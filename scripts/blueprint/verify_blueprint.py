#!/usr/bin/env python3
"""Static guard for the Reybain v2 voice-first workflow (see PLAN.md).

Fails fast (seconds, any OS, no Xcode) when a change re-introduces one of the seven "lessons"
(audio deadlock, volume flapping, deaf glasses mic, TTS echo cut-off, raw LaTeX speech, missing
Photos access, lost follow-up context), leaks secrets/prints, turns the glasses camera on outside
captures, or drifts from project.pbxproj.

Usage:  python3 scripts/blueprint/verify_blueprint.py [--repo PATH]
Exit status 1 if any check fails. Warnings never fail the run.
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path

RESULTS: list[tuple[str, str, str]] = []  # (status, id, message)


def ok(check_id: str, msg: str) -> None:
    RESULTS.append(("PASS", check_id, msg))


def fail(check_id: str, msg: str) -> None:
    RESULTS.append(("FAIL", check_id, msg))


def warn(check_id: str, msg: str) -> None:
    RESULTS.append(("WARN", check_id, msg))


def check(check_id: str, condition: bool, msg: str) -> None:
    (ok if condition else fail)(check_id, msg)


def strip_comments(swift: str) -> str:
    """Remove // line comments and /* */ blocks (good enough for these checks)."""
    swift = re.sub(r"/\*.*?\*/", "", swift, flags=re.S)
    return re.sub(r"//[^\n]*", "", swift)


