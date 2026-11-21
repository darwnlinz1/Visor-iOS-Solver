# PLAN.md: kế hoạch sửa OpenVision iOS (dành cho coding agent)

> Cập nhật: 21/11/2026. Đây là **tài liệu duy nhất** về thiết kế, hiện trạng và việc cần làm.
> Các tài liệu cũ (MASTER_HANDOVER_BLUEPRINT, ULTIMATE_VISOR_MASTER_MANIFESTO, PROJECT_AUDIT,
> ARCHITECTURE_DECISION, ADR-001, SETUP, E2E_TEST_PLAN, …) đã bị xoá vì chứa nhiều khẳng định
> sai so với code (ảnh 12 MP, OpenRouter, circuit breaker, phát hiện ảnh mờ, thời gian phản hồi
> 2,5 s trên kính…). Nếu comment trong code mâu thuẫn với file này, **tin file này**. Nếu file này
> mô tả hiện trạng khác với code bạn đọc được, **tin code** và ghi chú lại trong PR.

---

## 0. Quy tắc làm việc cho agent (đọc trước khi làm bất cứ gì)

1. **Làm theo thứ tự phase** (Phase 0 → 5). Không nhảy phase. Mỗi task (`T…`) là **một commit**.
2. **Branch:** tạo `feature/fix-ios-pipeline` từ branch đang chứa file này, mở **một** PR vào
   `main`. Không bao giờ commit hoặc push thẳng lên `main`. Không `push --force`.
3. **Commit message** theo `CONTRIBUTING.md`: `Fix: …`, `Refactor: …`, `Docs: …`, `Chore: …`,
   `Test: …` (tối đa 72 ký tự ở dòng đầu, dòng sau ghi ID task, ví dụ `Task: T1.2`).
4. **Môi trường:** sandbox là Linux, **không có Xcode**. Bạn không build được app ở local.
   - Chạy được ở local: `python3 scripts/blueprint/verify_blueprint.py` (phải luôn 0 failed).
   - Build và test iOS chạy trên GitHub Actions khi có PR (`CI`, `E2E (Blueprint)`). Xem mục 9
     để đọc kết quả. Một task chỉ coi là xong khi CI của commit đó xanh (hoặc lỗi còn lại đã được
     ghi rõ là có từ trước và không do bạn gây ra).
5. **Không thêm file Swift mới** nếu không thật cần. `OpenVision.xcodeproj/project.pbxproj` được
   commit sẵn và CI không chạy `xcodegen`. Nếu bắt buộc phải thêm file: thêm đủ 4 mục trong
   pbxproj (PBXFileReference, PBXBuildFile, children của group, Sources build phase) bằng cách
   sao chép mẫu của một file cùng thư mục; guard `project` sẽ kiểm tra.
6. **Không làm ngoài plan:** không refactor lan man, không thêm tính năng, không thêm dependency,
   không thêm OpenRouter / GeminiModelManager / phát hiện ảnh mờ / backend mới. Không đưa lại
   danh sách từ khoá để đoán ý người dùng.
7. **Giữ nguyên các bất biến âm thanh** mà guard đang kiểm tra (lesson 1–4): một tap mic duy nhất
   trong `VoiceCommandService`, `configureForGlasses` dùng `.playAndRecord` + `mode: .default` +
   `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]`, không gọi
   `setPreferredInput` trong route change, chờ 350 ms sau TTS, đặt `.speaking` + `isBargeInPaused`
   **trước** khi xếp câu nói.
8. **Bí mật:** không bao giờ commit hay in ra log API key, `CLIENT_TOKEN`, Team ID thật.
9. **Phần cứng:** nhiều task chỉ kiểm chứng được trên kính thật. Với các task đó: viết code, thêm
   log rõ ràng, ghi trong PR "Cần chủ dự án chạy H…" (mục 7). **Không được tuyên bố đã chạy trên
   kính.**
10. Khi xong (hoặc bị chặn), báo cáo theo mẫu ở mục 10.

---

## 1. Mục tiêu và phạm vi

App: người đeo **Ray-Ban Meta** (Gen 2) chụp ảnh bằng kính, nói "Ok Vision" + câu hỏi tự do
(tiếng Việt hoặc tiếng Anh). **Gemini** trả lời: phần `SPOKEN:` được đọc qua loa kính, phần
`DISPLAY:` (Markdown + LaTeX) hiển thị trên iPhone (KaTeX offline). Máy đích: iPhone 15 Pro,
iOS 18+. Cài bằng Sideloadly từ IPA unsigned do workflow `Build Unsigned IPA` tạo.

**Mục tiêu của đợt sửa này** (theo thứ tự ưu tiên):
1. CI và test thật sự chạy, và xanh.
2. Gỡ các hồi quy do các commit sau `418a993` gây ra.
3. Đường lấy ảnh nhanh, trung thực (biết ảnh từ đâu, độ phân giải bao nhiêu), không gửi nhầm ảnh
   riêng tư từ Camera Roll.
4. Nhận dạng giọng nói và âm thanh ổn định hơn.
5. Tài liệu khớp với code.

**Ngoài phạm vi** (chỉ làm khi chủ dự án duyệt, xem mục 6): Voice Invocation "Hey Meta",
MWDATSpeech, đổi model, port giao thức Visor.

---

## 2. Sự thật kỹ thuật đã xác minh

