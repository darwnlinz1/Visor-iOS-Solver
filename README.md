# OpenVision — Ray-Ban Meta × Gemini homework solver

Bấm nút chụp trên kính, nói **"Ok Vision"** và hỏi bất cứ điều gì bằng tiếng Việt hoặc tiếng Anh.
Kính đọc câu trả lời bằng đúng ngôn ngữ bạn hỏi; điện thoại hiện lời giải từng bước với công thức.

Press the capture button on the glasses, say **"Ok Vision"** and ask anything in Vietnamese or
English. The glasses speak the answer in the language you asked in; the phone shows the full
step-by-step solution with rendered formulas.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![iOS 18+](https://img.shields.io/badge/iOS-18+-blue.svg)](https://developer.apple.com/ios/)

> Fork of [rayl15/OpenVision](https://github.com/rayl15/OpenVision), narrowed to one workflow.
> Design notes, known issues and the work plan: [PLAN.md](PLAN.md). Coding agents: start with
> [AGENTS.md](AGENTS.md).

## Status (November 2026)

Version 2 is in progress on `feature/voice-v2` ([PLAN.md](PLAN.md) §3 and §11). In v2 every answer is read
aloud and the phone screen no longer carries the solution. Multiple-choice answers are read as "Câu 1: A.
Câu 2: C.". Essay solutions are read line by line, with pauses and their own speed. Formulas are read the way
Vietnamese classrooms say them.

- **Done (wave 1):** the spoken-math module, the v2.1 answer-format parser, the reading model and the new
  prompt text, with 143 pure-Swift tests. CI now runs every test suite (218 tests). The app no longer
  crashes at launch when the Meta SDK fails to configure. These new modules are built into the app but
  **not called yet**.
- **Next (wave 2):** wire them into speech, the Gemini client and History, then remove the phone display.

Until wave 2 lands, the app behaves as described below.

## What it does

- **Photo straight from the glasses.** The capture button is routed to the app (Meta DAT 1.0.1),
  with no waiting for the Meta AI app to import the photo into Camera Roll. Short press: photo for
  your next question. Hold: photo and solve now. Double press: hear the last answer again. (All
  configurable.) A full-resolution photo over Bluetooth takes about 9 s at 720p and 49 s at
  12 MP, so the app often uses a 1440×1080 still from the camera stream instead; PLAN.md
  T7.3–T7.5 rework this path.
- **Ask freely.** No fixed commands: "giải câu 3", "what does this say?", "hướng dẫn mình làm
  câu này", or a question that has nothing to do with the photo.
- **Answer in your language, pronounced right.** Vietnamese question → Vietnamese answer in a
  Vietnamese voice; English → English. Math is read as words ("x bình phương bằng 4").
- **Two channels.** A short spoken answer (answer first) on the glasses; the full derivation in
  Markdown + LaTeX on the phone, rendered offline with KaTeX.
- **Asks for a photo when it needs one.** If you ask about something and there is no photo, the
  app takes one and asks Gemini again.
- **Doesn't hang.** Streaming replies, retries by failure type, a second model when quota runs
  out, several API keys, and a hard 120 s limit — then it tells you, out loud.
- **Modes from your words:** solve (default), tutor ("gợi ý", "teach me"), whole page
  ("tất cả các câu"), read / translate.

## Requirements

- iPhone with iOS 18+ (built for iPhone 15 Pro / Pro Max), Ray-Ban Meta glasses
- The Meta AI app with **Developer Mode** on (needed for the capture button and full-resolution
  photos, which are experimental in the Meta SDK — without them the app falls back to Camera Roll)
- A [Gemini API key](https://aistudio.google.com/app/apikey) — pasted in **Settings → Gemini**.
  Several keys (from different Google Cloud projects) can be entered, separated by commas.
  **Never put a key in the source code: this repository is public.**

## Install

Unsigned IPA: run the **Build Unsigned IPA** workflow (Actions tab) and sideload the artifact
(e.g. with AltStore or Sideloadly). To build yourself:

```bash
git clone https://github.com/darwnlinz1/Visor-iOS-Solver.git
cd Visor-iOS-Solver
cp Config.xcconfig.example Config.xcconfig
cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift
open OpenVision.xcodeproj
```

`Config.xcconfig` holds your Apple Team ID, bundle id and (optionally) Meta App ID / Client Token
from the [Meta developer console](https://developer.meta.com). In Developer Mode the App ID may be
`0`. Both config files are gitignored. More: [PLAN.md](PLAN.md) §8.

First run:
1. Settings → **Kính Ray-Ban Meta** → **Đăng ký app** (opens Meta AI to grant access).
2. Settings → **Gemini** → paste your key.
3. Settings → **Giọng nói** → choose the listening language and download an Enhanced/Premium
   Vietnamese voice in iOS Settings for the most natural pronunciation.
4. Kính → **Chụp thử** to check the button link and photo transfer.

## Tests

```bash
python3 scripts/blueprint/verify_blueprint.py   # static workflow + security guard (any OS, seconds)
scripts/swift-local/run.sh                      # pure-Swift suites (spoken math, answer format) with SwiftPM, no Xcode
make e2e                                        # every XCTest suite on an iOS 18+ simulator (macOS + Xcode)
make e2e-blueprint                              # only the Blueprint workflow suites
```

Every pull request runs two GitHub Actions workflows. **CI** builds the app and the tests for a device.
**E2E** runs the static guard and then every test suite on a simulator: Gemini is replaced by a scripted
endpoint, and the tests use the simulator's real photo library. The opt-in `live_gemini` run calls the real
API. [PLAN.md](PLAN.md) §12 describes the test layers, and §7 the hardware test protocol (H1–H22).

## License & acknowledgments

MIT — see [LICENSE](LICENSE).

- [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios) — glasses
- [Google Gemini API](https://ai.google.dev) — the solver
- [KaTeX](https://katex.org) and [marked](https://marked.js.org) (MIT) — offline solution rendering
- [rayl15/OpenVision](https://github.com/rayl15/OpenVision) — the original app
- [Visor](https://github.com/macedonga/visor) — ideas for the glasses workflow (no code copied)