def function_body(swift: str, signature_regex: str) -> str | None:
    """Text of the brace-balanced body following the first match of `signature_regex`."""
    match = re.search(signature_regex, swift)
    if not match:
        return None
    start = swift.find("{", match.end())
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(swift)):
        if swift[i] == "{":
            depth += 1
        elif swift[i] == "}":
            depth -= 1
            if depth == 0:
                return swift[start : i + 1]
    return None


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repo", default=Path(__file__).resolve().parents[2], type=Path)
    args = parser.parse_args()
    repo: Path = args.repo

    def read(rel: str) -> str:
        path = repo / rel
        if not path.exists():
            fail("files", f"missing {rel}")
            return ""
        return path.read_text(encoding="utf-8")

    vm = read("Reybain/Views/VoiceAgent/VoiceAgentViewModel.swift")
    gemini = read("Reybain/Services/GeminiLive/GeminiLiveService.swift")
    prompt_v2 = read("Reybain/Services/Speech/PromptV2.swift")
    tts = read("Reybain/Services/TTS/TTSService.swift")
    audio = read("Reybain/Services/Audio/AudioSessionManager.swift")
    voice = read("Reybain/Services/Voice/VoiceCommandService.swift")
    pbxproj = read("Reybain.xcodeproj/project.pbxproj")

    # --- Project integrity: two-way sync between filesystem and project.pbxproj.
    for folder in ("Reybain", "ReybainTests"):
        for path in sorted((repo / folder).rglob("*.swift")):
            if f"path = {path.name};" not in pbxproj and f"/* {path.name} */" not in pbxproj:
                rel = path.relative_to(repo).as_posix()
                fail("project", f"{rel} is not in project.pbxproj "
                                f"(run `python3 scripts/pbxproj_files.py add {rel}` and commit project.pbxproj)")
    try:
        sys.dont_write_bytecode = True
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from pbxproj_files import Project

        listed = Project(pbxproj).swift_paths()
    except Exception as exc:
        fail("project", f"scripts/pbxproj_files.py cannot read project.pbxproj: {exc}")
        listed = []
    for rel in listed:
        if not (repo / rel).is_file() and not (repo / f"{rel}.example").is_file():
            fail("project", f"project.pbxproj lists {rel}, which does not exist "
                            f"(run `python3 scripts/pbxproj_files.py remove {rel}`)")
    if not any(r[0] == "FAIL" and r[1] == "project" for r in RESULTS):
        ok("project", f"every Swift source/test file is registered in project.pbxproj, and all {len(listed)} "
                      "Swift files it lists exist")

    # --- Lesson 1: one owner of the microphone tap (shared audio tap).
    allowed_taps = {
        "VoiceCommandService.swift": "owner of the shared mic tap",
        "SessionRecorder.swift": "fallback only when VoiceCommandService is not capturing",
        "AudioCaptureService.swift": "live-video capture, runs with the recognizer stopped",
    }
    offenders = []
    for path in (repo / "Reybain").rglob("*.swift"):
        code = strip_comments(path.read_text(encoding="utf-8"))
        if re.search(r"(inputNode|input)\s*\.\s*installTap\s*\(\s*onBus", code) and path.name not in allowed_taps:
            offenders.append(str(path.relative_to(repo)))
    check("lesson1", not offenders,
          "mic input taps only in " + ", ".join(allowed_taps) + ("" if not offenders else f" — NEW TAP in {offenders}"))
    recorder = strip_comments(read("Reybain/Services/Recording/SessionRecorder.swift"))
    check("lesson1", "appendMicAudio" in recorder and "isSharingVoiceCommandTap" in recorder,
          "SessionRecorder reuses VoiceCommandService's tap (appendMicAudio / isSharingVoiceCommandTap)")

    # --- Lesson 2: stable .playAndRecord/.default session for the glasses, no route ping-pong.
    glasses_fn = function_body(audio, r"func\s+configureForGlasses\s*\(") or ""
    glasses_code = strip_comments(glasses_fn)
    check("lesson2", ".playAndRecord" in glasses_code and "mode: .default" in glasses_code,
          "configureForGlasses uses .playAndRecord + mode .default")
    for option in (".mixWithOthers", ".allowBluetoothHFP", ".allowBluetoothA2DP", ".defaultToSpeaker"):
        check("lesson2", option in glasses_code, f"configureForGlasses keeps {option}")
    route = strip_comments(function_body(audio, r"func\s+handleAudioRouteChange\s*\(") or "")
    check("lesson2", route != "" and "setPreferredInput" not in route,
          "handleAudioRouteChange never calls setPreferredInput (recursive route-change loop)")

    # --- Lesson 3: the glasses mic + Vietnamese phonetic wake word.
    for phrase in ("ô kê vi dơn", "ok vi dơn", "vi dơn", "ok vision"):
        check("lesson3", f'"{phrase}"' in voice, f'wake word variant "{phrase}" present')
    check("lesson3", "findBluetoothHFPInput" in audio and "ray-ban" in audio.lower(),
          "Ray-Ban/Meta HFP input is preferred")

    # --- Lesson 4: no false barge-in from the temple speaker's echo.
    echo = re.search(r"ttsEchoSettleNanoseconds:\s*UInt64\s*=\s*([\d_]+)", vm)
    check("lesson4", bool(echo) and int(echo.group(1).replace("_", "")) >= 350_000_000,
          "echo settle delay >= 350 ms before the mic reopens")
    speak = strip_comments(function_body(vm, r"func\s+speakResponse\s*\(") or "")
    i_state, i_pause, i_speak = speak.find("agentState = .speaking"), speak.find("isBargeInPaused = true"), speak.find("ttsService.speak(")
    check("lesson4", -1 not in (i_state, i_pause, i_speak) and i_state < i_speak and i_pause < i_speak,
          "speakResponse sets .speaking + isBargeInPaused BEFORE queueing speech")
    partial = strip_comments(function_body(vm, r"onPartialAnswer\s*=") or "")
    check("lesson4", "isBargeInPaused = true" in partial and "readingEngine.start" in partial
          and partial.find("isBargeInPaused = true") < partial.find("readingEngine.start"),
          "streamed v2.1 speech also pauses barge-in before starting ReadingEngine")

    # --- Lesson 5 (v2.1): voice-first PromptV2 contract, VietMathSpeech + cleanSpokenAudio.
    check("lesson5", "PromptV2.systemPrompt" in gemini, "GeminiLiveService wires PromptV2.systemPrompt")
    for token in ("TYPE:", "Q1:", "L1:", "FINAL:"):
        check("lesson5", token in prompt_v2, f"PromptV2 defines v2.1 tag {token}")
    check("lesson5", "DISPLAY:" not in prompt_v2 and "shown on the phone screen" not in prompt_v2.lower(),
          "PromptV2 has no legacy DISPLAY channel or phone-screen pointer")
    check("lesson5", "never tell the user to look at the phone or at a screen" in prompt_v2.lower(),
          "PromptV2 forbids sending the wearer to the phone screen (D5)")
    check("lesson5", "under 250 characters" not in prompt_v2.lower(), "the old ultra-concise prompt is gone")
    check("lesson5", "static func cleanSpokenAudio" in tts and "cleanSpokenAudio(text)" in tts
          and "VietMathSpeech.render" in tts,
          "TTSService runs VietMathSpeech before cleanSpokenAudio safety net")

    # --- Lesson 6: Camera Roll scanner for the temple shutter (Meta albums only).
    check("lesson6", "class RecentPhotoScanner" in vm and "PHPhotoLibraryChangeObserver" in vm,
          "RecentPhotoScanner observes the photo library")
    check("lesson6", len(re.findall(r"requestAuthorizationIfNeeded\(\)", strip_comments(vm))) >= 2,
          "Photos permission is actually requested (not only defined)")
    check("lesson6", "recentPhotoWindow: TimeInterval = 120" in vm, "120 s recent-photo window")
    check("lesson6", "requestImageDataAndOrientation" in vm, "the ORIGINAL full-resolution photo is loaded")
    try:
        plist = plistlib.loads((repo / "Reybain/Resources/Info.plist").read_bytes())
        for key in ("NSPhotoLibraryUsageDescription", "NSMicrophoneUsageDescription",
                    "NSCameraUsageDescription", "NSBluetoothAlwaysUsageDescription",
                    "NSSpeechRecognitionUsageDescription"):
            check("lesson6", bool(plist.get(key)), f"Info.plist {key}")
    except Exception as exc:
        fail("lesson6", f"Info.plist unreadable: {exc}")

    # --- Lesson 7: follow-up context.
    check("lesson7", re.search(r"maxHistoryEntries\s*=\s*6\b", gemini) is not None, "6-entry conversation history")
    check("lesson7", "conversationHistory + [" in gemini or "contentsToSend = conversationHistory" in gemini,
          "history is sent with every request")

    # --- Workflow & v2 invariants.
    send = strip_comments(function_body(vm, r"func\s+sendCommand\s*\(") or "")
    phrase_lists = [name for name in ("visualKeywords", "visualPhrases", "requiresAttachedPhoto") if name in vm]
    check("workflow", "sendRESTMessage(command" in send and not phrase_lists,
          "Gemini receives the wearer's words verbatim (no fixed phrase list"
          + (f"; found {', '.join(phrase_lists)}" if phrase_lists else "") + ")")
    check("workflow", not re.search(r"MLX|Kokoro|GemmaLocal|OpenClaw|AppleFoundation", read("project.yml")),
          "lean app: no on-device LLM / extra backends in the project")
    check("workflow", "language the user used" in prompt_v2, "answers in the language the wearer asked in")
    check("workflow", "streamGenerateContent" in gemini and "URLSession.shared" not in strip_comments(gemini),
          "streamed requests on a dedicated session (idle timeout, test-injectable)")
    check("workflow", "case .rateLimited" in gemini and "case .badKey" in gemini and "overallDeadline" in gemini,
          "retry policy by failure type with an overall deadline")
    check("workflow", "x-goog-api-key" in gemini and "?key=" not in strip_comments(gemini),
          "API key sent in the x-goog-api-key header, never in the URL")
    check("workflow", "captureToken" in gemini and "onCaptureRequested" in vm,
          "agent loop: the model can ask the app to take a photo")
    glasses = read("Reybain/Managers/GlassesManager.swift")
    plist_text = read("Reybain/Resources/Info.plist")
    project_text = read("project.yml")
    check("workflow", ".photo.capturePhoto(resolution:" in glasses
          and "addInputs(configuration:" in glasses and "MWDATInputs" in project_text
          and "acquireGlassesPhoto" in vm and "onCaptureButton" in vm
          and "NSLocalNetworkUsageDescription" in plist_text,
          "glasses photo goes straight to the app (DAT capture button + full-resolution still), "
          "Camera Roll only as fallback")

    # --- Camera on demand (T7.9): never activate glasses camera on session start or wake word.
    start_session_body = strip_comments(function_body(vm, r"func\s+startSession\s*\(") or "")
    check("camera", "startStreaming" not in start_session_body and "captureFullResolutionPhoto" not in start_session_body,
          "startSession never activates the glasses camera (LED stays off until capture)")

    # --- Logging & secret hygiene (T2.4).
    logged_files = [
        "Reybain/App/ReybainApp.swift",
        "Reybain/Managers/GlassesManager.swift",
        "Reybain/Views/VoiceAgent/VoiceAgentViewModel.swift",
        "Reybain/Services/GeminiLive/GeminiLiveService.swift",
        "Reybain/Services/Voice/VoiceCommandService.swift",
        "Reybain/Services/Audio/AudioSessionManager.swift",
        "Reybain/Services/TTS/TTSService.swift",
    ]
    print_offenders = []
    for rel in logged_files:
        code = strip_comments(read(rel))
        if re.search(r"\b(?:print|NSLog)\s*\(", code):
            print_offenders.append(rel)
    check("logging", not print_offenders,
          "core files use AppLog (no raw print/NSLog"
          + (f"; found in {', '.join(print_offenders)}" if print_offenders else "") + ")")
    check("logging", "key.prefix(6)" not in strip_comments(gemini),
          "GeminiLiveService never logs API key prefixes")

    # --- v2 UI: no active app references to legacy KaTeX DISPLAY / SpokenMath.
    legacy_refs = []
    for path in (repo / "Reybain").rglob("*.swift"):
        if path.name == "SolutionView.swift":
            continue
        code = strip_comments(path.read_text(encoding="utf-8"))
        for symbol in ("SolutionWebView", "SolutionSheet", "SolutionButton", "latestSolution", "parseDualChannel", "SpokenMath"):
            if symbol in code:
                legacy_refs.append(f"{path.name}:{symbol}")
    check("v2-ui", not legacy_refs,
          "no app code references legacy KaTeX DISPLAY or SpokenMath"
          + (f" — FOUND {legacy_refs}" if legacy_refs else ""))

    # --- Security: no API keys in source.
    key_patterns = re.compile(r"AIza[0-9A-Za-z_-]{30,}|AQ\.Ab[0-9A-Za-z_-]{20,}|QVEuQWI[A-Za-z0-9+/=]{20,}|QUl6YV[A-Za-z0-9+/=]{20,}")
    leaks = []
    for folder in ("Reybain", "ReybainTests", "scripts", ".github"):
        for path in (repo / folder).rglob("*"):
            if path.is_file() and path.suffix in {".swift", ".py", ".sh", ".yml", ".yaml", ".plist", ".xcconfig", ".json", ".md"}:
                if key_patterns.search(path.read_text(encoding="utf-8", errors="ignore")):
                    leaks.append(str(path.relative_to(repo)))
    check("security", not leaks, "no Gemini API keys in source" + ("" if not leaks else f" — FOUND in {leaks}"))

    # --- Warnings (never fail the run).
    build_ipa = (repo / ".github/workflows/build-ipa.yml")
    if build_ipa.exists() and "push:" not in build_ipa.read_text(encoding="utf-8"):
        warn("ci", "build-ipa.yml only runs on workflow_dispatch; manual trigger saves macOS runner quota.")
    if (repo / "Reybain/Resources/SolutionRenderer").exists() or (repo / "Reybain/Views/Components/SolutionView.swift").exists():
        warn("cleanup", "Unused legacy KaTeX files (SolutionView.swift / SolutionRenderer) can be removed via scripts/pbxproj_files.py to shrink IPA size.")

    width = max(len(r[1]) for r in RESULTS)
    for status, check_id, msg in RESULTS:
        print(f"[{status}] {check_id.ljust(width)}  {msg}")
    failures = sum(1 for r in RESULTS if r[0] == "FAIL")
    print(f"\n{len(RESULTS) - failures} passed/warned, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
