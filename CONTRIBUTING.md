# Contributing to OpenVision

Thank you for your interest in contributing to OpenVision! This document explains how the repository
works: branches, commits, tests and CI. The technical plan and the current task list are in
[PLAN.md](PLAN.md) (Vietnamese). Coding agents start with [AGENTS.md](AGENTS.md).

## Code of Conduct

Be respectful, inclusive, and constructive. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## How to Contribute

### Reporting Bugs

1. Check [existing issues](https://github.com/darwnlinz1/Visor-iOS-Solver/issues) first.
2. Open a new issue with the **🐛 Bug report** template:
   - Clear, descriptive title
   - Steps to reproduce (what you said, what the glasses did)
   - Expected vs actual behavior
   - iPhone model, iOS version, glasses firmware, Meta AI app version
   - Relevant logs: Console.app on a Mac, filtered by the app (tags such as `[GeminiLive]`,
     `[GlassesManager]`, `[VoiceAgent]`, `[VoiceCommand]`). A log screen with "Export log" is planned
     (PLAN.md T6.5).
   - Never paste an API key, a `CLIENT_TOKEN` or a Team ID into an issue.

### Suggesting Features

Open an issue with the **💡 Feature request** template: the problem, your proposed solution, and the
alternatives you considered. Check PLAN.md first: it may already be planned or decided against (§1, §6).

### Pull Requests

1. Branch from the right base:
   - During v2 (now): create your branch from `feature/voice-v2` and open the PR into `feature/voice-v2`.
     That branch reaches `main` through one integration PR (PLAN.md §0 rule 2).
   - Otherwise: branch from `main` and open the PR into `main`.
   ```bash
   git checkout -b feature/your-feature-name origin/feature/voice-v2
   ```
2. Make your changes following the code style below. Keep the audio invariants (PLAN.md §0 rule 7).
3. Add or update tests (see [Testing](#testing)).
4. Register any added or removed Swift file with `scripts/pbxproj_files.py` (see [Project file](#project-file)).
5. Commit with clear messages (see [Commit Messages](#commit-messages)).
6. Push and open the pull request. Fill in the template. Wait for CI and E2E to pass.

Never commit directly to `main`, never force-push a shared branch, and never commit secrets.

## Code Style

### Swift Guidelines

Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

```swift
// GOOD: Clear, descriptive names
func startVoiceSession() async throws
func capturePhoto() -> Data?

// BAD: Abbreviated, unclear names
func startVS() async throws
func capPh() -> Data?
```

### Architecture Patterns

See [PLAN.md](PLAN.md) §3.4 for the code map.

- **MVVM**: Views render and forward interactions; ViewModels (`@MainActor ObservableObject`) orchestrate.
- **@MainActor**: Use for all UI-related code and managers.
- **Singleton pattern**: For shared managers and services (`SettingsManager`, `GlassesManager`,
  `GeminiLiveService.shared`, `TTSService.shared`).
- **Pure logic in pure types**: parsing, spoken math, reading state and voice commands live in enums and
  structs that import only Foundation. Most of them are in `OpenVision/Services/Speech/`, which must stay
  Foundation-only because it is also compiled on Linux by `scripts/swift-local/run.sh`.
- **Settings**: store every enum-like option as a `String` with a computed enum accessor (unknown value →
  default), so one bad value can never reset all settings (PLAN.md §4.6).
- **Async/await**: Prefer over completion handlers.
- **No new dependencies or backends** without an issue and a PLAN.md decision.

```swift
// GOOD: @MainActor isolation
@MainActor
final class MyService: ObservableObject {
    @Published var state: ServiceState = .idle

    func performAction() async throws {
        // Implementation
    }
}

// GOOD: Protocol for testability
protocol CameraServiceProtocol {
    func capturePhoto() async throws -> Data
}
```

### File Organization

```swift
// MARK: - Properties

@Published var isActive = false
private var task: URLSessionDataTask?

// MARK: - Initialization

init() {
    // Setup
}

// MARK: - Public Methods

func start() async throws {
    // Implementation
}

// MARK: - Private Methods

private func setupConnection() {
    // Implementation
}
```

### Documentation

Add documentation to public APIs, and say why when the code is not obvious:

```swift
/// Sends the user's question (and photo, if any) to Gemini and streams the reply.
///
/// - Throws: `AIBackendError.notConfigured` if no API key is set
func sendRESTMessage(_ text: String, imageData: Data?) async throws {
    // Implementation
}
```

### Error Handling

Use typed errors with clear cases and user-facing descriptions (Vietnamese in the UI):

```swift
enum CaptureError: LocalizedError {
    case notRegistered
    case timeout(seconds: Int)

    var errorDescription: String? {
        switch self {
        case .notRegistered:
            return "App chưa được đăng ký với kính"
        case .timeout(let seconds):
            return "Kính không gửi ảnh sau \(seconds) giây"
        }
    }
}
```

## Testing

All tests live in `OpenVisionTests/` (one XCTest target). PLAN.md §12 has the full guide and the list of
suites.

| Layer | Command | Needs |
|---|---|---|
| Static guard | `python3 scripts/blueprint/verify_blueprint.py` or `make blueprint-check` | Python 3, any OS |
| Pure Swift | `scripts/swift-local/run.sh [filter]` | a Swift toolchain (Linux or macOS), no Xcode |
| Simulator | `make e2e` (every suite), `make e2e-blueprint`, `make e2e-live` (real Gemini, uses quota) | macOS + Xcode, iOS 18+ simulator |
| Hardware | PLAN.md §7 (H1–H22) | iPhone + Ray-Ban Meta glasses |

The guard must always report `0 failed`. When a design change makes a check wrong, fix the check in the
same commit and never delete one without a replacement.

### Writing Tests

- Put pure logic in Foundation-only types and test it directly. A pure suite runs on Linux if its file
  name starts with one of the prefixes in `scripts/swift-local/run.sh` (`VietMath`, `AnswerFormat`,
  `ReplyAssembler`, `PromptV2`, `ReadingEngine`, `ReadingCommand`, `ReadingModel`, `MathPretty`).
- Assert exact output, not just "not empty". Spoken-math tests compare whole spoken strings.
- Network tests use `GeminiStub` (a `URLProtocol` in `BlueprintGeminiE2ETests.swift`) to script Gemini
  replies and inspect the request the app sent.
- Register every new test file with `scripts/pbxproj_files.py add OpenVisionTests/<Name>Tests.swift`, or CI
  will not run it.

```swift
final class ReplyAssemblerSpeechTests: XCTestCase {
    func testShortAnswerIsReadAsAFraction() {
        let parsed = AnswerFormat.parse("TYPE: MCQ\nQ12: 3/4")
        let plan = ReplyAssembler(languageCode: "vi").plan(turnID: UUID(), parsed: parsed)

        let pieces = VietMathSpeech.render(plan.segments[0].speechText, vietnamese: true, style: .default)

        XCTAssertEqual(pieces, [.words("Câu 12:", isMath: false), .words("ba phần tư", isMath: true)])
    }
}
```

## Project file

CI builds the committed `OpenVision.xcodeproj`; it never runs `xcodegen`. Add, remove or move Swift files
only with the script, which keeps `project.pbxproj` diffs small and checked:

```bash
python3 scripts/pbxproj_files.py --dry-run add OpenVision/Services/Speech/NewThing.swift   # preview
python3 scripts/pbxproj_files.py add OpenVision/Services/Speech/NewThing.swift
python3 scripts/pbxproj_files.py remove OpenVision/Views/Components/OldThing.swift
python3 scripts/pbxproj_files.py remove-folder-ref OpenVision/Resources/SomeFolder
python3 scripts/pbxproj_files.py --self-test
```

Files under `OpenVision/` join the app target and files under `OpenVisionTests/` join the test target.
The guard fails if a Swift file is missing from the project or if the project lists a file that does not
exist. Do not run `xcodegen generate` for normal changes: it rewrites the whole project file.

## Project Structure

```
OpenVision/
├── App/                 # App entry point, Meta DAT configuration, URL callback
├── Config/              # Config.swift (gitignored, from Config.swift.example), constants
├── Managers/            # Glasses (Meta DAT), settings, conversations
├── Models/              # AppSettings, Conversation / Message
├── Resources/           # Assets, sounds, SolutionRenderer (KaTeX; removed in PLAN.md T4.4)
├── Services/
│   ├── AIBackend/       # Connection state and error types
│   ├── Audio/           # AVAudioSession, glasses HFP microphone
│   ├── GeminiLive/      # Gemini REST streaming client, prompt, history, retries
│   ├── Recording/       # Session recording
│   ├── Speech/          # Foundation-only: spoken math, answer format v2.1, reading model, prompt v2.1
│   ├── Telemetry/       # Turn metrics
│   ├── TTS/             # AVSpeechSynthesizer queue
│   └── Voice/           # Wake word and speech recognition
├── Utilities/Helpers/   # Haptics, Objective-C exception catcher
└── Views/               # SwiftUI: VoiceAgent, History, Settings, Components
OpenVisionTests/         # XCTest suites: unit, E2E with a scripted Gemini endpoint, live smoke test
scripts/                 # Guard, simulator runner, pbxproj_files.py, swift-local runner
```

## Commit Messages

```
Type: Short description (max 72 chars)

Task: T4.3

Optional longer description explaining the why and how.

Closes #123
```

Types:
- `Add`: New feature
- `Fix`: Bug fix
- `Refactor`: Code restructuring
- `Docs`: Documentation only
- `Test`: Adding/updating tests
- `Chore`: Maintenance tasks

When the work is a PLAN.md task, put `Task: Tx.y` on the line after the subject, and make one commit per
task. Fixes from a review add the finding ID, for example `Task: T3.1 (review X1)`.

## Pull Request Process

1. **Title**: Clear, descriptive title
2. **Description**: Explain what and why; list the PLAN.md tasks
3. **Testing**: Say which layers you ran (guard, pure Swift, CI, E2E) and which hardware steps (H…) still
   need a person with the glasses
4. **Screenshots**: Include for UI changes
5. **Breaking changes**: Call out any breaking changes

### PR Checklist

- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex logic
- [ ] Documentation updated if needed (PLAN.md status, README, CHANGELOG)
- [ ] Tests added/updated, exact-output assertions
- [ ] New or removed Swift files registered with `scripts/pbxproj_files.py`
- [ ] No compiler warnings introduced
- [ ] CI and E2E are green

### Continuous integration

Every pull request runs two workflows on GitHub Actions:

- **CI** (`.github/workflows/ci.yml`, about 3 minutes): builds the app and its test target for a generic
  iOS device with code signing off.
- **E2E (Blueprint)** (`.github/workflows/e2e.yml`, about 11 minutes): the static guard on Linux, then
  `scripts/e2e/run-simulator-tests.sh` on an iOS simulator:
  1. It builds and installs the app and grants Photos access.
  2. It launches the app twice, normally and without the glasses SDK, and checks that it survives.
  3. It runs every test suite.

  A skipped photo-library test fails the job on CI. The manual run (`workflow_dispatch`) has two options:
  `live_gemini` runs the real-API smoke test, and `blueprint_only` runs only the Blueprint suites.

Both workflows copy `Config.xcconfig.example` and `OpenVision/Config/Config.swift.example` into place, so
no secrets are needed to compile. If a run fails, open the job's log: the E2E job prints the app's launch
console and crash reports, and uploads the `.xcresult` bundle as an artifact. From a sandbox without the
GitHub web UI, read runs and logs with `gh api` (PLAN.md §9).

## Release Process

Releases are cut by a maintainer. Version numbers follow [Semantic Versioning](https://semver.org/):
a new feature bumps the minor version, fixes alone bump the patch version.

1. Open a release branch from `main` (for example `release/3.0.0`).
2. Update `CHANGELOG.md`: move everything merged since the last release under a new
   `## [x.y.z] - YYYY-MM-DD` heading, grouped as Added / Changed / Removed / Fixed, with the PR number
   on each line.
3. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` **and** in the matching build
   settings of `OpenVision.xcodeproj/project.pbxproj` (CI builds the committed project), and commit as
   `Chore: bump version to x.y.z (build N)`.
4. Open a pull request. The release commits go through CI like any other change.
5. After the merge, tag the merge commit and publish the release with narrative notes and a
   compare link:

   ```bash
   git tag -a vx.y.z -m "OpenVision x.y.z"
   git push origin vx.y.z
   gh release create vx.y.z --title "OpenVision x.y.z" --notes-file notes.md
   ```

The app is distributed as source and as an unsigned IPA (the **Build Unsigned IPA** workflow, installed
with Sideloadly or AltStore). There is no App Store or TestFlight step in this repository.

## Questions?

- Open an [issue](https://github.com/darwnlinz1/Visor-iOS-Solver/issues)
- Check existing issues and PRs
- Read [PLAN.md](PLAN.md) for technical context

---

Thank you for contributing to OpenVision!