### 2.1 Vì sao app này khác Visor Android về bản chất
- [Visor](https://github.com/macedonga/visor) **thay thế** app Meta AI: nó trở thành "owner app"
  của kính, nói giao thức riêng của Meta qua **BLE L2CAP (PSM 0x80)**, RFCOMM và Wi-Fi Direct.
  "Hey Meta", mic, nhận dạng giọng nói, giọng đọc và nút chụp đều do kính xử lý; Visor chỉ thay
  "server" trả lời. Ảnh 12 MP qua Wi-Fi Direct. Chạy được khi khoá máy.
- App này là **app phụ** qua Meta Wearables DAT SDK. Meta AI vẫn giữ kính. App phải tự làm: wake
  word (`SFSpeechRecognizer` trên iPhone), mic qua Bluetooth HFP (chất lượng cuộc gọi), giọng đọc
  `AVSpeechSynthesizer` phát qua HFP, và lấy ảnh qua DAT. Đây là giới hạn kiến trúc, không phải bug.

### 2.2 Giới hạn của Meta DAT SDK (iOS) cần biết khi sửa code
| Sự thật | Nguồn |
|---|---|
| `Camera.photo` (ảnh rời) qua Bluetooth Classic: `.medium` 720×1280 ≈ **8,7 s**, `.full` 3024×4032 ≈ **49 s**. Qua Wi-Fi còn chậm hơn (25 s / 165 s). `stream.capturePhoto` (1440×1080, ~200 KB) chỉ ≈ **1 s**. App này dùng cấu hình Bluetooth Classic (`external-accessory` + `com.meta.ar.wearable`). | [DAT #363](https://github.com/meta/meta-wearables-dat-ios/issues/363) |
| Ray-Ban Meta Gen 1: `Camera.photo` báo `CaptureRequestError 6` ở cả 720p và 12 MP; stream still vẫn chạy. | [DAT #383](https://github.com/meta/meta-wearables-dat-ios/issues/383) |
| Bấm nút chụp khi luồng camera đang chạy: kính **tạm dừng session** thay vì gửi sự kiện cho app. | [DAT #312](https://github.com/meta/meta-wearables-dat-ios/issues/312) |
| Khi luồng camera chạy, kính tắt các âm thanh khác; A2DP có thể **không bật lại**. | [DAT #256](https://github.com/meta/meta-wearables-dat-ios/issues/256), [#358](https://github.com/meta/meta-wearables-dat-ios/issues/358) |
| `Inputs` (nút chụp), `Camera.photo`, `Speech`, `VoiceInvocation` là **experimental**: cần Developer Mode, app dùng chúng chưa được phát hành. | [CHANGELOG DAT](https://github.com/meta/meta-wearables-dat-ios/blob/main/CHANGELOG.md) |
| Một số bản Meta AI không bật được Developer Mode. | [DAT #325](https://github.com/meta/meta-wearables-dat-ios/issues/325) |
| DAT **1.1.0** (20/11/2026): thêm `DeviceSession.pause()/resume()`, `DeviceSessionError.notRegistered` (createSession ném lỗi khi chưa đăng ký), `RegistrationError.unauthorized`, `stream.capturePhoto` timeout 10 s (trước là 30 s). Project đang ghim **1.0.1**. | CHANGELOG DAT |
| DAT tạm dừng camera khi app ra nền; sample chính thức của Meta đóng session khi app ra nền. | CHANGELOG DAT 0.9.0 |

### 2.3 Gemini
- Model đang dùng: `gemini-3.5-flash-lite` → `gemini-3.1-flash-lite` (cả hai tồn tại, xem
  [danh sách model](https://ai.google.dev/gemini-api/docs/models)). Flash-Lite là bậc yếu nhất,
  Google định vị cho tác vụ nhẹ và đọc tài liệu.
- Gemini 3 tính token ảnh theo mức cố định (HIGH ≈ 1120, ULTRA_HIGH ≈ 2240 token), nên upload ảnh
  lớn hơn ~3072 px chỉ tốn thời gian truyền.

---

## 3. Bản đồ mã nguồn

| File | Trách nhiệm |
|---|---|
| `OpenVision/App/OpenVisionApp.swift` | Khởi động, cấu hình DAT SDK, nhận URL callback từ Meta AI |
| `OpenVision/Managers/GlassesManager.swift` | Đăng ký, `DeviceSession`, camera stream, ảnh (`captureFullResolutionPhoto`), nút chụp (`MWDATInputs`) |
| `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` | Điều phối toàn bộ: phiên, `sendCommand`, lấy ảnh (`acquireGlassesPhoto`), nút chụp, TTS streaming, lịch sử. Chứa luôn `CapturedPhotoContext`, `SolverIntent`, `RecentPhotoScanner`, `PhotoPayload`, `TextChunking` |
| `OpenVision/Services/GeminiLive/GeminiLiveService.swift` | REST streaming SSE, retry theo loại lỗi, xoay key, model chain, lịch sử 6 entry, `[[CAPTURE]]` / `[[END]]`, system prompt, `parseDualChannel` |
| `OpenVision/Services/Voice/VoiceCommandService.swift` | `AVAudioEngine` duy nhất + tap mic, `SFSpeechRecognizer`, wake word, conversation mode, barge-in |
| `OpenVision/Services/Voice/SpeechActivityDetector.swift` | VAD Silero (FluidAudio) để biết lúc người dùng nói xong |
| `OpenVision/Services/Audio/AudioSessionManager.swift` | `AVAudioSession`, chọn mic HFP của kính |
| `OpenVision/Services/TTS/TTSService.swift` | Giọng Apple theo ngôn ngữ, `cleanSpokenAudio`, `SpokenMath` |
| `OpenVision/Views/Settings/GlassesSettingsView.swift` | Cài đặt kính, công tắc ảnh full-res, nút "Chụp thử" |
| `OpenVision/Models/AppSettings.swift` | Model cài đặt (mặc định) |
| `OpenVisionTests/*` | `BlueprintSolverTests` (logic thuần), `BlueprintGeminiE2ETests` (Gemini giả lập bằng URLProtocol), `BlueprintPhotoLibraryE2ETests`, `GeminiLiveSmokeTests` (Gemini thật, tuỳ chọn) |
| `scripts/blueprint/verify_blueprint.py` | Guard tĩnh, chạy được trên Linux |
| `scripts/e2e/run-simulator-tests.sh` | Chạy test trên simulator (CI job `E2E (Blueprint)`) |
| `.github/workflows/{ci,e2e,build-ipa}.yml` | Build, test, đóng gói IPA |

Commit `418a993` (commit đầu tiên) là mốc "sạch". Các commit `d881354`, `284bdfd`, `f032c60`,
`050dea5`, `c4d7987` thêm các thay đổi liên quan tới ảnh, một phần là hồi quy (mục 4). Các tính
năng UI của chúng (xem trước ảnh trong bong bóng chat, ô nhập câu hỏi bằng bàn phím
`sendTypedCommand`, `detachPhoto`) **giữ lại**.

---

## 4. Lỗi đã xác minh (hiện trạng trên `main`)

| ID | Lỗi | Vị trí | Bằng chứng |
|---|---|---|---|
| B1 | Job `E2E (Blueprint)` fail ở **mọi** commit: script không có quyền chạy. Test simulator **chưa từng chạy**. | `scripts/e2e/run-simulator-tests.sh` (mode 100644) | Log CI: `run-simulator-tests.sh: Permission denied` |
| B2 | TTL ảnh 300 s / 10 lần dùng, test yêu cầu 120 s / 5 lần → test sẽ fail khi B1 được sửa. | `CapturedPhotoContext.ttl`, `.maxUses` | `testPhotoContextLivesFor120SecondsAndFiveQuestions`; giá trị gốc ở `418a993` là 120/5 |
| B3 | Câu hỏi nối tiếp gửi lại **cả ảnh gốc lẫn bản 1536 px** trong lịch sử. `imageFingerprintInHistory` được ghi nhưng không bao giờ đọc. | `GeminiLiveService.performTurn` | `testFollowUpOnTheSamePhotoKeepsContextWithoutReuploading` sẽ fail; logic gốc ở `418a993` (khối "Photo already in conversation history — not re-uploading") |
| B4 | Danh sách từ khoá (`requiresAttachedPhoto`) chặn câu hỏi và đi chụp ảnh. Nó trùng và mâu thuẫn với cơ chế `[[CAPTURE]]`. Chỉ cần có "chụp", "photo", "bài này" là app chụp ảnh; trường hợp xấu nhất chờ 60–90 s. Guard không bắt được vì chỉ tìm tên `visualKeywords`. | `SolverIntent.requiresAttachedPhoto`, `sendCommand` | Thêm ở `f032c60`, `050dea5` |
| B5 | Câu hỏi **không liên quan tới ảnh** vẫn chờ 1 s quét Camera Roll và gắn ảnh tìm được. | `sendCommand` (nhánh `else if !hasExistingFreshPhoto`) | |
| B6 | `RecentPhotoScanner` nhận ảnh 4032×3024 (trùng ảnh 12 MP của iPhone) và **mọi ảnh ≥ 1200 px** trong 120 s → ảnh riêng tư bị gửi lên Gemini. `photoLibraryDidChange` cũng tự gắn ảnh đó làm ngữ cảnh. | `RecentPhotoScanner.newestImageAsset`, `photoLibraryDidChange`, `onPhotoArrived` | |
| B7 | `currentTranscriptPhotoData` (biến cho UI) được dùng làm nguồn ảnh gửi đi, **bỏ qua TTL**: ảnh cũ bị gắn mãi. | `sendCommand` | |
| B8 | `captureFullResolutionPhoto` gần như **không bao giờ** dùng `Camera.photo`: thử stream still (chờ 4 s) → `lastFrame` (khung video) → `Camera.photo` sau cùng với timeout **3 s** (thực tế cần 8–49 s). Tham số `timeout` bị bỏ qua. `fullPhotoFailures = 0` bị đặt lại mỗi lần gọi nên khoá sau 2 lần lỗi vô tác dụng. Không biết ảnh từ nguồn nào, độ phân giải bao nhiêu. | `GlassesManager.captureFullResolutionPhoto` | Mục 2.2 |
| B9 | Các lần chụp đồng thời đợi nhau bằng vòng lặp poll (15 s trong `sendCommand`, 45 s trong `acquireGlassesPhoto`). `captureFullResolutionPhoto` trả `nil` nếu đang có lần chụp khác. Sau đó `acquireGlassesPhoto` lại bật stream lần nữa (`takeGlassesPhoto` → `freshLiveFrame`), rồi chờ Camera Roll 30 s. | `VoiceAgentViewModel.acquireGlassesPhoto`, `sendCommand` | |
| B10 | Ảnh upload 4032 px q0.92 thay vì 3072 px q0.85 (giá trị gốc), chỉ thêm độ trễ. | `PhotoPayload.uploadMaxDimension`, `.uploadQuality` | Đổi ở `284bdfd` |
| B11 | Nhận dạng giọng nói chạy trên server Apple (không đặt `requiresOnDeviceRecognition`), `taskHint = .search` cho cả câu hỏi dài. | `VoiceCommandService.configureRecognitionRequest` | |
| B12 | Biến thể wake word dễ khớp nhầm câu tiếng Anh bình thường: `"a vision"`, `"have vision"`, `"heavy vision"`, `"obey vision"`. `detectWakeWord` khớp substring ở bất kỳ đâu. | `VoiceCommandService.wakeWordVariations` | |
| B13 | Info.plist: `UIRequiredDeviceCapabilities = armv7` (sai cho app 64-bit), `NSAllowsArbitraryLoads = true` (không cần). | `OpenVision/Resources/Info.plist` | |
| B14 | `build-ipa.yml` in nội dung `Config.xcconfig` ra log (`cat Config.xcconfig`). Hiện là placeholder, nhưng sẽ lộ token nếu sau này dùng secret. | `.github/workflows/build-ipa.yml` | |
| B15 | DAT SDK ghim 1.0.1, đã có 1.1.0. | `project.yml`, `project.pbxproj` | |
| B16 | README, CONTRIBUTING mô tả sai (ảnh full-res từ kính, OpenClaw, rayl15, thư mục `Tests/`, `CLAUDE.md`). | `README.md`, `CONTRIBUTING.md` | |

---

## 5. Kế hoạch theo phase

Mỗi task ghi: **Việc cần làm**, **Không làm**, **Xong khi**. Sau mỗi task: chạy guard ở local,
commit, push, chờ CI (mục 9).

### Phase 0: nền móng (không đổi hành vi app)

**T0.1: Cho script E2E chạy được (B1)**
- Việc: `git update-index --chmod=+x scripts/e2e/run-simulator-tests.sh` và `chmod +x` file đó.
- Xong khi: `git ls-files -s scripts/e2e/run-simulator-tests.sh` bắt đầu bằng `100755`; job
  `Blueprint E2E (iOS simulator)` không còn `Permission denied`. **Ghi lại danh sách test fail**
  (dự kiến có ít nhất các test ở B2, B3). Chưa sửa ở task này.
- Nếu job fail vì lý do hạ tầng (không tìm thấy simulator iOS 18+, xcbeautify…): sửa
  `scripts/e2e/run-simulator-tests.sh` hoặc `e2e.yml` tối thiểu để chạy được, ghi lý do trong commit.

**T0.2: Sửa tham chiếu tới tài liệu đã xoá**
- Việc: các file sau còn nhắc `MASTER_HANDOVER_BLUEPRINT.md`, `docs/testing/E2E_TEST_PLAN.md`,
  `docs/architecture/ADR-001-solver-pipeline.md`, `docs/architecture.md`, `SETUP.md`, `CLAUDE.md`:
  `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `.github/pull_request_template.md`, `Makefile`,
  `.github/workflows/e2e.yml`, `scripts/blueprint/verify_blueprint.py`,
  `scripts/blueprint/verify_ipa_symbols.sh`, `scripts/e2e/run-simulator-tests.sh`,
  `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift`,
  `OpenVision/Services/GeminiLive/GeminiLiveService.swift`, `OpenVisionTests/BlueprintSolverTests.swift`,
  `OpenVisionTests/BlueprintGeminiE2ETests.swift`. Thay bằng `PLAN.md` (ví dụ "see PLAN.md §7")
  hoặc bỏ câu đó. Chỉ sửa comment/chuỗi, **không sửa logic**.
- Xong khi: `grep -rnE "MASTER_HANDOVER|E2E_TEST_PLAN|ADR-001|docs/architecture|SETUP\.md|CLAUDE\.md" --exclude-dir=.git .`
  chỉ còn kết quả trong `PLAN.md`. (Trong `CHANGELOG.md`, các mục lịch sử cũ chỉ cần bỏ link,
  giữ nội dung.)

**T0.3: Info.plist (B13)**
- Việc: `armv7` → `arm64`. Xoá `NSAllowsArbitraryLoads`, giữ `NSAllowsLocalNetworking = true`
  (DAT có thể cần mạng nội bộ tới kính). Không đổi key nào khác.
- Xong khi: guard xanh, CI build xanh.

**T0.4: Không in config ra log (B14)**
- Việc: trong `build-ipa.yml`, bỏ `cat Config.xcconfig`; chỉ in "Configuration files verified".
- Không làm: chưa thêm secret Team ID / Meta ID vào CI (xem spike S5).

### Phase 1: gỡ hồi quy để CI xanh

**T1.1: TTL ảnh 120 s / 5 lần (B2)**
- Việc: `CapturedPhotoContext.ttl = 120.0`, `maxUses = 5`; sửa doc comment cho đúng.
- Xong khi: `testPhotoContextLivesFor120SecondsAndFiveQuestions` pass.

**T1.2: Không gửi lại ảnh đã có trong lịch sử (B3)**
- Việc: trong `GeminiLiveService.performTurn`, khôi phục khối của `418a993`
  (`git show 418a993:OpenVision/Services/GeminiLive/GeminiLiveService.swift`, quanh dòng 228):
  nếu `historyContainsImage` và `imageFingerprintInHistory == PhotoPayload.fingerprint(prepared)`
  thì `prepared = nil` và log `Photo already in conversation history — not re-uploading`. Xoá
  comment "always attach it…". Giữ nguyên nhánh `.staleSignature` (nó gắn lại `fullUpload`).
- Xong khi: `testFollowUpOnTheSamePhotoKeepsContextWithoutReuploading` và
  `testANewPhotoIsUploadedAgain` pass.

**T1.3: Kích thước upload 3072 px q0.85 (B10)**
- Việc: `PhotoPayload.uploadMaxDimension = 3072`, `uploadQuality = 0.85`; sửa comment.
- Xong khi: test trong `BlueprintSolverTests` / `BlueprintGeminiE2ETests` về kích thước ảnh pass.

**T1.4: Chỉ một cơ chế quyết định có cần ảnh: `[[CAPTURE]]` (B4, B5, B7)**
- Việc trong `VoiceAgentViewModel.sendCommand`:
  - Xoá nhánh `isVisual` (gọi `acquireGlassesPhoto` khi có từ khoá) và nhánh quét nhanh 1 s.
  - Ảnh gửi đi **chỉ** lấy từ `activePhotoContext` khi `isFresh` (tăng `useCount`).
    `currentTranscriptPhotoData` chỉ dùng cho UI: gán bằng ảnh thực sự gửi đi (hoặc `nil`).
  - Giữ: lệnh dừng, chống trùng lệnh 4 s, vòng chờ `glassesManager.isTakingPhoto` (sẽ thay ở T3.1),
    `ConversationManager.addUserMessage`, `sendRESTMessage`, `handleSendFailure`.
- Xoá `SolverIntent.requiresAttachedPhoto` và `scripts/test_e2e_photo_flow.py`.
- Guard: trong `verify_blueprint.py`, check `workflow` "verbatim" phải fail nếu
  `VoiceAgentViewModel.swift` chứa `requiresAttachedPhoto` hoặc `visualPhrases` (bên cạnh
  `visualKeywords` hiện có).
- Không làm: không thêm danh sách từ khoá mới dưới tên khác.
- Xong khi: guard xanh; toàn bộ test Blueprint trên simulator xanh. Hardware: H6, H12.

### Phase 2: nâng DAT SDK lên 1.1.0 (B15)

**T2.1**
- Việc: `project.yml` → `exactVersion: "1.1.0"`; `project.pbxproj` → khối
  `XCRemoteSwiftPackageReference "meta-wearables-dat-ios"` `version = 1.1.0;`. Sửa comment pin trong
  `project.yml` (bỏ đoạn mô tả 1.0.1, thêm 1 dòng về 1.1.0).
- Xử lý API mới (chỉ những gì cần để compile + báo lỗi rõ):
  - `GlassesManager.register()`: bắt `RegistrationError.unauthorized` → `errorMessage =
    "Meta chưa cho phép app này đăng ký. Kiểm tra App ID, Bundle ID và Team ID trong Wearables Developer Center."`
  - `GlassesManager.startSession`: lỗi `DeviceSessionError.notRegistered` → `report("Chưa đăng ký với Meta AI")`.
  - Nếu code `switch` trên các enum lỗi này mà không có `default`, thêm case mới.
- Không làm: chưa dùng `pause()/resume()`.
- Xong khi: CI build + E2E xanh. Nếu không resolve được package qua URL `facebook/…`, đổi sang
  `https://github.com/meta/meta-wearables-dat-ios` ở cả hai file. Hardware: H1, H9.

### Phase 3: đường lấy ảnh

**T3.1: Một lần chụp dùng chung (B9)**
- Việc trong `GlassesManager`:
  - Thêm `private var captureTask: Task<Data?, Never>?`.
  - `captureFullResolutionPhoto(fullResolution:timeout:)`: nếu `captureTask != nil` thì
    `return await captureTask!.value` (dùng chung kết quả) thay vì trả `nil`. Nếu không, tạo task
    chạy phần thân hiện tại, gán `captureTask`, `await`, rồi đặt `captureTask = nil`.
    `isTakingPhoto` vẫn phản ánh "đang có task".
- Việc trong `VoiceAgentViewModel`: bỏ vòng poll `isTakingPhoto` ở đầu `acquireGlassesPhoto` và
  ở bước 1 của `sendCommand` (gọi thẳng `acquireGlassesPhoto` / dùng `activePhotoContext`).
- Xong khi: CI xanh. Không còn vòng `while glassesManager.isTakingPhoto` nào trong ViewModel.

**T3.2: Thứ tự nguồn ảnh theo cài đặt, timeout đúng, ghi nguồn (B8)**
- Việc trong `GlassesManager.captureFullResolutionPhoto`:
  - Thêm `@Published private(set) var lastPhotoSource: String = ""` (giá trị:
    `"camera.photo full"`, `"camera.photo large"`, `"stream still"`, `"video frame"`).
  - Sau khi lấy được ảnh: đọc kích thước bằng `PhotoPayload.imageInfo(data)` và log
    `[GlassesManager] Photo: <source> <w>x<h> <bytes> bytes in <s> s`.
  - `fullResolution == true` (người dùng chọn ảnh nét tối đa): thử **`Camera.photo` trước** theo
    trình tự hiện có (đánh thức bằng stream → `photo.start()` → chờ `.started` → dừng stream → chờ
    `.stopped` → `capturePhoto(resolution: .full, quality: .high)`). Chờ ảnh tới `timeout`
    (mặc định **75 s**). Mỗi sự kiện `transferProgressPublisher` cập nhật một mốc "lần cuối có tiến
    độ"; huỷ sớm nếu **15 s** không có tiến độ. Lỗi thì rơi xuống stream still.
  - `fullResolution == false` (mặc định mới): **stream still trước**, chờ tối đa **10 s**; rồi tới
    video frame. Không thử `Camera.photo`.
  - Bỏ dòng `fullPhotoFailures = 0` ở đầu hàm. Chỉ reset trong `endSession()` và
    `resetPhotoFailures()`. Khi `fullPhotoFailures >= 2`, bỏ qua `Camera.photo` trong session đó.
  - Bỏ timeout cứng 3 s bên trong `withCheckedContinuation`; dùng cơ chế timeout ở trên.
  - Giữ chuỗi `.photo.capturePhoto(resolution:` (guard kiểm tra).
- Xong khi: CI xanh. Hardware: H9 (đo cả hai chế độ), H1.

**T3.3: Mặc định và nhãn Settings trung thực**
- Việc: `AppSettings.fullResolutionPhotos = false`. Trong `GlassesSettingsView.photoSection`:
  tiêu đề "Ảnh nét tối đa (12 MP)"; phụ đề khi bật: "Rất chậm qua Bluetooth, có thể 30–60 giây";
  khi tắt: "Nhanh (~1–2 giây), ảnh từ luồng camera". Kết quả "Chụp thử" hiển thị thêm
  `glassesManager.lastPhotoSource`, ví dụ `1440×1080 · 1.2 s · stream still`.
- Xong khi: CI xanh.

**T3.4: Đơn giản hoá `acquireGlassesPhoto` (B9)**
- Việc: logic mới:
  1. Nếu `isRecording` (stream đang được ghi hình dùng): `capturePhotoFromGlasses()` (stream still
     trên stream đang chạy), nâng thời gian chờ trong đó từ 1,5 s lên 10 s.
  2. Ngược lại: `glassesManager.captureFullResolutionPhoto(fullResolution: settings.fullResolutionPhotos)`
     nếu `glassesManager.isRegistered`.
  3. Nếu vẫn `nil`: `RecentPhotoScanner.shared.fetchMostRecentPhoto()` (một lần, **không** vòng chờ 30 s).
- Xoá `takeGlassesPhoto()`, `freshLiveFrame()`, `RecentPhotoScanner.waitForFullResolutionGlassesPhoto`,
  `waitForRecentGlassesPhoto` nếu không còn ai gọi.
- Xong khi: CI xanh. Thời gian xấu nhất khi không có ảnh (chế độ nhanh) ≲ 30 s (mở session 15 s +
  stream 8 s + still 10 s). Ghi con số ước tính trong PR.

**T3.5: Camera Roll chỉ đọc album của Meta (B6)**
- Việc trong `RecentPhotoScanner.newestImageAsset`:
  - Chỉ tìm trong album có tiêu đề chứa `meta`, `ray-ban` hoặc `stories` (không phân biệt hoa thường).
  - Xoá toàn bộ bước 2 (quét thư viện chung, luật tỉ lệ 4032×3024, luật ≥ 1200 px).
  - Nếu không có album Meta nào: log **một lần** danh sách tiêu đề album người dùng có (để chẩn đoán)
    rồi trả `nil`.
- Hệ quả: `photoLibraryDidChange` / `onPhotoArrived` chỉ còn kích hoạt với ảnh từ album Meta. Giữ
  `recentPhotoWindow = 120` và `requestImageDataAndOrientation` (guard lesson 6).
- Sửa `OpenVisionTests/BlueprintPhotoLibraryE2ETests.swift` cho khớp: helper `addToLibrary` nhận
  thêm tham số `album: String?`; khi có, tạo (hoặc tìm) album đó bằng
  `PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:)` và thêm asset vào.
  Hai test hiện có dùng album `"Meta AI"`. Thêm test mới: ảnh 4032×3024 vừa tạo **không** thuộc
  album nào thì `fetchMostRecentPhoto()` phải trả `nil` (hoặc ảnh khác, không phải ảnh này).
- Xong khi: guard xanh; cả ba test trong `BlueprintPhotoLibraryE2ETests` pass trên simulator.
  Hardware: H12, và H1 khi dùng đường Camera Roll.

### Phase 4: giọng nói và âm thanh

**T4.1: Nhận dạng trên máy khi có thể (B11)**
- Việc trong `configureRecognitionRequest`: nếu `speechRecognizer?.supportsOnDeviceRecognition == true`
  thì `request.requiresOnDeviceRecognition = true`. Log một lần cho mỗi locale:
  `[VoiceCommand] on-device recognition for <locale>: yes/no`.
- Xong khi: CI xanh. Hardware: H1, H10 (ghi lại vi-VN có hỗ trợ on-device không).

**T4.2: `taskHint` theo trạng thái (B11)**
- Việc: `.search` khi `state == .idle` (chờ wake word); `.dictation` khi `.listening` /
  `.conversationMode`. Truyền trạng thái vào `configureRecognitionRequest` (thêm tham số).
- Lưu ý: request được tạo lại trong `restartRecognition()`, `enterConversationMode()` gọi
  `restartRecognition()` **trước** khi đổi `state`. Đặt `state` trước khi restart, hoặc truyền
  trạng thái đích vào. Không đổi thứ tự ngoài chỗ này.
- Xong khi: CI xanh.

**T4.3: Bỏ biến thể wake word dễ nhầm (B12)**
- Việc: xoá `"a vision"`, `"have vision"`, `"heavy vision"`, `"obey vision"` khỏi
  `wakeWordVariations`. Giữ các biến thể guard yêu cầu (`"ô kê vi dơn"`, `"ok vi dơn"`, `"vi dơn"`,
  `"ok vision"`).
- Xong khi: `testWakeWordIsStrippedInEitherLanguage` pass, guard xanh.

**T4.4: Kiểm tra âm thanh sau khi chụp (DAT #256/#358)**
- Việc: trong `VoiceAgentViewModel`, sau mỗi lần `acquireGlassesPhoto` trả về (có ảnh hay không),
  log `AVAudioSession.sharedInstance().currentRoute` (input/output portName + portType) và
  `isOtherAudioPlaying`, rồi gọi `configureAudioForGlasses(forceRestart: false)`.
- Không làm: không đổi category/mode/options, không tự `setActive(false)`. Nếu H11 cho thấy kính
  im lặng sau khi chụp, ghi vào PR để chủ dự án quyết định bước tiếp.
- Xong khi: guard xanh, CI xanh. Hardware: H2, H11.

### Phase 5: tài liệu khớp code (B16)

**T5.1 README.md**: viết lại ngắn gọn, đúng sự thật: app làm gì; ảnh mặc định là stream still
(~1–2 s), 12 MP là tuỳ chọn chậm; tính năng experimental cần Developer Mode; yêu cầu và thiết lập
(copy từ mục 8); giới hạn đã biết (mục 2.1, 2.2); lệnh test. Bỏ link tới file đã xoá.

**T5.2 CONTRIBUTING.md**: bỏ phần lỗi thời (OpenClaw, link `rayl15`, thư mục `Tests/`,
`CLAUDE.md`, `AIBackend` factory, `NativeTool`). Giữ quy ước branch, commit, PR, CI. Ghi: "Kế hoạch
và hiện trạng: PLAN.md".

**T5.3 CHANGELOG.md**: thêm vào `[Unreleased]` các mục Fixed/Changed của đợt này (mỗi dòng một
thay đổi, ngắn).

**T5.4 PR template**: thay tham chiếu `E2E_TEST_PLAN.md` bằng "PLAN.md §7 (H1–H12)"; bỏ "on-device MLX".

**T5.5 PLAN.md**: cập nhật mục 4 (đánh dấu lỗi nào đã sửa, commit nào), không xoá nội dung khác.

---

## 6. Spike cần chủ dự án duyệt (KHÔNG tự làm code sản phẩm)

Chỉ làm khi chủ dự án yêu cầu. Kết quả là một ghi chú ngắn (thêm mục mới vào PLAN.md hoặc mô tả PR):
đã thử gì, kết quả, đề xuất.

| ID | Nội dung | Vì sao |
|---|---|---|
| S1 | `VoiceInvocation` (DAT, experimental): "Hey Meta, mở OpenVision" mở app từ kính | Gần nhất với việc Visor chiếm "Hey Meta"; có báo lỗi ở [#344](https://github.com/meta/meta-wearables-dat-ios/issues/344), [#355](https://github.com/meta/meta-wearables-dat-ios/issues/355) |
| S2 | `MWDATSpeech`: nhận dạng giọng nói trên kính thay `SFSpeechRecognizer` + HFP | Bỏ được mic HFP chất lượng thấp; cần kiểm tra có hỗ trợ tiếng Việt không |
| S3 | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) cho vi-VN | Nhận dạng trên máy, câu dài; cần `#available` vì app hỗ trợ iOS 18 |
| S4 | Model: so `gemini-3.5-flash-lite` với `gemini-3.5-flash` trên 20 bài toán thật (đúng/sai, độ trễ, quota) | Flash-Lite là bậc yếu nhất cho giải toán |
| S5 | Đăng ký Meta sau khi Sideloadly ký lại: `MWDAT.TeamID` trong Info.plist đang rỗng (CI build với `DEVELOPMENT_TEAM=`). Có cần Team ID khớp không? | Có thể là lý do đăng ký thất bại; chưa xác minh |
| S6 | Port giao thức Visor lên iOS qua BLE L2CAP (`CBPeripheral.openL2CAPChannel`, PSM 0x80) | Cách duy nhất để ngang Visor. Rất lớn; phải chiếm quyền owner bằng token trích từ Meta AI; rủi ro điều khoản/pháp lý; iOS không có Wi-Fi Direct |

---

## 7. Quy trình kiểm thử trên phần cứng (chủ dự án chạy)

Chuẩn bị: iPhone 15 Pro (iOS 18+), kính đã ghép đôi và bật Developer Mode, app cài bằng Sideloadly,
quyền Ảnh = **Toàn bộ ảnh**. Mở Console.app trên Mac, lọc `OpenVision`.

| # | Bước | Đạt khi | Log cần thấy |
|---|---|---|---|
| H1 | Nhìn đề toán, bấm nút chụp trên gọng, nói "Ok Vision, giải câu này" | Kính đọc lời giải, iPhone hiện LaTeX, không báo thiếu ảnh | `[GlassesManager] Photo: <source> <w>x<h>` → `[GeminiLive] Attached image payload` |
| H2 | Nghe hết câu trả lời | Đọc 2–4 câu liền mạch, không đọc `$`, `\frac` | Không có `Stop command detected` khi đang đọc |
| H3 | Quan sát thanh âm lượng và loa kính khi trả lời | Không nhảy, không tiếng click | |
| H4 | Trong 120 s hỏi "Tại sao lại ra kết quả đó?" | Trả lời đúng ngữ cảnh | `Photo already in conversation history — not re-uploading` |
| H5 | Bấm ghi hình POV khi đang hội thoại | App không đơ | `Using shared microphone tap` |
| H6 | Không có ảnh, hỏi "giải câu này"; rồi hỏi "Thủ đô của Pháp là gì?" | Câu 1: app tự chụp (qua `[[CAPTURE]]`) rồi trả lời, hoặc nói không có ảnh. Câu 2: "Paris", không gắn ảnh | `Model asked to see — capturing a photo`; câu 2 không có `Attached image payload` |
| H7 | Hỏi bằng tiếng Anh sau khi chụp | Trả lời và đọc bằng tiếng Anh | |
| H8 | Mạng yếu (Network Link Conditioner 3G) | Có câu trả lời, hoặc kính nói "Mạng đang chậm…" trong ≤ 2 phút | `Sending request (attempt …)` |
| H9 | Cài đặt → Kính → **Chụp thử**, 3 lần mỗi chế độ (nhanh / 12 MP) | Ghi lại kích thước, thời gian, nguồn | Kết quả trên màn hình |
| H10 | Khoá màn hình, để iPhone trong túi, nói "Ok Vision…" và bấm nút chụp | Ghi lại cái gì chạy, cái gì không | |
| H11 | Ngay sau một lần chụp, nghe câu trả lời qua kính; thử cả khi đang phát nhạc | Kính vẫn phát tiếng; ghi lại nhạc có bật lại không | Dòng log route sau khi chụp (T4.4) |
| H12 | Chụp 1 ảnh bằng **camera iPhone**, rồi hỏi một câu không liên quan tới ảnh | Ảnh iPhone **không** được gửi | Không có `Attached image payload` |

Mẫu báo cáo:
```
Ngày / build: ____  iOS: ____  Firmware kính: ____  Meta AI: ____  Mạng: ____
H1 ☐ H2 ☐ H3 ☐ H4 ☐ H5 ☐ H6 ☐ H7 ☐ H8 ☐ H9 ☐ H10 ☐ H11 ☐ H12 ☐
H9 nhanh: ___×___ ___ s | 12 MP: ___×___ ___ s
Thời gian từ lúc nói xong tới câu đầu tiên được đọc (H1): ____ s
Ghi chú / log lỗi:
```

---

## 8. Thiết lập tài khoản và thiết bị (gộp từ SETUP.md cũ)

1. `cp Config.xcconfig.example Config.xcconfig` và `cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift`
   (cả hai bị gitignore). Điền `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, `META_APP_ID`,
   `CLIENT_TOKEN` (dạng đầy đủ `AR|<app id>|<hash>`), `APP_LINK_URL_SCHEME`. Ở Developer Mode,
   `META_APP_ID` có thể là `0`.
2. [Wearables Developer Center](https://wearables.developer.meta.com/): tạo app, điền Apple Team ID,
   bật quyền Camera. Sau khi đổi cấu hình: trong app bấm Huỷ đăng ký → Đăng ký lại.
3. Meta AI app: bật **Developer Mode**. Tuỳ phiên bản Meta AI: Cài đặt → Thiết bị → Kính →
   Developer Mode, hoặc Cài đặt → Giới thiệu → chạm số phiên bản 5 lần.
4. Trong app: Cài đặt → Kính → **"Cài/cập nhật thành phần trên kính"** (gọi
   `Wearables.shared.openDATGlassesAppUpdate()`; thiếu bước này session chết với "Device
   unavailable"). Cần firmware kính V126+, Meta AI V282+, iOS 17.2+.
5. Cài đặt → Gemini: dán API key (nhiều key cách nhau bằng dấu phẩy; nên từ các project Google
   Cloud khác nhau). Key lưu trong Keychain, không bao giờ nằm trong code.
6. Cài đặt iOS → Trợ năng → Nội dung được đọc → Giọng nói: tải giọng tiếng Việt Enhanced/Premium.
7. Cài IPA: chạy workflow **Build Unsigned IPA** (Actions → Run workflow), tải artifact
   `OpenVision-unsigned`, ký và cài bằng Sideloadly, rồi tin cậy nhà phát triển trong
   Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị. Với Apple ID miễn phí, app hết hạn sau 7 ngày.

---

## 9. Cách xem CI từ sandbox Linux

`gh run list` **không chạy** trong sandbox này (GH_HOST không khớp remote). Dùng `gh api`:

```bash
REPO=darwnlinz1/Visor-iOS-Solver
BR=feature/fix-ios-pipeline

# Mở PR (một lần). Không dùng `gh pr create`.
gh api repos/$REPO/pulls -f title="Fix iOS pipeline per PLAN.md" -f head="$BR" -f base="main" \
  -f body="Thực hiện PLAN.md. Xem từng commit (Task: Tx.y)."

# Các lần chạy của branch
gh api "repos/$REPO/actions/runs?branch=$BR&per_page=10" \
  --jq '.workflow_runs[] | "\(.id) \(.name) \(.status)/\(.conclusion) \(.head_sha[0:7])"'

# Job của một lần chạy, rồi log job lỗi
gh api repos/$REPO/actions/runs/<RUN_ID>/jobs --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'
gh api repos/$REPO/actions/jobs/<JOB_ID>/logs | grep -n -iE "error:|failed|XCTAssert|Test Case .* failed" | head -80
```

CI mất 10–40 phút. Chờ bằng `sleep 300` rồi kiểm tra lại; không chờ quá 90 phút cho một lần chạy.
Có thể đẩy vài task rồi mới chờ, nhưng nếu CI đỏ thì phải tìm đúng commit gây lỗi.

---

## 10. Mẫu báo cáo cuối của agent

```
PR: <link>
Task đã xong: T0.1 (sha) ✅ CI xanh | T0.2 (sha) ✅ | …
Task chưa xong / bị chặn: Tx.y: lý do, đã thử gì
Test fail còn lại: <tên test>: có từ trước? nguyên nhân?
Cần chủ dự án chạy trên kính: H…
Phát hiện mới (không có trong PLAN): …
```
