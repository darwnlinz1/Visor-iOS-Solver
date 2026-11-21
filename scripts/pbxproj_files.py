#!/usr/bin/env python3
"""Register or unregister Swift files in OpenVision.xcodeproj/project.pbxproj (PLAN.md T2.1).

The .xcodeproj is committed and CI never runs xcodegen, so a Swift file only compiles once it is
listed in project.pbxproj. PLAN.md §0 rule 5: change that file only through this script.

  python3 scripts/pbxproj_files.py add OpenVision/Services/Speech/VietMathSpeech.swift [...]
  python3 scripts/pbxproj_files.py remove OpenVision/Views/Components/SolutionView.swift [...]
  python3 scripts/pbxproj_files.py remove-folder-ref OpenVision/Resources/SolutionRenderer
  python3 scripts/pbxproj_files.py --self-test
  Add --dry-run to print the diff instead of writing project.pbxproj.

add                Files under OpenVision/ join the app target (Sources phase
                   5B369180DFE2DD0B99684491), files under OpenVisionTests/ the test target
                   (4082EAA7B9C9E911E29F7B44). Writes the PBXFileReference, the PBXBuildFile, the
                   child entry of the folder's PBXGroup and the Sources entry, and creates the
                   PBXGroup chain for a folder the project does not have yet. Object IDs are 24
                   uppercase hex digits taken from SHA-1 of the path (never an ID already in the
                   file), so a file always gets the same IDs. Running it again changes nothing.
remove             The reverse: drops every entry of the file, then the groups it left empty.
remove-folder-ref  Drops a folder reference (lastKnownFileType = folder, e.g. the KaTeX bundle
                   OpenVision/Resources/SolutionRenderer) with its build file and Resources entry.
--self-test        Runs every command on a temporary copy of project.pbxproj (never the real one):
                   add + remove of fake files (one in a new nested folder) must give back the
                   original bytes, and so must a folder reference round trip.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import posixpath
import re
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = "OpenVision.xcodeproj/project.pbxproj"

# Top-level source folder -> Sources build phase of the target that compiles it.
TARGET_PHASES = {
    "OpenVision": "5B369180DFE2DD0B99684491",       # app target
    "OpenVisionTests": "4082EAA7B9C9E911E29F7B44",  # unit-test target
}

SECTION = re.compile(r"^/\* (Begin|End) (\w+) section \*/$")
OBJECT_START = re.compile(r"^\t\t([0-9A-F]{24})(?: /\* (.*?) \*/)? = \{(.*)$")
ATTR_LINE = re.compile(r"^\t\t\t(\w+) = (.*);$")
LIST_START = re.compile(r"^\t\t\t(\w+) = \($")
LIST_ITEM = re.compile(r"^\t\t\t\t([0-9A-F]{24})(?: /\* (.*?) \*/)?,$")
INLINE_ATTR = re.compile(r'(\w+) = ("(?:[^"\\]|\\.)*"|[^;]*);')
ID_TOKEN = re.compile(r"\b[0-9A-F]{24}\b")
STRINGS_AND_COMMENTS = re.compile(r'"(?:[^"\\]|\\.)*"|/\*.*?\*/|//[^\n]*', re.S)
UNQUOTED_OK = re.compile(r"^[A-Za-z0-9_$./]+$")


class PbxprojError(Exception):
    """A request the script refuses (bad path, unexpected project layout...)."""


@dataclass
class Obj:
    id: str
    comment: str | None
    isa: str
    section: str
    start: int  # index of the first line
    end: int  # index of the last line (== start for one-line objects)
    attrs: dict[str, str] = field(default_factory=dict)  # scalar values, unquoted
    lists: dict[str, list[tuple[str, str | None, int]]] = field(default_factory=dict)  # [(id, comment, line)]
    list_bounds: dict[str, tuple[int, int]] = field(default_factory=dict)  # name -> (line of "(", line of ")")


def unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        escapes = {"n": "\n", "t": "\t"}
        return re.sub(r"\\(.)", lambda m: escapes.get(m.group(1), m.group(1)), value[1:-1])
    return value


def quote(value: str) -> str:
    if UNQUOTED_OK.match(value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def norm_dir(path: str) -> str:
    path = posixpath.normpath(path) if path else ""
    return "" if path == "." else path


def lint(text: str) -> list[str]:
    """Structural problems: unbalanced brackets, duplicate object IDs, references to IDs that
    no object defines. Empty list = the file is sane."""
    problems = []
    code = STRINGS_AND_COMMENTS.sub(" ", text)
    for opening, closing in ("{}", "()"):
        depth = 0
        for char in code:
            depth += (char == opening) - (char == closing)
            if depth < 0:
                break
        if depth != 0:
            problems.append(f"unbalanced {opening}{closing}")
    defined: dict[str, int] = {}
    for line in text.split("\n"):
        match = OBJECT_START.match(line)
        if match:
            defined[match.group(1)] = defined.get(match.group(1), 0) + 1
    problems += [f"object {oid} is defined {count} times" for oid, count in defined.items() if count > 1]
    dangling = sorted(set(ID_TOKEN.findall(code)) - set(defined))
    problems += [f"{oid} is referenced but not defined" for oid in dangling]
    return problems


class Project:
    """project.pbxproj as lines, with the objects, groups and build phases it defines."""

    def __init__(self, text: str):
        if "\r" in text:
            raise PbxprojError("project.pbxproj has CR line endings; expected LF only")
        self.lines = text.split("\n")
        self.parse()

    @property
    def text(self) -> str:
        return "\n".join(self.lines)

    # --- Reading ---------------------------------------------------------------------------

    def parse(self) -> None:
        self.objects: dict[str, Obj] = {}
        self.sections: dict[str, tuple[int, int]] = {}
        section, begin, i = None, 0, 0
        while i < len(self.lines):
            line = self.lines[i]
            marker = SECTION.match(line)
            if marker:
                if marker.group(1) == "Begin":
                    section, begin = marker.group(2), i
                else:
                    self.sections[marker.group(2)] = (begin, i)
                    section = None
                i += 1
                continue
            match = OBJECT_START.match(line) if section else None
            if not match:
                i += 1
                continue
            oid, comment, rest = match.groups()
            if rest.strip():  # one-line object: `ID /* c */ = {isa = ...; ...; };`
                if not rest.endswith("};"):
                    raise PbxprojError(f"line {i + 1}: cannot parse object {oid}")
                attrs = {key: unquote(value) for key, value in INLINE_ATTR.findall(rest[:-2])}
                self.objects[oid] = Obj(oid, comment, attrs.get("isa", ""), section, i, i, attrs)
                i += 1
                continue
            end = i + 1
            while end < len(self.lines) and self.lines[end] != "\t\t};":
                end += 1
            if end == len(self.lines):
                raise PbxprojError(f"line {i + 1}: object {oid} never closes")
            obj = Obj(oid, comment, "", section, i, end)
            j = i + 1
            while j < end:
                list_start = LIST_START.match(self.lines[j])
                if list_start:
                    name, items, k = list_start.group(1), [], j + 1
                    while k < end and self.lines[k] != "\t\t\t);":
                        item = LIST_ITEM.match(self.lines[k])
                        if item:
                            items.append((item.group(1), item.group(2), k))
                        k += 1
                    obj.lists[name], obj.list_bounds[name] = items, (j, k)
                    j = k + 1
                    continue
                attr = ATTR_LINE.match(self.lines[j])
                if attr:
                    obj.attrs[attr.group(1)] = unquote(attr.group(2))
                j += 1
            obj.isa = obj.attrs.get("isa", "")
            self.objects[oid] = obj
            i = end + 1
        self._resolve_paths()

    def _main_group(self) -> str:
        for obj in self.objects.values():
            if obj.isa == "PBXProject":
                main = ID_TOKEN.search(obj.attrs.get("mainGroup", ""))
                if main and main.group(0) in self.objects:
                    return main.group(0)
        raise PbxprojError("no PBXProject mainGroup in project.pbxproj")

    def _resolve_paths(self) -> None:
        """Repo-relative folder of every group and path of every file reference, by walking the
        group tree from the main group (sourceTree <group> = relative to the parent group)."""
        self.group_dir: dict[str, str] = {}
        self.ref_path: dict[str, str] = {}
        self.parent: dict[str, str] = {}

        def located(base: str | None, obj: Obj) -> str | None:
            tree = obj.attrs.get("sourceTree", "<group>")
            if tree == "SOURCE_ROOT":
                base = ""
            elif tree != "<group>" or base is None:
                return None
            path = obj.attrs.get("path")
            return norm_dir(posixpath.join(base, path)) if path else base

        def walk(gid: str, base: str | None) -> None:
            group = self.objects[gid]
            folder = located(base, group)
            if folder is not None:
                self.group_dir[gid] = folder
            for cid, _, _ in group.lists.get("children", []):
                child = self.objects.get(cid)
                if child is None or cid in self.parent:
                    continue
                self.parent[cid] = gid
                if child.isa == "PBXGroup":
                    walk(cid, folder)
                elif child.isa == "PBXFileReference":
                    path = located(folder, child)
                    if path is not None:
                        self.ref_path[cid] = path

        walk(self._main_group(), "")

    def group_for_dir(self, folder: str) -> str | None:
        """The group that maps `folder` (its own `path` names the folder), or None."""
        found = [gid for gid, d in self.group_dir.items()
                 if d == folder and self.objects[gid].attrs.get("path", ".") != "."]
        if len(found) > 1:
            raise PbxprojError(f"{folder}: several groups map this folder ({', '.join(found)})")
        return found[0] if found else None

    def refs_at(self, path: str) -> list[str]:
        return [rid for rid, p in self.ref_path.items() if p == path]

    def build_files_of(self, ref: str) -> list[Obj]:
        return [o for o in self.objects.values()
                if o.isa == "PBXBuildFile" and ID_TOKEN.findall(o.attrs.get("fileRef", ""))[:1] == [ref]]

    def phase_members(self, phase: str) -> set[str]:
        return {item[0] for item in self.objects[phase].lists.get("files", [])}

    def swift_paths(self) -> list[str]:
        """Repo-relative path of every Swift file reference in the project."""
        return sorted(p for rid, p in self.ref_path.items() if p.endswith(".swift"))

    def compiled_by(self, phase: str) -> set[str]:
        """Repo-relative paths of the files a Sources phase compiles."""
        members = self.phase_members(phase)
        return {self.ref_path[ref] for ref in self.ref_path
                if any(bf.id in members for bf in self.build_files_of(ref))}

    def resources_phase_of(self, sources_phase: str) -> str:
        for obj in self.objects.values():
            phases = [item[0] for item in obj.lists.get("buildPhases", [])]
            if obj.isa == "PBXNativeTarget" and sources_phase in phases:
                for pid in phases:
                    if self.objects.get(pid) and self.objects[pid].isa == "PBXResourcesBuildPhase":
                        return pid
        raise PbxprojError(f"no Resources phase next to Sources phase {sources_phase}")

    def check_phase(self, phase: str) -> None:
        obj = self.objects.get(phase)
        if obj is None or obj.isa != "PBXSourcesBuildPhase":
            raise PbxprojError(f"Sources phase {phase} is not in project.pbxproj; update TARGET_PHASES")

    # --- Writing (every helper re-parses, so indexes never go stale) -----------------------

    def new_id(self, kind: str, key: str) -> str:
        """24 uppercase hex digits from SHA-1("kind:key"), salted until no object uses it."""
        used = set(ID_TOKEN.findall(self.text))
        salt = 0
        while True:
            seed = f"{kind}:{key}" if salt == 0 else f"{kind}:{key}:{salt}"
            oid = hashlib.sha1(seed.encode("utf-8")).hexdigest()[:24].upper()
            if oid not in used:
                return oid
            salt += 1

    def _insert_object(self, section: str, oid: str, lines: list[str]) -> None:
        """Into `section`, before the first object whose ID sorts after `oid` (Xcode's order)."""
        if section not in self.sections:
            raise PbxprojError(f"no {section} section in project.pbxproj")
        position = self.sections[section][1]
        for obj in sorted((o for o in self.objects.values() if o.section == section), key=lambda o: o.start):
            if obj.id > oid:
                position = obj.start
                break
        self.lines[position:position] = lines
        self.parse()

    def _insert_child(self, gid: str, cid: str, name: str, is_group: bool) -> None:
        """Groups first, then files, each alphabetical (case-insensitive, like XcodeGen)."""
        group = self.objects[gid]
        if "children" not in group.lists:
            raise PbxprojError(f"group {gid} has no children list")
        items = group.lists["children"]
        opening, closing = group.list_bounds["children"]
        subgroups = [it for it in items if self.objects.get(it[0]) and self.objects[it[0]].isa == "PBXGroup"]
        files = [it for it in items if it not in subgroups]
        candidates = subgroups if is_group else files
        position = next((line for _, comment, line in candidates if (comment or "").lower() > name.lower()), None)
        if position is None:
            position = (subgroups[-1][2] + 1 if subgroups else opening + 1) if is_group else closing
        self.lines.insert(position, f"\t\t\t\t{cid} /* {name} */,")
        self.parse()

    def _insert_phase_entry(self, phase: str, bid: str, comment: str) -> None:
        """Alphabetical by file name (case-sensitive, like XcodeGen)."""
        obj = self.objects[phase]
        name = comment.rsplit(" in ", 1)[0]
        position = obj.list_bounds["files"][1]
        for _, other, line in obj.lists.get("files", []):
            if (other or "").rsplit(" in ", 1)[0] > name:
                position = line
                break
        self.lines.insert(position, f"\t\t\t\t{bid} /* {comment} */,")
        self.parse()

    def _delete_lines(self, doomed: set[int]) -> None:
        for index in sorted(doomed, reverse=True):
            del self.lines[index]
        self.parse()

    def _ensure_group(self, folder: str, changes: list[str]) -> str:
        gid = self.group_for_dir(folder)
        if gid:
            return gid
        if "/" not in folder:
            raise PbxprojError(f"project.pbxproj has no group for the top-level folder {folder}/")
        parent_folder, name = posixpath.split(folder)
        parent = self._ensure_group(parent_folder, changes)
        gid = self.new_id("PBXGroup", folder)
        self._insert_object("PBXGroup", gid, [
            f"\t\t{gid} /* {name} */ = {{",
            "\t\t\tisa = PBXGroup;",
            "\t\t\tchildren = (",
            "\t\t\t);",
            f"\t\t\tpath = {quote(name)};",
            '\t\t\tsourceTree = "<group>";',
            "\t\t};",
        ])
        self._insert_child(parent, gid, name, is_group=True)
        changes.append(f"new group {folder} ({gid})")
        return gid

    def _add_ref(self, path: str, file_type: str, changes: list[str]) -> str:
        refs = self.refs_at(path)
        if refs:
            return refs[0]
        folder, name = posixpath.split(path)
        gid = self._ensure_group(folder, changes)
        ref = self.new_id("PBXFileReference", path)
        self._insert_object("PBXFileReference", ref, [
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {file_type}; "
            f'path = {quote(name)}; sourceTree = "<group>"; }};'])
        self._insert_child(gid, ref, name, is_group=False)
        changes.append(f"file reference {ref}")
        return ref

    def _add_to_phase(self, path: str, ref: str, phase: str, phase_name: str, changes: list[str]) -> None:
        members = self.phase_members(phase)
        if any(bf.id in members for bf in self.build_files_of(ref)):
            return
        name = posixpath.basename(path)
        bid = self.new_id("PBXBuildFile", f"{path}@{phase}")
        self._insert_object("PBXBuildFile", bid, [
            f"\t\t{bid} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};"])
        self._insert_phase_entry(phase, bid, f"{name} in {phase_name}")
        changes.append(f"build file {bid} in {phase_name} phase {phase}")

    def add_swift(self, path: str) -> list[str]:
        phase = TARGET_PHASES[path.split("/", 1)[0]]
        self.check_phase(phase)
        changes: list[str] = []
        ref = self._add_ref(path, "sourcecode.swift", changes)
        self._add_to_phase(path, ref, phase, "Sources", changes)
        return changes

    def add_folder_ref(self, path: str) -> list[str]:
        """Self-test helper: a folder reference copied into the app's Resources phase."""
        phase = self.resources_phase_of(TARGET_PHASES["OpenVision"])
        changes: list[str] = []
        ref = self._add_ref(path, "folder", changes)
        self._add_to_phase(path, ref, phase, "Resources", changes)
        return changes

    def remove_path(self, path: str, folder_ref: bool = False) -> list[str]:
        refs = self.refs_at(path)
        if folder_ref:
            wrong = [r for r in refs if self.objects[r].attrs.get("lastKnownFileType") != "folder"]
            if wrong:
                raise PbxprojError(f"{path} is not a folder reference (lastKnownFileType = "
                                   f"{self.objects[wrong[0]].attrs.get('lastKnownFileType')})")
        changes: list[str] = []
        for ref in refs:
            gid = self.parent[ref]
            doomed_ids = {ref} | {bf.id for bf in self.build_files_of(ref)}
            doomed = set()
            for obj in self.objects.values():
                if obj.id in doomed_ids:
                    doomed.update(range(obj.start, obj.end + 1))
                for items in obj.lists.values():
                    doomed.update(line for item_id, _, line in items if item_id in doomed_ids)
            self._delete_lines(doomed)
            changes.append(f"removed {', '.join(sorted(doomed_ids))}")
            # Groups the removal left empty go too (never the target's top-level folder).
            while (gid in self.objects and not self.objects[gid].lists.get("children")
                   and "/" in self.group_dir.get(gid, "")):
                parent = self.parent[gid]
                doomed = set(range(self.objects[gid].start, self.objects[gid].end + 1))
                doomed.update(line for item_id, _, line in self.objects[parent].lists["children"] if item_id == gid)
                changes.append(f"removed empty group {self.group_dir[gid]} ({gid})")
                self._delete_lines(doomed)
                gid = parent
        return changes


# --- Command line ------------------------------------------------------------------------------


def repo_relative(raw: str, root: Path) -> str:
    path = Path(raw)
    if path.is_absolute():
        try:
            path = path.resolve().relative_to(root.resolve())
        except ValueError:
            raise PbxprojError(f"{raw}: not inside {root}") from None
    rel = posixpath.normpath(path.as_posix())
    parts = rel.split("/")
    if rel.startswith("../") or rel == ".." or "*/" in rel or "\n" in rel:
        raise PbxprojError(f"{raw}: not a path inside the repository")
    if parts[0] not in TARGET_PHASES or len(parts) < 2:
        raise PbxprojError(f"{raw}: must be under {'/ or '.join(TARGET_PHASES)}/")
    return rel


def apply(command: str, raw_paths: list[str], root: Path, dry_run: bool = False, quiet: bool = False) -> int:
    pbxproj = root / PBXPROJ
    original = pbxproj.read_bytes().decode("utf-8")
    project = Project(original)
    for raw in raw_paths:
        path = repo_relative(raw, root)
        if command in ("add", "remove") and not path.endswith(".swift"):
            raise PbxprojError(f"{raw}: only Swift files (*.swift) are handled")
        if command == "add":
            if not (root / path).is_file():
                raise PbxprojError(f"{raw}: no such file (create it first)")
            changes = project.add_swift(path)
        elif command == "remove":
            changes = project.remove_path(path)
        else:
            changes = project.remove_path(path, folder_ref=True)
        if not quiet:
            print(f"{command} {path}: " + ("; ".join(changes) if changes else "nothing to do"))
    problems = lint(project.text)
    if problems:
        raise PbxprojError("refusing to write a broken project.pbxproj: " + "; ".join(problems))
    if project.text == original:
        return 0
    if dry_run:
        sys.stdout.writelines(difflib.unified_diff(
            original.splitlines(True), project.text.splitlines(True), PBXPROJ, PBXPROJ))
        print("(dry run: project.pbxproj not written)")
    else:
        pbxproj.write_bytes(project.text.encode("utf-8"))
    return 0


def self_test(root: Path) -> int:
    real = root / PBXPROJ
    real_before = real.read_bytes()
    checks = 0

    def expect(condition: bool, message: str) -> None:
        nonlocal checks
        if not condition:
            raise AssertionError(message)
        checks += 1

    with tempfile.TemporaryDirectory(prefix="pbxproj-self-test-") as tmp:
        work = Path(tmp)
        copy = work / PBXPROJ
        copy.parent.mkdir(parents=True)
        copy.write_bytes(real_before)
        original = real_before.decode("utf-8")
        expect(not lint(original), f"the real project.pbxproj fails lint: {lint(original)}")

        def run(command: str, *paths: str) -> str:
            apply(command, list(paths), work, quiet=True)
            return copy.read_bytes().decode("utf-8")

        fake_app = "OpenVision/Services/PbxprojSelfTest/Nested/PbxprojSelfTestFake.swift"
        fake_existing = "OpenVision/Managers/PbxprojSelfTestManager.swift"
        fake_test = "OpenVisionTests/PbxprojSelfTest/PbxprojSelfTestFakeTests.swift"
        for fake in (fake_app, fake_existing, fake_test):
            (work / fake).parent.mkdir(parents=True, exist_ok=True)
            (work / fake).write_text("// pbxproj self-test\n", encoding="utf-8")
        before = Project(original)
        expect(before.group_for_dir("OpenVision/Services/PbxprojSelfTest") is None, "the fake folder must be new")

        added = run("add", fake_app, fake_existing, fake_test)
        project = Project(added)
        expect(not lint(added), f"lint after add: {lint(added)}")
        inserted_only = all(op == "equal" or op == "insert" for op, *_ in
                            difflib.SequenceMatcher(None, original.split("\n"), added.split("\n")).get_opcodes())
        expect(inserted_only, "add must only insert lines")
        app_phase, test_phase = TARGET_PHASES["OpenVision"], TARGET_PHASES["OpenVisionTests"]
        for fake, phase, other in ((fake_app, app_phase, test_phase), (fake_existing, app_phase, test_phase),
                                   (fake_test, test_phase, app_phase)):
            refs = project.refs_at(fake)
            expect(len(refs) == 1, f"{fake}: one file reference")
            ref = refs[0]
            expect(ref == hashlib.sha1(f"PBXFileReference:{fake}".encode()).hexdigest()[:24].upper(),
                   f"{fake}: file reference ID is SHA-1 of the path")
            expect(re.fullmatch(r"[0-9A-F]{24}", ref) is not None, f"{fake}: 24 uppercase hex digits")
            group = project.parent[ref]
            expect(project.group_dir[group] == posixpath.dirname(fake), f"{fake}: child of its folder's group")
            expect(fake in project.compiled_by(phase), f"{fake}: in Sources phase {phase}")
            expect(fake not in project.compiled_by(other), f"{fake}: not in Sources phase {other}")
            expect(len(project.build_files_of(ref)) == 1, f"{fake}: one build file")
        nested = project.parent[project.refs_at(fake_app)[0]]
        middle = project.parent[nested]
        expect(project.group_dir[middle] == "OpenVision/Services/PbxprojSelfTest", "new parent group created")
        expect(project.parent[middle] == before.group_for_dir("OpenVision/Services"),
               "the new folder hangs under the existing Services group")
        expect(project.parent[project.parent[project.refs_at(fake_test)[0]]] == before.group_for_dir("OpenVisionTests"),
               "the new test folder hangs under the OpenVisionTests group")
        expect(project.parent[project.refs_at(fake_existing)[0]] == before.group_for_dir("OpenVision/Managers"),
               "a file in an existing folder joins that folder's group")

        expect(run("add", fake_app, fake_existing, fake_test) == added, "add is idempotent")
        removed = run("remove", fake_app, fake_existing, fake_test)
        expect(removed == original, "add + remove gives back the original bytes")
        expect(run("remove", fake_app, fake_existing, fake_test) == original, "remove is idempotent")

        for bad in ("README.md", "scripts/pbxproj_files.py", "OpenVision/Missing/NotThere.swift",
                    "../OpenVision/App/OpenVisionApp.swift"):
            try:
                run("add", bad)
            except PbxprojError:
                checks += 1
            else:
                raise AssertionError(f"add {bad} must be refused")
        expect(copy.read_bytes() == real_before, "refused requests leave the file alone")

        folder = "OpenVision/Resources/PbxprojSelfTestFolder"
        project = Project(original)
        project.add_folder_ref(folder)
        copy.write_bytes(project.text.encode("utf-8"))
        expect(not lint(project.text), f"lint after a folder reference: {lint(project.text)}")
        ref = project.refs_at(folder)[0]
        expect(project.objects[ref].attrs.get("lastKnownFileType") == "folder", "folder reference type")
        expect(len(project.build_files_of(ref)) == 1, "folder reference copied by the Resources phase")
        expect(run("remove-folder-ref", folder) == original, "folder reference round trip gives back the original bytes")
        try:
            run("remove-folder-ref", "OpenVision/Resources/Info.plist")
        except PbxprojError:
            checks += 1
        else:
            raise AssertionError("remove-folder-ref must refuse a plain file reference")

        katex = "OpenVision/Resources/SolutionRenderer"
        if before.refs_at(katex):  # T4.4 removes it for real; until then, prove the command on a copy.
            ref = before.refs_at(katex)[0]
            doomed = {ref} | {bf.id for bf in before.build_files_of(ref)}
            stripped = run("remove-folder-ref", katex)
            gone = [line for line in original.split("\n") if line not in stripped.split("\n")]
            expect(len(stripped.split("\n")) == len(original.split("\n")) - 4 and len(gone) == 4,
                   f"{katex}: exactly 4 lines go (file ref, build file, group child, Resources entry)")
            expect(not any(oid in stripped for oid in doomed), f"{katex}: no reference left")
            expect(not lint(stripped), f"lint after removing {katex}: {lint(stripped)}")
            expect(run("remove-folder-ref", katex) == stripped, "remove-folder-ref is idempotent")

        probe = Project(original)
        taken = probe.new_id("PBXFileReference", "OpenVision/Collision.swift")
        probe.lines.insert(probe.sections["PBXFileReference"][1], f"\t\t{taken} /* taken */ = {{isa = PBXFileReference; }};")
        probe.parse()
        expect(probe.new_id("PBXFileReference", "OpenVision/Collision.swift") != taken, "an ID already in use is never reused")

    expect(real.read_bytes() == real_before, "the real project.pbxproj was not touched")
    print(f"pbxproj self-test passed ({checks} checks, real project.pbxproj untouched)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    parser.add_argument("command", nargs="?", choices=("add", "remove", "remove-folder-ref"))
    parser.add_argument("paths", nargs="*", help="repository-relative paths")
    parser.add_argument("--self-test", action="store_true", help="exercise every command on a temporary copy")
    parser.add_argument("--dry-run", action="store_true", help="print the diff, do not write project.pbxproj")
    args = parser.parse_args(argv)
    try:
        if args.self_test:
            return self_test(REPO_ROOT)
        if not args.command or not args.paths:
            parser.error("a command and at least one path are required (or --self-test)")
        return apply(args.command, args.paths, REPO_ROOT, dry_run=args.dry_run)
    except (PbxprojError, AssertionError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
