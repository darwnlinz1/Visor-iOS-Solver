# PLAN.md v2: OpenVision iOS, trả lời hoàn toàn bằng giọng nói (dành cho coding agent)

> Cập nhật: 21/11/2026, bản v2, thay thế v1. Thay đổi so với v1:
> - **Bỏ kênh DISPLAY** (lời giải LaTeX hiện trên iPhone). Mọi câu trả lời được **đọc qua loa kính**.
> - Thêm: module đọc toán tiếng Việt, bộ máy đọc lời giải nhiều bước có chỉnh tốc độ, màn hình
>   "Trực tiếp" (hội thoại đang diễn ra), Cài đặt mới, công cụ gỡ lỗi, thiết kế lại giao diện.
> - Phase 0–1 của v1 đã xong (PR #2). Việc còn lại của v1 (DAT 1.1.0, đường ảnh, nhận dạng giọng)
>   được giữ và đánh số lại (Phase 7–8).
> - **v2.1 (21/11/2026):** chủ dự án đã trả lời D1–D6 (mục 6). App chỉ dùng cho bài tập và thi:
>   trắc nghiệm đọc "Câu 1: A. Câu 2: B."; tự luận đọc từng dòng "Dòng 1: …" có nghỉ, tốc độ riêng.
>   Luôn đọc hết; màn hình hiện đầy đủ; không bao giờ bảo "xem màn hình điện thoại".
> Nếu comment trong code mâu thuẫn với file này, tin file này. Nếu file này mô tả hiện trạng khác
> với code, tin code và ghi chú lại trong PR.

---

## 0. Quy tắc làm việc cho agent (đọc trước khi làm bất cứ gì)

1. **Thứ tự:** làm theo phase (2 → 9), trong phase làm theo số task. Mỗi task là **một commit**.
2. **Branch:** tạo `feature/voice-v2` từ `main` nếu PR #2 đã merge, nếu chưa thì từ
   `feature/fix-ios-pipeline`. Mở **một** PR vào `main`. Không commit thẳng `main`, không force push.
3. **Commit message:** `Fix: …`, `Add: …`, `Refactor: …`, `Docs: …`, `Chore: …`, `Test: …`
   (dòng đầu ≤ 72 ký tự), dòng sau ghi `Task: Tx.y`.
4. **Môi trường:** sandbox Linux, **không có Xcode**. Chạy được ở local:
   `python3 scripts/blueprint/verify_blueprint.py` (luôn 0 failed), các script Python, và
   `scripts/swift-local/run.sh` (Swift 6.3 có sẵn trong sandbox: biên dịch và chạy test cho code thuần
   trong `OpenVision/Services/Speech/`, xem §11).
   Build và test iOS chạy trên GitHub Actions (mục 9). Task chỉ xong khi CI của commit đó xanh,
   hoặc lỗi còn lại được chứng minh là có từ trước.
5. **File Swift mới:** được phép, nhưng **chỉ** đăng ký vào `project.pbxproj` bằng
   `scripts/pbxproj_files.py` (tạo ở T2.1). Không sửa tay pbxproj.
6. **Không làm ngoài plan:** không thêm dependency (không thư viện LaTeX bên thứ ba), không backend
   mới, không OpenRouter, không danh sách từ khoá đoán ý câu hỏi.
7. **Giữ nguyên bất biến âm thanh** (guard lesson 1–4): một tap mic duy nhất trong
   `VoiceCommandService`; `configureForGlasses` dùng `.playAndRecord` + `mode: .default` +
   `[.mixWithOthers, .allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker]`; không gọi
   `setPreferredInput` trong route change; chờ ≥ 350 ms sau TTS; đặt `.speaking` +
   `isBargeInPaused = true` **trước** khi xếp câu nói. Không đổi category/mode khi đang đọc.
8. **Logic thuần phải test được:** parser, bộ đọc toán, lệnh giọng nói, máy trạng thái đọc nằm
   trong enum/struct không phụ thuộc UIKit/AVFoundation, có unit test chạy trên simulator.
   Mỗi file test mới phải được thêm vào danh sách suite trong `scripts/e2e/run-simulator-tests.sh`
   (nếu không, CI biên dịch nhưng không chạy nó).
   Giữ các tên mà `scripts/blueprint/verify_ipa_symbols.sh` tìm trong IPA: `RecentPhotoScanner`,
   `cleanSpokenAudio`, `conversationHistory`, `PhotoPayload`, `streamGenerateContent`, `SolverIntent`.
   Khi một check của guard không còn đúng với thiết kế v2, **sửa check** cho đúng tên/hành vi mới
   trong cùng commit, không xoá check mà không có check thay thế.
9. **Bí mật và riêng tư:** không commit hay log API key, `CLIENT_TOKEN`, Team ID. Log có câu hỏi
   của người dùng chỉ lưu trên máy; chỉ xuất ra khi người dùng bấm "Xuất log".
10. **Phần cứng:** việc nào chỉ kiểm được trên kính thì viết code + log rõ, ghi trong PR
    "Cần chủ dự án chạy H…" (mục 7). Không tuyên bố đã chạy trên kính.
11. Nếu bị chặn quá 2 lần ở cùng một task: dừng, báo cáo theo mẫu mục 10.

---

## 1. Mục tiêu sản phẩm (v2)

App dùng cho **bài tập và đề thi** (chủ yếu toán phổ thông, nhiều trắc nghiệm). Người đeo
**Ray-Ban Meta** bấm chụp, nói "Ok Vision" + câu hỏi tự do (Việt hoặc Anh). Kính **đọc hết** câu trả lời:
1. **Trắc nghiệm** (gồm cả đúng/sai và trả lời ngắn): chỉ đọc đáp án, gọn:
   "Câu 1: A. Câu 2: C. Câu 3: a đúng, b sai, c đúng, d sai. Câu 4: 2 phẩy 5."
2. **Tự luận**: đọc **từng dòng lời giải** như viết trên giấy, "Dòng 1: …", "Dòng 2: …", có khoảng
   nghỉ giữa các dòng, với **tốc độ riêng** (chậm hơn trắc nghiệm), rồi đọc đáp số.
3. Công thức được đọc **tự nhiên bằng tiếng Việt** ("x bình phương trừ 5 x cộng 6 bằng 0",
   "tích phân từ 0 đến 1 của…", "căn bậc hai của…").
4. Người đeo **điều khiển nhịp đọc**: tạm dừng, đọc lại dòng, dòng tiếp, chậm lại, nhanh lên,
   và chế độ **đọc chép** (dừng sau mỗi dòng chờ lệnh "tiếp" để kịp viết).
5. Không bao giờ nói "câu trả lời dài quá, xem trên điện thoại". Màn hình hiện **đầy đủ** mọi dòng.

Vai trò của iPhone:
- Màn hình **Trực tiếp**: theo dõi hội thoại khi nó diễn ra (câu hỏi, ảnh, câu trả lời chia theo
  bước, đoạn đang đọc được tô sáng), có nút điều khiển đọc và ô gõ câu hỏi.
- **Lịch sử**: xem lại và **đọc lại** câu trả lời cũ.
- **Cài đặt**: mọi tuỳ chọn đọc (tốc độ, nghỉ, chế độ, cách đọc toán, từ điển phát âm, nút thử đọc).
- **Gỡ lỗi**: log, dòng thời gian từng lượt hỏi, câu trả lời thô so với văn bản được đọc.

Không phải mục tiêu: hiển thị LaTeX đẹp trên màn hình, chạy offline, thay thế Meta AI.

---

## 2. Sự thật kỹ thuật đã xác minh

### 2.1 Vì sao app này khác Visor Android về bản chất
- [Visor](https://github.com/macedonga/visor) **thay thế** Meta AI, nói giao thức riêng của Meta
  qua BLE L2CAP (PSM 0x80), RFCOMM và Wi-Fi Direct; "Hey Meta", mic, nhận dạng và giọng đọc do
  kính xử lý. App này là **app phụ** qua Meta DAT SDK: tự làm wake word (`SFSpeechRecognizer`),
  mic qua Bluetooth HFP, giọng đọc `AVSpeechSynthesizer`. Đây là giới hạn kiến trúc.

### 2.2 Giới hạn của Meta DAT SDK (iOS)
| Sự thật | Nguồn |
|---|---|
| `Camera.photo` qua Bluetooth Classic: 720p ≈ 8,7 s, 12 MP ≈ 49 s; `stream.capturePhoto` (1440×1080) ≈ 1 s. App đang dùng Bluetooth Classic. | [DAT #363](https://github.com/meta/meta-wearables-dat-ios/issues/363) |
| Gen 1: `Camera.photo` lỗi `CaptureRequestError 6`. | [DAT #383](https://github.com/meta/meta-wearables-dat-ios/issues/383) |
| Bấm nút chụp khi stream đang chạy: kính tạm dừng session. | [DAT #312](https://github.com/meta/meta-wearables-dat-ios/issues/312) |
| Khi camera stream chạy, kính tắt âm thanh khác; A2DP có thể không bật lại. | [#256](https://github.com/meta/meta-wearables-dat-ios/issues/256), [#358](https://github.com/meta/meta-wearables-dat-ios/issues/358) |
| `Inputs`, `Camera.photo`, `Speech`, `VoiceInvocation` là experimental, cần Developer Mode. | [CHANGELOG DAT](https://github.com/meta/meta-wearables-dat-ios/blob/main/CHANGELOG.md) |
| Tài liệu DAT hiện khuyến nghị Bluetooth LE + Wi-Fi làm mặc định, bỏ `external-accessory`. | `plugins/mwdat-ios/skills/getting-started/SKILL.md` (repo DAT) |
| DAT 1.1.0 (20/11/2026): `pause()/resume()`, `notRegistered`, `RegistrationError.unauthorized`. App ghim 1.0.1. | CHANGELOG DAT |

### 2.3 Gemini
- Model chain `gemini-3.5-flash-lite` → `gemini-3.1-flash-lite`; Flash-Lite là bậc yếu nhất.
- `maxOutputTokens` 8192; `finishReason` hiện không được kiểm tra (xem N12).

### 2.4 Giọng đọc Apple (AVSpeechSynthesizer)
- Mỗi `AVSpeechUtterance` có `rate` (0…1, mặc định 0,5), `preUtteranceDelay`, `postUtteranceDelay`.
  Không đổi được rate của utterance đã xếp hàng; muốn đổi tốc độ giữa chừng phải dừng và xếp lại.
- Có `pauseSpeaking(at:)` / `continueSpeaking()` và delegate `didPause`, `didContinue`,
  `willSpeakRangeOfSpeechString` (biết đang đọc tới chữ nào, dùng để tô sáng).
- Utterance quá dài có thể bị dừng giữa chừng (diễn đàn Apple, thread 737685: dừng sau ~300 từ).
  → **Mỗi utterance chỉ một câu hoặc một công thức.**
- SSML (`AVSpeechUtterance(ssmlRepresentation:)`, iOS 16+) có nhưng hành vi theo từng giọng không
  ổn định → không dùng trong bản chính (spike S8).
- Giọng tiếng Việt đọc chữ cái Latinh đứng riêng, số thập phân, chữ Hy Lạp thế nào **chưa được
  kiểm chứng** → spike S7, dùng màn hình "Thử đọc" trong Cài đặt.
- Khi dùng mic kính, đầu ra đi qua HFP (chất lượng cuộc gọi). Đọc lời giải dài sẽ kém rõ hơn
  nhạc A2DP. Không được đổi category để cải thiện (lesson 2) → chỉ nghiên cứu (spike S9).

### 2.5 Cách người Việt đọc công thức (quy ước dùng cho module đọc toán)
Đây là cách đọc phổ thông trong trường học; người dùng có thể sửa từng mục trong từ điển phát âm.
`x²` "x bình phương", `x³` "x lập phương", `xⁿ` "x mũ n", `√x` "căn x" / "căn bậc hai của x",
`∛x` "căn bậc ba của x", `3/4` "ba phần tư", `a/b` "a trên b", `−3` "âm 3", `2,5` "2 phẩy 5",
`f'(x)` "f phẩy x", `∫₀¹` "tích phân từ 0 đến 1", `lim` "giới hạn khi … tiến tới …",
`log₂ 8` "lô-ga-rít cơ số 2 của 8", `sin/cos/tan/cot` "sin / cốt / tang / cô-tang",
`Δ` "đen-ta", `→AB` "véc-tơ A B", `∈` "thuộc", `[1; 3]` "đoạn từ 1 đến 3", `30°` "30 độ".
Bảng đầy đủ ở mục 4.3.

---

## 3. Hiện trạng

### 3.1 Đã xong (Phase 0–1 của v1, PR #2, CI + E2E xanh ở `dd04593`)
E2E chạy được lần đầu (ký ad-hoc simulator); tham chiếu tài liệu cũ đã sửa; Info.plist `arm64`,
bỏ `NSAllowsArbitraryLoads`; không in config; TTL ảnh 120 s / 5 lần; không gửi lại ảnh đã có trong
lịch sử; upload 3072 px q0.85; bỏ danh sách từ khoá, chỉ dùng `[[CAPTURE]]`.

### 3.2 Lỗi còn mở từ v1 (giữ ID cũ)
- **B6** RecentPhotoScanner nhận mọi ảnh ≥ 1200 px trong 120 s (ảnh riêng tư bị gửi đi) → T7.6.
- **B8** `captureFullResolutionPhoto` sai thứ tự nguồn, timeout 3 s, không ghi nguồn → T7.3.
- **B9** chụp đồng thời dùng vòng poll, fallback lặp lại → T7.2, T7.5.
- **B11** nhận dạng giọng chạy trên server, `taskHint = .search` → T8.1, T8.2.
- **B12** biến thể wake word dễ nhầm → T8.3.
- **B15** DAT 1.0.1 → T7.1. **B16** README/CONTRIBUTING sai → Phase 9.

### 3.3 Phát hiện mới khi đọc code (21/11/2026)
N1 và N2 đã thấy trên CI. N6, N7, N9, N10 là **suy ra từ việc đọc code**, chưa chạy trên máy: khi sửa,
viết test tái hiện trước rồi mới sửa.

| ID | Vấn đề | Vị trí | Sửa ở |
|---|---|---|---|
| N1 | 3 test `BlueprintPhotoLibraryE2ETests` luôn bị skip trên CI (quyền Ảnh chưa `.authorized` lúc chạy test). | `scripts/e2e/run-simulator-tests.sh` | T2.3 |
| N2 | `GlassesManager.init` dùng `Wearables.shared` vô điều kiện; nếu `Wearables.configure()` lỗi thì app crash lúc khởi động (đã thấy trên CI). | `GlassesManager.swift` (`private let wearables`) | T2.5 |
| N3 | App dùng đường Bluetooth Classic, tài liệu DAT khuyến nghị BLE + Wi-Fi. | `Info.plist` | Quyết định D2 |
| N4 | `cleanSpokenAudio` xoá lệnh LaTeX **trước** `SpokenMath`: `\frac{1}{2}` thành "12", `\sqrt{x}` thành "x", `x \le 2` thành "x 2"; xoá dấu `-` đầu dòng ("-2x+4=0" đọc thành "2x+4=0"); "2*3*4" thành "234". | `TTSService.cleanSpokenAudio`, `enqueue` | T3.3 |
| N5 | Ngôn ngữ chọn theo từng câu: dòng công thức có ≥ 2 từ ASCII ≥ 3 chữ ("f(x) = sin x + cos x.") bị đọc bằng giọng tiếng Anh giữa câu trả lời tiếng Việt. | `TTSService.sentenceIsVietnamese` | T5.1 |
| N6 | Khi đang đọc câu trả lời (state `.processing`), bộ nhận dạng tích luỹ chính tiếng đọc của app; "Ok Vision …" sớm không còn nằm trong 15 ký tự đầu nên lệnh ngắt hỏng; nếu task nhận dạng kết thúc (~1 phút) thì không ai khởi động lại → mic điếc tới hết câu trả lời. | `VoiceCommandService.handleRecognitionResult` (`.processing`), `restartIfRecognizerEnded` | T5.3 |
| N7 | Câu trả lời không bắt đầu bằng giọng nói (giữ nút "chụp và giải", gõ phím, đọc lại): bộ đếm 30 s của conversation mode vẫn chạy và `stopSession()` cắt ngang câu trả lời. | `startConversationTimeout`, `onConversationTimeout` | T5.3 |
| N8 | `ttsSpeakingChanged(false)` mở lại mic ngay, bỏ qua lớp chờ 350 ms (lớp này chỉ đổi `agentState`). | `VoiceAgentViewModel.ttsSpeakingChanged` | T5.3 |
| N9 | "Ok Vision, <câu hỏi>" khi đang đọc: dừng TTS nhưng không dừng Gemini; câu hỏi có thể bị mất; stream có thể đọc lại từ đầu. | `onWakeWordDetected`, `handleCommandComplete` | T5.3 |
| N10 | Gõ câu hỏi khi chưa có phiên: câu trả lời bị bỏ (guard `isSessionActive`); câu trả lời cho câu gõ không vào Lịch sử (`historyAwaitingReply` không được đặt). | `sendTypedCommand` | T6.2 |
| N11 | Lịch sử lưu văn bản DISPLAY (LaTeX); ảnh lưu base64 lặp lại mỗi câu hỏi; lỗi decode `conversations.json` thì lần lưu sau ghi đè mất lịch sử. | `ConversationManager`, `recordAssistantReply` | T4.3, T6.3 |
| N12 | `finishReason` không được kiểm tra: câu trả lời bị cắt vì `MAX_TOKENS` vẫn coi là thành công. | `GeminiLiveService.performStreamingRequest` | T4.3 |
| N13 | `SettingsSecretsTests`, `TextChunkingTests` không bao giờ chạy trên CI (script chỉ chạy các suite Blueprint*). | `run-simulator-tests.sh` | T2.2 |
| N14 | 145 lệnh `print(` không vào OSLog; 58 `NSLog`; không có logger chung → không làm được màn hình log. | toàn bộ `OpenVision/` | T2.4 |
| N15 | `MetricsCollector` có dòng thời gian từng lượt nhưng không ai hiển thị; lượt không có tiếng đọc thì bị "treo" và dính vào lượt sau. | `Services/Telemetry/` | T6.5 |
| N16 | `ParticleEffect` tạo thêm `Timer` mỗi lần `onAppear` (rò rỉ); giao diện lẫn tiếng Anh/Việt; link GitHub trong Cài đặt sai tên repo. | `AnimatedBackground.swift`, `MainTabView`, `SettingsView` | T6.1, T6.4 |
| N17 | Prompt coi "explain step by step" là chế độ Gia sư (giấu đáp án), trùng với yêu cầu "giải chi tiết từng bước". | `buildSystemPrompt` | T4.1 |
| N18 | Một số enum lạ trong `settings.json` làm hỏng cả hai lần decode → **toàn bộ cài đặt về mặc định**. | `SettingsManager.loadSettings` | Quy tắc ở 4.6 |

### 3.4 Bản đồ mã nguồn (hiện có và sẽ thêm)
| File | Trách nhiệm |
|---|---|
| `OpenVision/App/OpenVisionApp.swift` | Khởi động, `Wearables.configure()`, URL callback của Meta AI |
| `OpenVision/Managers/GlassesManager.swift` | Đăng ký, `DeviceSession`, camera, ảnh, nút chụp (`MWDATInputs`) |
| `OpenVision/Managers/SettingsManager.swift`, `Models/AppSettings.swift` | Cài đặt, lưu `settings.json` (key ở Keychain) |
| `OpenVision/Managers/ConversationManager.swift`, `Models/Conversation.swift` | Lịch sử, lưu `conversations.json` |
| `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` | Điều phối: phiên, `sendCommand`, ảnh, TTS streaming, lịch sử; chứa `CapturedPhotoContext`, `SolverIntent`, `RecentPhotoScanner`, `PhotoPayload`, `TextChunking` |
| `OpenVision/Views/VoiceAgent/VoiceAgentView.swift` | Màn hình chính hiện tại (sẽ thành Trực tiếp) |
| `OpenVision/Services/GeminiLive/GeminiLiveService.swift` | REST SSE, retry, xoay key, model chain, lịch sử 6 entry, `[[CAPTURE]]`/`[[END]]`, prompt, parser |
| `OpenVision/Services/TTS/TTSService.swift` | Giọng Apple, `cleanSpokenAudio`, `SpokenMath`, hàng đợi utterance |
| `OpenVision/Services/Voice/VoiceCommandService.swift` | `AVAudioEngine` + tap mic duy nhất, `SFSpeechRecognizer`, wake word, barge-in |
| `OpenVision/Services/Audio/AudioSessionManager.swift` | `AVAudioSession`, mic HFP của kính |
| `OpenVision/Services/Telemetry/*` | `MetricsCollector`, `TurnTimeline` (chưa ai hiển thị) |
| `OpenVision/Views/Components/*`, `History/*`, `Settings/*` | Thành phần giao diện, Lịch sử, Cài đặt |
| **Mới** `OpenVision/Services/Speech/` | `VietMathSpeech` (+ splitter, lexer, parser, reader, từ điển), `AnswerFormat`, `ReplyAssembler`, `ReadingEngine`, `ReadingCommand` |
| **Mới** `OpenVision/Utilities/Helpers/AppLog.swift` | Logger chung + bộ đệm cho màn hình Log |
| **Mới** `scripts/pbxproj_files.py` | Đăng ký / gỡ file Swift trong pbxproj |
| `scripts/blueprint/verify_blueprint.py`, `verify_ipa_symbols.sh` | Guard tĩnh, kiểm tra ký hiệu trong IPA |
| `scripts/e2e/run-simulator-tests.sh`, `.github/workflows/*` | Test simulator, CI, build IPA |

---

## 4. Thiết kế mới

### 4.1 Luồng từ câu hỏi tới giọng đọc
```
Câu hỏi + ảnh → Gemini (định dạng v2.1: TYPE + Q / P / L / FINAL / ANSWER, toán trong $…$)
  → AnswerFormat.parse / completedSections(in:)     tách đoạn theo thẻ khi stream tới
  → VietMathSpeech.render(đoạn)                      đổi công thức thành lời tiếng Việt
  → ReadingPlan (danh sách ReadingSegment)           mỗi đoạn: loại, chữ hiển thị, các mẩu đọc
  → ReadingEngine                                    xếp utterance ngắn, tốc độ, nghỉ, điều khiển
  → TTSService (AVSpeechSynthesizer, giọng theo ngôn ngữ của câu trả lời)
Song song: LiveConversationView hiển thị ReadingPlan + đoạn đang đọc; History lưu ReadingRecord.
```

### 4.2 Định dạng câu trả lời v2.1 (hợp đồng với Gemini)
Gemini **tự nhận dạng loại bài** và trả lời theo một trong các khuôn dưới. Thẻ viết bằng ASCII để parse
chắc chắn; app tự đọc nhãn theo ngôn ngữ người hỏi ("Câu 1" / "Question 1", "Dòng 1" / "Line 1").
Mỗi thẻ đứng đầu một dòng. Dòng đầu tiên luôn là `TYPE:`.
```
TYPE: MCQ                      trắc nghiệm, đúng/sai, trả lời ngắn
Q1: A
Q2: C
Q3: a Đ, b S, c Đ, d S         câu đúng/sai (kiểu đề 2025): mỗi ý một chữ Đ hoặc S
Q4: 2,5                        câu trả lời ngắn: chỉ con số
```
```
TYPE: ESSAY                    tự luận, chứng minh, bài có lời văn
P1: Bài 1                      chỉ khi có nhiều bài
L1: Ta có $\Delta = b^2 - 4ac = 9$.
L2: Vì $\Delta > 0$ nên phương trình có hai nghiệm phân biệt.
L3: $x_1 = 2$, $x_2 = \frac{1}{2}$.
FINAL: Vậy tập nghiệm là $S = \{\frac{1}{2}; 2\}$.
```
```
TYPE: MIXED                    đề vừa trắc nghiệm vừa tự luận: khối Q trước, rồi các P / L / FINAL
TYPE: OTHER                    câu hỏi không phải bài tập ("đây là đâu", dịch, giải thích)
ANSWER: <câu trả lời; có thể nhiều dòng ANSWER:>
```
Quy tắc trong prompt:
- `MCQ`: **chỉ** đáp án, không giải thích, không chép lại đề. Đánh số theo đề (Câu 5 → `Q5`). Trả lời
  mọi câu nhìn thấy trong ảnh; câu không đọc được ghi `Q7: ?` (app đọc "Câu 7: không đọc được đề").
- `ESSAY`: mỗi `L` là **một dòng như viết trên giấy**: một phép biến đổi hoặc một câu lập luận ngắn,
  ≤ 25 từ, ≤ 2 công thức. Đủ mọi bước, không bỏ bước "dễ". Kết thúc bằng `FINAL`.
- Công thức **chỉ** trong `$…$` một dòng; không `$$`, không bảng, không markdown, không gạch đầu dòng.
- Không bao giờ nhắc tới màn hình điện thoại, không xin lỗi vì dài (D5).
- Giữ: kiểm tra lại kết quả trước khi trả lời, `[[CAPTURE]]`, `[[END]]`,
  "ALWAYS answer in the language the user used". Bỏ chế độ Gia sư (D1: luôn giải đầy đủ).
- Hỏi tiếp về một câu ("tại sao câu 3 chọn C?", "giải chi tiết câu 3") → trả lời `ESSAY` cho câu đó.

Quy tắc của parser (`AnswerFormat`, thuần, có test):
- Không phân biệt hoa thường; bỏ `**`, `-`, `#` trước thẻ. Bí danh: `CÂU n:` / `CAU n:` = `Qn`,
  `DÒNG n:` / `DONG n:` = `Ln`, `BÀI n:` = `Pn`, `ĐÁP SỐ:` / `KẾT LUẬN:` = `FINAL`, `TRẢ LỜI:` = `ANSWER`.
- Thiếu `TYPE:` → suy ra từ thẻ đầu tiên (`Q` → MCQ, `L` / `P` → ESSAY, còn lại OTHER).
- Văn bản không có thẻ nào → `OTHER`, tách thành câu.
- Khi stream: chỉ trả về mục đã **xong dòng**; giữ lại dòng cuối nếu nó có thể là nửa thẻ.
- `Q` đúng/sai: chuẩn hoá thành từng ý (chấp nhận Đ/S, D/S, T/F, đúng/sai, true/false).
- Xoá `[[END]]`; `[[CAPTURE]]` xử lý như hiện nay (không bao giờ đọc ra).
- `finishReason == MAX_TOKENS`: đọc phần đã có, rồi thêm mục thông báo "Lời giải dài nên mình dừng ở
  dòng N. Bạn hỏi 'giải tiếp' để mình giải nốt." ("giải tiếp" là câu hỏi mới gửi Gemini, khác lệnh
  đọc "tiếp tục" ở 4.4.)

Cách đọc từng loại (do `ReadingEngine`, tốc độ và khoảng nghỉ ở 4.6):
| Loại | Mục | Đọc | Tốc độ / nghỉ |
|---|---|---|---|
| MCQ | `Q3: C` | "Câu 3: C." | `mcqRate`, nghỉ `pauseBetweenAnswers` |
| MCQ đúng/sai | `Q3: a Đ, b S, c Đ, d S` | "Câu 3: a đúng, b sai, c đúng, d sai." | như trên |
| MCQ trả lời ngắn | `Q4: 2,5` | "Câu 4: 2 phẩy 5." | như trên |
| ESSAY | `P2: Bài 2` | "Bài 2." | `essayRate`, nghỉ `pauseBetweenLines` |
| ESSAY | `L1: …` | "Dòng 1." (nếu `readLineNumbers`) rồi nội dung qua `VietMathSpeech` | `essayRate` × `mathRateFactor` cho công thức, nghỉ `pauseBetweenLines` |
| ESSAY | `FINAL: …` | "Đáp số: …" | `essayRate` |
| OTHER | `ANSWER: …` | nội dung | `speechRate` |

### 4.3 Module đọc toán tiếng Việt: `VietMathSpeech`
Thư mục mới `OpenVision/Services/Speech/`. **Thuần Swift**, không import UIKit/AVFoundation.

Thành phần:
| Kiểu | Việc |
|---|---|
| `MathSpanSplitter` | Tách văn bản thành mẩu lời văn và mẩu công thức: `$…$`, `\(…\)`, `\[…\]`, `$$…$$` (coi như một dòng). Nhận cả "công thức trần" trong lời văn: ký tự Unicode toán (² ³ √ ≤ ≥ ≠ ≈ × ÷ ± ∞ ∫ ∑ π Δ → ⇒ ⇔ ∈ ∉ ⊂ ∪ ∩ ∅ °) và mẫu ASCII rõ ràng (`x^2`, `3/4`, `f(x) =`). Thận trọng: "1-5", "Ray-Ban", ngày "12/5/2026" giữ nguyên. |
| `MathLexer`, `MathParser` | LaTeX tập con → cây `MathNode` (đệ quy xuống). **Không bao giờ throw**: lệnh lạ thành `.unknown(name, args)`. |
| `MathNode` | `number`, `identifier`, `binary(op)`, `unary(op)`, `fraction`, `power`, `subscript`, `root(index)`, `function(name, arg)`, `group`, `abs`, `integral(lower, upper, body, variable)`, `limit(variable, target, body)`, `sum/product(from, to, body)`, `vector`, `angle`, `triangle`, `set`, `interval`, `cases([rows])`, `matrix(rows)`, `text`, `unknown`. |
| `VietnameseMathReader` | `MathNode` → mảng `SpeechPiece` (`.words(String)`, `.pause(ms)`), theo `MathReadingStyle`. |
| `EnglishMathReader` | Bộ đọc tối giản cho câu trả lời tiếng Anh (chuyển các từ tiếng Anh của `SpokenMath` sang đây). |
| `PronunciationDictionary` | Bảng mặc định (hàm, chữ Hy Lạp, đơn vị, tên chữ cái) + ghi đè của người dùng (Cài đặt). Áp dụng theo **token nguyên**, không theo chuỗi con. |
| `VietMathSpeech.render(_ text:, language:, style:) -> [SpeechPiece]` | Điểm vào duy nhất. Lời văn giữ nguyên (chỉ chuẩn hoá số, đơn vị, ký hiệu). |

`MathReadingStyle` (lấy từ Cài đặt, mục 4.6):
- `verbosity`: `natural` (tự nhiên) hoặc `explicit` (rõ ràng: thêm "hết căn", "hết mũ",
  "hết phân số", "mở ngoặc / đóng ngoặc" khi cấu trúc lồng nhau).
- `symbolicFraction`: "trên" (mặc định) hoặc "phần" cho `a/b` có chữ; phân số số luôn "một phần hai".
- `negativeWord`: "âm" (mặc định) hoặc "trừ" cho dấu trừ một ngôi.
- `letterStyle`: `asWritten` (đưa chữ Latinh cho giọng đọc) hoặc `vietnameseNames`
  (a, bê, xê, đê, e, ép, giê, hát, i, gi, ca, lờ, mờ, nờ, o, pê, quy, rờ, ét, tê, u, vê, vê kép,
  ích, i, dét; chữ hoa đọc giống chữ thường). **Mặc định `vietnameseNames` (D3)**: đọc chắc chắn đúng
  kiểu lớp học, không phụ thuộc giọng máy đọc chữ Latinh ra sao. S7 dùng để kiểm tra lại.

Ràng buộc bắt buộc (có test):
- Đầu ra không bao giờ chứa `\`, `$`, `{`, `}`, `^`, `_`.
- Mỗi `SpeechPiece.words` ≤ 200 ký tự (để mỗi utterance ngắn, mục 2.4).
- Chạy < 5 ms cho một bước điển hình (đo trong test bằng `measure`).
- Lời văn tiếng Việt không có công thức đi qua **không đổi** (trừ số và ký hiệu).

Bảng quy tắc đọc (kiểu `natural`; cột "rõ ràng" chỉ ghi khi khác). Mỗi dòng là ít nhất một test.
Bảng ghi biến bằng chữ cái cho dễ đọc. Với mặc định `letterStyle = vietnameseNames` (D3), mỗi biến
một chữ cái được thay bằng tên tiếng Việt, ví dụ mẫu 1 ở H13 thành "ích bình phương trừ 5 ích cộng 6
bằng 0", `dx` thành "đê ích". Test chạy cả hai kiểu `letterStyle`.
| Viết | Đọc (tự nhiên) | Rõ ràng |
|---|---|---|
| `a + b`, `a - b`, `a = b` | a cộng b, a trừ b, a bằng b | |
| `-3`, `-x` (đầu biểu thức, sau `=`, sau `(`) | âm 3, âm x | |
| `2x`, `ab`, `2(x+1)` | 2 x, a b, 2 nhân x cộng 1 | 2 nhân mở ngoặc x cộng 1 đóng ngoặc |
| `a \cdot b`, `a \times b`, `a : b`, `a \div b` | a nhân b, a nhân b, a chia b, a chia b | |
| `\neq`, `<`, `>`, `\le`, `\ge`, `\approx`, `\pm` | khác, nhỏ hơn, lớn hơn, nhỏ hơn hoặc bằng, lớn hơn hoặc bằng, xấp xỉ, cộng trừ | |
| `x^2`, `x^3`, `x^n`, `x^{-1}` | x bình phương, x lập phương, x mũ n, x mũ âm 1 | |
| `e^{2x+1}` | e mũ 2 x cộng 1 (nghỉ ngắn sau mũ) | e mũ 2 x cộng 1, hết mũ |
| `(x+1)^2` | x cộng 1, tất cả bình phương | |
| `\frac{1}{2}`, `\frac{3}{4}`, `\frac{1}{10}` | một phần hai, ba phần tư, một phần mười | |
| `\frac{a}{b}`, `\frac{x}{2}` | a trên b, x trên 2 | |
| `\frac{x+1}{x-1}` | x cộng 1, trên x trừ 1 | phân số, tử số x cộng 1, mẫu số x trừ 1, hết phân số |
| `\sqrt{x}`, `\sqrt{2}` | căn x, căn 2 | căn bậc hai của x |
| `\sqrt[3]{x}` | căn bậc ba của x | |
| `\sqrt{x^2+1}` | căn của x bình phương cộng 1 | căn của x bình phương cộng 1, hết căn |
| x giữa hai dấu gạch đứng, `\lvert x \rvert`, `\left\lvert x \right\rvert` | giá trị tuyệt đối của x | |
| `n!` | n giai thừa | |
| `f(x)`, `f'(x)`, `f''(x)` | f x, f phẩy x, f hai phẩy x | f của x |
| `\sin x`, `\cos x`, `\tan x`, `\cot x`, `\sin^2 x` | sin x, cốt x, tang x, cô-tang x, sin bình phương x | |
| `\log_2 8`, `\log x`, `\ln x`, `e^x` | lô-ga-rít cơ số 2 của 8, lốc x, lốc nê-pe của x, e mũ x | |
| `\int_0^1 f(x)\,dx` | tích phân từ 0 đến 1 của f x, đê x | |
| `\int f(x)\,dx` | nguyên hàm của f x, đê x | |
| `\lim_{x \to 0}`, `x \to +\infty` | giới hạn khi x tiến tới 0 của, x tiến tới dương vô cùng | |
| `\sum_{i=1}^{n} a_i` | tổng từ i bằng 1 đến n của a i | |
| `x_1`, `u_{n+1}` | x một, u n cộng 1 | x chỉ số 1 |
| `\overrightarrow{AB}`, `\vec{a}` | véc-tơ A B, véc-tơ a | |
| `\widehat{ABC}`, `\angle ABC`, `\triangle ABC` | góc A B C, góc A B C, tam giác A B C | |
| `\perp`, `\parallel`, `\sim` | vuông góc với, song song với, đồng dạng với | |
| `\in`, `\notin`, `\subset`, `\cup`, `\cap`, `\emptyset` | thuộc, không thuộc, là tập con của, hợp, giao, tập rỗng | |
| `\mathbb{R}`, `\mathbb{N}`, `\mathbb{Z}`, `\mathbb{Q}` | tập số thực, tập số tự nhiên, tập số nguyên, tập số hữu tỉ | |
| `[1; 3]`, `(1; 3)`, `[1; 3)` | đoạn từ 1 đến 3, khoảng từ 1 đến 3, nửa khoảng từ 1 đến 3 | |
| `\forall`, `\exists`, `\Rightarrow`, `\Leftrightarrow` | với mọi, tồn tại, suy ra, tương đương | |
| `\infty`, `\Delta`, `\alpha`, `\beta`, `\pi` | vô cùng, đen-ta, an-pha, bê-ta, pi (đủ bảng chữ Hy Lạp trong từ điển) | |
| `30^\circ`, `30°`, `50\%` | 30 độ, 30 độ, 50 phần trăm | |
| `2.5`, `2,5`, `2{,}5` (câu trả lời tiếng Việt) | 2 phẩy 5 | |
| `C_5^2`, `\binom{5}{2}`, `A_5^2` | tổ hợp chập 2 của 5, tổ hợp chập 2 của 5, chỉnh hợp chập 2 của 5 | |
| `\begin{cases} x+y=3 \\ x-y=1 \end{cases}` | hệ phương trình: x cộng y bằng 3; x trừ y bằng 1 | hệ gồm 2 phương trình: thứ nhất…; thứ hai… |
| ma trận `\begin{pmatrix} 1 & 2 \\ 3 & 4 \end{pmatrix}` | ma trận 2 hàng 2 cột: hàng 1: 1, 2; hàng 2: 3, 4 | |
| `5 cm`, `3 m/s`, `60 km/h`, `2 kg` | 5 xen-ti-mét, 3 mét trên giây, 60 ki-lô-mét trên giờ, 2 ki-lô-gam | |
| `\text{nếu }` | đọc nguyên chữ | |
| lệnh lạ `\foo{x}` | bỏ tên lệnh, đọc đối số: x (và log cảnh báo cho màn hình Gỡ lỗi) | |

Ngoài phạm vi bản này: công thức hoá học (`H_2O` đọc thành "H 2 O"), đạo hàm riêng, tích phân bội
ngoài `\iint` cơ bản. Ghi vào Gỡ lỗi khi gặp để bổ sung sau.

### 4.4 Bộ máy đọc: `ReadingPlan` + `ReadingEngine`
File mới `OpenVision/Services/Speech/ReadingEngine.swift` (logic) và mở rộng `TTSService` (âm thanh).

Kiểu dữ liệu (thuần, `Codable` để lưu vào Lịch sử):
- `ReadingSegment { id, kind, title, displayText }` (file `Services/Speech/ReadingModel.swift`), với `kind` là
  `mcq(n) | problem(n) | line(n) | final | answer | notice`. `title` ví dụ "Câu 3", "Dòng 2".
  `displayText` là chữ model viết (công thức giữ dạng chữ, hiển thị bằng bộ làm đẹp đơn giản ở 4.5).
- `ReadingPlan { turnID, language (vi|en), answerType (mcq|essay|mixed|other), segments, isComplete }`,
  được **nối thêm đoạn** khi stream tới. Mẩu đọc (`[SpeechPiece]`) **không** lưu trong đoạn: `ReadingEngine`
  dựng chúng bằng `VietMathSpeech` lúc đọc tới đoạn đó, theo cài đặt hiện tại.
- `ReadingRecord { language, answerType, segments }`: bản lưu vào Lịch sử (trường tuỳ chọn
  `Message.reading`). Đọc lại thì dựng mẩu đọc mới theo cài đặt hiện tại (từ điển vừa sửa cũng có hiệu lực).
- Mẩu lời văn dài hơn 200 ký tự được tách tiếp tại dấu phẩy hoặc chấm phẩy gần nhất.

`ReadingEngine` (`@MainActor ObservableObject`):
- Trạng thái công khai: `state` (`idle | reading | paused | waitingForNext | finished`),
  `currentSegment`, `currentPieceRange` (từ `willSpeakRangeOfSpeechString`, để tô sáng chữ đang đọc),
  `liveRateMultiplier` (0,75 / 1 / 1,25 / 1,5).
- Lệnh: `start(plan)`, `append(segments)`, `finishAppending()`, `pause()`, `resume()`, `next()`,
  `previous()`, `repeatCurrent()`, `restartFromBeginning()`, `jump(to:)`, `stop()`, `setRate(_:)`.
- Cách đọc: **một utterance cho một mẩu** (một câu hoặc một công thức).
  - rate = tốc độ theo loại (`mcqRate` / `essayRate` / `speechRate`, bảng ở 4.2)
    × (`mathRateFactor` nếu là mẩu công thức) × `liveRateMultiplier`;
  - `postUtteranceDelay` = `pauseAfterFormula` cho mẩu công thức;
  - giữa hai mục nghỉ `pauseBetweenAnswers` (trắc nghiệm) hoặc `pauseBetweenLines` (tự luận);
  - `.pause(ms)` trong mẩu đọc thành khoảng nghỉ thật (utterance rỗng hoặc delay).
- Đổi tốc độ giữa chừng: dừng utterance hiện tại, đọc lại mẩu hiện tại với tốc độ mới.
- **Đọc chép** (`dictationMode`, chỉ áp dụng cho tự luận): sau mỗi dòng `L` chuyển `waitingForNext`; đi tiếp khi có lệnh "tiếp",
  nút kính, nút trên màn hình, hoặc sau `dictationAutoContinue` giây (0 = chờ lệnh). Tuỳ chọn
  `repeatFormulaInDictation`: đọc mỗi công thức hai lần.
- **Giọng theo cả câu trả lời**, không theo từng câu (sửa N5): ngôn ngữ của `ReadingPlan` quyết định
  giọng cho mọi mẩu, kể cả mẩu chỉ có công thức.
- Kiểm thử không cần âm thanh: `ReadingEngine` dùng protocol `SpeechSynthesizing`; test dùng bản giả
  ghi lại các utterance (văn bản, rate, delay) và giả lập callback xong/huỷ.

Điều khiển bằng giọng khi đang đọc (sửa N6–N9), trong `VoiceCommandService` + `ReadingCommand`:
- Khi `ReadingEngine.state` là `reading`: **xoá bộ đệm nhận dạng ở đầu mỗi đoạn** (để wake word có thể
  "nằm đầu" lại) và tự khởi động lại bộ nhận dạng nếu nó kết thúc. Lệnh phải có wake word ở đầu
  (chống tiếng vọng): "Ok Vision" + một trong các lệnh dưới.
- Khi `paused` hoặc `waitingForNext`: app đang im, nên chấp nhận lệnh **không cần wake word**.
- `ReadingCommand.parse(_ text:) -> ReadingCommand?` (thuần, có test, hai ngôn ngữ):
  | Lệnh | Câu nói (ví dụ) |
  |---|---|
  | `pause` | tạm dừng, dừng chút, pause |
  | `resume` | tiếp tục, đọc tiếp, tiếp, continue |
  | `next` | dòng tiếp, câu tiếp, bỏ qua, next |
  | `previous` | dòng trước, câu trước, quay lại, back |
  | `jump(n)` | đọc lại câu 3, đọc lại dòng 5, câu 3, dòng 5 |
  | `repeat` | đọc lại, lặp lại, nhắc lại, repeat |
  | `restart` | đọc lại từ đầu, from the start |
  | `slower` / `faster` | chậm lại, đọc chậm / nhanh lên, đọc nhanh |
  | `stop` | dừng lại, thôi, stop (dừng đọc, giữ kế hoạch để "đọc lại") |
- Sau wake word mà **không phải** lệnh đọc → coi là câu hỏi mới: dừng đọc, `gemini.interrupt()`,
  **giữ nguyên câu hỏi** và gửi đi (sửa N9).
- Trong khi `reading | paused | waitingForNext`: **không chạy** bộ đếm conversation timeout (sửa N7).
- Khi đọc xong (`finished`) hoặc bị dừng: chỉ bỏ `isBargeInPaused` và vào conversation mode sau
  350 ms kể từ utterance cuối (sửa N8, giữ check lesson 4).
- Phân biệt hai kiểu dừng: lệnh đọc `stop` ("Ok Vision dừng lại") chỉ dừng đọc, phiên vẫn mở, nói
  "đọc lại" thì đọc tiếp được. Kết thúc phiên vẫn như cũ: "tạm biệt / cảm ơn" (`[[END]]`), nút mic,
  hoặc hết thời gian im lặng sau khi đọc xong.
- Nút kính khi đang đọc: **gác lại** (D4). Làm được bằng `MWDATInputs` (experimental) nhưng chưa làm.

### 4.5 Giao diện mới
Tab (nhãn tiếng Việt): **Trực tiếp** | **Lịch sử** | **Cài đặt**. Màn hình Gỡ lỗi mở từ Cài đặt;
lớp phủ gỡ lỗi bật được trên màn hình Trực tiếp. Toàn bộ chữ trên giao diện bằng tiếng Việt.

**Trực tiếp** (thay bố cục `VoiceAgentView`; `VoiceAgentViewModel` vẫn là nơi điều phối):
- Thanh trạng thái trên cùng, các chip bấm được (mở đúng màn hình Cài đặt):
  Kính (chưa đăng ký / đã kết nối), Mic (kính / điện thoại, nhận dạng trên máy hay server),
  Gemini (có key, model), Ảnh (còn N giây, nguồn và độ phân giải), Trạng thái (Đang nghe /
  Đang nghĩ N s / Đang đọc bước k/n / Tạm dừng / Chờ "tiếp").
- Danh sách lượt hỏi của cuộc hội thoại hiện tại (`ConversationManager.currentConversation`
  + lượt đang diễn ra):
  - Bong bóng người dùng: chữ nhận dạng **cập nhật trực tiếp** khi đang nói, ảnh thu nhỏ (chạm để xem lớn).
  - Thẻ trả lời, hiện **đầy đủ** (D5): nhãn loại (Trắc nghiệm / Tự luận / Hỗn hợp / Khác).
    Trắc nghiệm: lưới "Câu 1: A  Câu 2: C …" (đúng/sai hiện từng ý). Tự luận: các dòng đánh số
    "Dòng 1 … Dòng n" và "Đáp số". Mục đang đọc được tô sáng và tự cuộn tới; chữ đang đọc được gạch
    chân theo `currentPieceRange`. Chạm một mục để đọc từ đó.
  - Công thức hiển thị bằng bộ làm đẹp đơn giản (`MathPrettyText`, thuần): `x^2` → x², `\sqrt{x}` → √x,
    `\frac{a}{b}` → a/b, `\le` → ≤, `\pi` → π… Không dùng KaTeX/WebView.
- Thanh điều khiển đọc (hiện khi có `ReadingPlan`): ⏮ mục trước, ⏯ tạm dừng/tiếp, ⏭ mục tiếp,
  🔁 đọc lại mục, chip tốc độ (0,75× / 1× / 1,25× / 1,5×), công tắc nhanh "Đọc chép" (tự luận).
- Ô soạn: nút mic (bắt đầu/dừng phiên), nút chụp từ kính, ô gõ câu hỏi. Gõ khi chưa có phiên thì tự
  mở phiên; câu trả lời cho câu gõ được lưu Lịch sử (sửa N10).
- Trạng thái trống: hướng dẫn 3 bước + danh sách kiểm tra (key Gemini, kính, quyền Ảnh, quyền Mic,
  quyền Nhận dạng giọng nói), mỗi mục bấm để sửa.
- `SwirlOrb` thu nhỏ thành biểu tượng trạng thái; bỏ `ParticleEffect` (rò rỉ Timer, N16).

**Lịch sử**: danh sách (tìm kiếm, xoá); chi tiết hiển thị các lượt như màn hình Trực tiếp; mỗi câu
trả lời có nút **Đọc lại** (dùng `ReadingRecord` đã lưu) và **Tiếp tục hội thoại** (`seedHistory` v2).

**Cài đặt** (nhóm theo thứ tự):
1. Kính Ray-Ban Meta (giữ nội dung hiện có).
2. Gemini (key).
3. Nghe: wake word, ngôn ngữ nghe, mic kính, tự kết thúc khi im lặng, âm báo.
4. **Đọc câu trả lời**, hai nhóm riêng:
   - *Trắc nghiệm*: tốc độ, nghỉ giữa các câu.
   - *Tự luận*: tốc độ, hệ số tốc độ công thức, nghỉ giữa các dòng, nghỉ sau công thức, đọc số dòng
     ("Dòng 1"), đọc chép (+ tự đi tiếp sau N giây, đọc công thức hai lần).
   - Chung: giọng Việt, giọng Anh, tốc độ cho câu trả lời thường (`speechRate`).
   Có nút **Nghe thử** đọc một đề mẫu (3 câu trắc nghiệm + 1 bài tự luận 4 dòng) với cài đặt hiện tại.
5. **Đọc toán tiếng Việt**: kiểu đọc (tự nhiên / rõ ràng), phân số chữ ("trên" / "phần"), số âm
   ("âm" / "trừ"), tên chữ cái, **Từ điển phát âm** (thêm / sửa / xoá / khôi phục mặc định),
   **Thử đọc**: ô nhập công thức hoặc chọn mẫu (15 mẫu ở mục 7, H13), nút nghe, hiện văn bản sẽ đọc.
6. Trợ lý: hướng dẫn riêng, ghi nhớ.
7. **Gỡ lỗi** (mục 4.7).
8. Giới thiệu: phiên bản app, phiên bản DAT SDK, model đang dùng, link repo đúng (sửa N16).

Bỏ khỏi Cài đặt: "Hiện hội thoại trên màn hình" (`showTranscripts`) → thay bằng "Ẩn chữ, chỉ nghe"
trong Đọc câu trả lời (giữ key cũ để decode không lỗi).

**Onboarding**: sửa chữ cho đúng sản phẩm mới (không còn "iPhone hiện lời giải có công thức");
trang cuối là danh sách quyền và thiết lập, mỗi dòng có nút cấp/mở.

Chung: token giao diện (cỡ chữ, khoảng cách, bo góc) đưa vào `Theme`; hỗ trợ Dynamic Type; mọi nút
điều khiển có nhãn VoiceOver tiếng Việt.

### 4.6 Cài đặt mới trong `AppSettings`
Quy tắc (do N18): **mọi lựa chọn kiểu enum lưu dưới dạng `String`** với giá trị mặc định, và có thuộc
tính tính toán trả về enum (giá trị lạ → mặc định). Không thêm enum `Codable` mới trực tiếp vào
`AppSettings`. Số thực được kẹp trong khoảng ở chỗ đọc. Mở rộng `testOlderSettingsFilesStillDecode`.

| Key | Kiểu | Mặc định | Khoảng / giá trị | Ý nghĩa |
|---|---|---|---|---|
| `speechRate` (đã có) | Float | 0.5 | 0.35–0.6 | Tốc độ câu trả lời thường (`OTHER`, thông báo) |
| `mcqRate` | Float | 0.5 | 0.35–0.6 | Tốc độ đọc đáp án trắc nghiệm |
| `essayRate` | Float | 0.42 | 0.3–0.6 | Tốc độ đọc tự luận (chậm hơn để kịp viết) |
| `pauseBetweenAnswers` | Double | 0.5 | 0–2 s | Nghỉ giữa các câu trắc nghiệm |
| `pauseBetweenLines` | Double | 1.2 | 0–5 s | Nghỉ giữa các dòng tự luận |
| `readLineNumbers` | Bool | true | | Đọc "Dòng 1", "Dòng 2" trước mỗi dòng |
| `mathRateFactor` | Double | 0.85 | 0.6–1.0 | Hệ số tốc độ cho mẩu công thức |
| `pauseAfterFormula` | Double | 0.3 | 0–1.5 s | Nghỉ sau mỗi công thức |
| `dictationMode` | Bool | false | | Đọc chép: dừng sau mỗi bước |
| `dictationAutoContinue` | Double | 0 | 0 (chờ lệnh) – 30 s | Tự đi tiếp |
| `repeatFormulaInDictation` | Bool | false | | Đọc công thức hai lần khi đọc chép |
| `mathVerbosity` | String | `"natural"` | `natural`, `explicit` | Kiểu đọc toán |
| `symbolicFractionWord` | String | `"tren"` | `tren`, `phan` | "a trên b" hay "a phần b" |
| `negativeWord` | String | `"am"` | `am`, `tru` | "âm 3" hay "trừ 3" |
| `letterStyle` | String | `"vietnameseNames"` | `vietnameseNames`, `asWritten` | Tên chữ cái (D3) |
| `pronunciationOverrides` | [String: String] | [:] | | Từ điển phát âm của người dùng |
| `hideTextSpeakOnly` | Bool | false | | Ẩn chữ trên màn hình Trực tiếp |
| `debugOverlay` | Bool | false | | Lớp phủ gỡ lỗi trên Trực tiếp |
| `verboseLogging` | Bool | false | | Log chi tiết (kể cả văn bản đọc) |

### 4.7 Gỡ lỗi
- `AppLog` (file mới `OpenVision/Utilities/Helpers/AppLog.swift`): `AppLog.info(.gemini, "…")`,
  `.debug/.warning/.error`. Ghi vào `os.Logger(subsystem: bundleID, category:)` **và** một bộ đệm vòng
  2000 dòng trong bộ nhớ (`@Published`) cho màn hình log. Danh mục: `app, glasses, gemini, voice,
  tts, reading, audio, photo, settings, history`. Không bao giờ ghi key hay token.
- Màn hình **Log**: lọc theo danh mục và mức, tìm kiếm, tạm dừng cuộn, sao chép, **Xuất log** (.txt
  qua share sheet). Có thêm nút gộp log SDK Meta (dùng `OSLogStore` như `dumpSDKLogs`).
- Màn hình **Lượt hỏi**: từ `MetricsCollector.recentTurns` → thời gian từ nói xong tới token đầu,
  tới tiếng đầu, tổng thời gian đọc, model, số đoạn, số mẩu, nguồn và kích thước ảnh, bị ngắt hay không.
  Sửa N15: lượt không có tiếng đọc phải được đóng (`abandonTurn`).
- Màn hình **Câu trả lời thô**: văn bản Gemini trả về, các đoạn đã tách, văn bản thực sự được đọc
  cho từng mẩu, cảnh báo của bộ đọc toán (lệnh lạ).
- **Lớp phủ trên Trực tiếp**: `agentState`, trạng thái `VoiceCommandService`, trạng thái `ReadingEngine`,
  tuyến âm thanh (mic/loa), lỗi gần nhất.

### 4.8 Những thứ bị gỡ bỏ
`SolutionView.swift` (SolutionWebView, SolutionSheet, SolutionButton, SolutionItem); thư mục
`Resources/SolutionRenderer` (KaTeX, marked, fonts, giấy phép) và khai báo của nó trong `project.yml`
+ pbxproj; `latestSolution`, `solutionWorthShowing`; nhánh DISPLAY của `parseDualChannel`,
`generateSpokenSummary` (câu "xem trên điện thoại"), `dualChannelFromHistory`, `streamingSpokenPrefix`
(thay bằng `AnswerFormat`); nút "Xem công thức" trong Lịch sử; chữ onboarding về lời giải trên màn
hình; dòng ghi công KaTeX/marked trong README; các test và check guard gắn với DISPLAY (thay bằng bản v2).
`SpokenMath` được thay bằng `VietMathSpeech` + `EnglishMathReader`.

---

## 5. Kế hoạch theo phase

Mỗi task: **Việc**, **Không làm**, **Xong khi**. Sau mỗi task: guard local, commit, push, chờ CI.

### Phase 2: hạ tầng (không đổi hành vi app)

**T2.1 Script đăng ký file Swift vào pbxproj**
- Việc: `scripts/pbxproj_files.py add <path>` / `remove <path>`. File dưới `OpenVision/` vào target app
  (Sources phase `5B369180DFE2DD0B99684491`), dưới `OpenVisionTests/` vào target test
  (`4082EAA7B9C9E911E29F7B44`). Thêm đủ 4 mục (PBXBuildFile, PBXFileReference, con của group, mục
  trong Sources phase); tạo PBXGroup nếu thư mục chưa có (ví dụ `Services/Speech`). ID 24 ký tự hex
  in hoa, sinh tất định từ SHA-1 của đường dẫn, kiểm tra không trùng. Lệnh chạy lại không đổi gì.
  Có `--self-test` chạy trên bản sao tạm của pbxproj: thêm rồi xoá một file giả, kết quả phải giống hệt ban đầu.
- Guard: check `project` thêm chiều ngược lại: mọi `path = X.swift;` trong pbxproj phải có file thật.
- Xong khi: `--self-test` pass ở local; guard xanh; CI build xanh.

**T2.2 CI chạy mọi suite test (N13)**
- Việc: trong `run-simulator-tests.sh`, chế độ `blueprint` chạy thêm `SettingsSecretsTests`,
  `TextChunkingTests` và mọi suite mới của plan này (liệt kê tường minh). `GeminiLiveSmokeTests` tự skip.
- Xong khi: log E2E có dòng "Executed" cho từng suite, 0 fail.

**T2.3 Test thư viện Ảnh không bị skip (N1)**
- Việc: tìm nguyên nhân (in `PHPhotoLibrary.authorizationStatus` trong `setUp`, kiểm tra
  `xcodebuild test-without-building` có cài lại app sau `simctl privacy grant` không). Sửa tối thiểu.
- Xong khi: 3 test `BlueprintPhotoLibraryE2ETests` được chạy (không skip) và pass. Nếu sau 2 lần thử
  vẫn không được: ghi rõ nguyên nhân trong PR và chuyển sang task sau.

**T2.4 `AppLog` và chuyển log**
- Việc: tạo `AppLog` (4.7). Thay `print(`/`NSLog(` bằng `AppLog` trong: `VoiceAgentViewModel`,
  `GeminiLiveService`, `TTSService`, `VoiceCommandService`, `GlassesManager`, `AudioSessionManager`,
  `OpenVisionApp`. Giữ nguyên nội dung thông điệp. Thông điệp có văn bản người dùng chỉ ghi khi
  `verboseLogging` bật.
- Guard: check mới, các file trên không còn `print(` / `NSLog(` (bỏ qua comment).
- Xong khi: guard xanh, CI xanh, log khởi động trong E2E vẫn hiện thông điệp của app.

**T2.5 Không crash khi SDK kính không khởi tạo được (N2)**
- Việc: `OpenVisionApp` ghi kết quả `Wearables.configure()` vào một cờ dùng chung
  (ví dụ `WearablesBootstrap.configureError`). `GlassesManager` lấy `Wearables.shared` **lười**, chỉ sau
  khi cấu hình thành công; nếu lỗi thì mọi hàm trả về sớm và đặt `errorMessage`
  "SDK kính chưa khởi tạo được: <lỗi>". Cài đặt → Kính hiện thông báo này.
- Kiểm chứng: bản Debug đọc biến môi trường `OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1` để bỏ qua
  `configure()`. `launch_smoke` trong `run-simulator-tests.sh` chạy thêm một lần với biến này
  (`SIMCTL_CHILD_OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1 xcrun simctl launch …`).
- Xong khi: CI xanh; console của lần khởi động có biến này **không** có `Fatal error`, và có dòng
  "SDK kính chưa khởi tạo được".

### Phase 3: module đọc toán tiếng Việt (4.3)
Làm trước Phase 4 để khi bỏ DISPLAY, công thức đã được đọc đúng ngay từ đầu. Cuối phase này module
được nối vào `TTSService` (T3.3), nên cả câu trả lời dạng cũ (SPOKEN) cũng hưởng lợi.

**T3.1 Tách mẩu, lexer, parser, AST**
- Việc: `MathSpanSplitter`, `MathLexer`, `MathParser`, `MathNode` trong `Services/Speech/`.
- Test (`OpenVisionTests/VietMathParserTests.swift`): mỗi cấu trúc ở bảng 4.3 parse ra đúng cây;
  ngoặc thiếu, lệnh lạ, chuỗi rỗng không crash.
- Xong khi: CI xanh.

**T3.2 `VietnameseMathReader` + `PronunciationDictionary` + `MathReadingStyle`**
- Việc: luật đọc theo bảng 4.3, cả hai kiểu `natural` / `explicit`; từ điển mặc định (hàm số, chữ Hy
  Lạp, đơn vị, tên chữ cái) + ghi đè từ `pronunciationOverrides`.
- Test (`OpenVisionTests/VietMathSpeechTests.swift`): bảng dữ liệu **≥ 80 ca** (đầu vào → câu đọc mong
  đợi), gồm mọi dòng của bảng 4.3 và 15 mẫu ở H13; ghi đè từ điển có hiệu lực; tên chữ cái theo
  `letterStyle`.
- Xong khi: CI xanh.

**T3.3 Lời văn, số, đơn vị, tiếng Anh; sửa thứ tự xử lý (N4)**
- Việc: chuẩn hoá số (thập phân dấu phẩy trong câu tiếng Việt, số âm), đơn vị, ký hiệu Unicode trong lời
  văn; `EnglishMathReader` (chuyển từ `SpokenMath`). Trong `TTSService`: `VietMathSpeech.render` chạy
  **trước**; `cleanSpokenAudio` chỉ còn là lưới an toàn bỏ thẻ và markdown, **không** xoá nghĩa toán,
  **không** xoá dấu `-` đầu dòng, không xoá `*` giữa số. Giữ `static func cleanSpokenAudio` và lời gọi
  `cleanSpokenAudio(text)` (guard lesson 5, ký hiệu IPA).
- Test: các ca hồi quy N4 (`\frac{1}{2}`, `\sqrt{x}`, `x \le 2`, "-2x + 4 = 0", "2*3*4").
- Xong khi: CI xanh; `testCleanSpokenAudio…` được cập nhật đúng hành vi mới.

**T3.4 Kiểm tra độ bền**
- Việc: test sinh 1000 chuỗi ngẫu nhiên (seed cố định) gồm ký tự LaTeX, Unicode toán, chữ Việt.
- Xong khi: không crash; đầu ra không chứa `\ $ { } ^ _`; mỗi mẩu ≤ 200 ký tự; tổng thời gian < 2 s.

### Phase 4: định dạng trả lời v2, bỏ DISPLAY

**T4.1 Prompt v2**
- Việc: viết lại `buildSystemPrompt()` theo 4.2 (Gemini tự nhận loại bài). Giữ các phần ảnh, `[[CAPTURE]]`,
  `[[END]]`, ngôn ngữ, kiểm tra lại kết quả toán, ngày giờ, hướng dẫn riêng, ghi nhớ. Bỏ hẳn
  "DUAL-CHANNEL", `SPOKEN:`, `DISPLAY:`, "2 to 4 complete sentences", "phone screen". Sửa N17.
- Guard (sửa `verify_blueprint.py`): thay check "2 to 4 complete sentences" và "SPOKEN:/DISPLAY:"
  bằng: prompt chứa `TYPE:`, `Q1:`, `L1:`, `FINAL:`; không chứa `DISPLAY:`; không chứa "phone screen".
  Giữ check "language the user used", "under 250 characters" (không có), `captureToken`.
- Test: thay `testSystemPromptKeepsTheDualChannelContractAndIsBilingual` bằng bản v2.1 (có đủ khuôn
  MCQ / ESSAY / MIXED / OTHER, có câu cấm nhắc màn hình điện thoại, không còn chế độ Gia sư).
- Xong khi: guard xanh, CI xanh.

**T4.2 `AnswerFormat` (parser v2)**
- Việc: file mới `OpenVision/Services/Speech/AnswerFormat.swift` (thuần): `parse(_ raw:) -> [AnswerSection]`
  và `completedSections(in accumulated:) -> [AnswerSection]` cho stream (4.2). `GeminiLiveService` gọi
  callback mới `onPartialSections([AnswerSection])` thay cho `onPartialSpoken`. Mất kết nối giữa chừng:
  giữ câu trả lời nếu đã có `ANSWER` (thay điều kiện dùng `parseDualChannel` hiện nay).
- Test: chuyển các test parser cũ sang v2: biến thể thẻ, chữ "display"/`\displaystyle` trong nội dung
  không cắt câu, tính "tiền tố" khi stream (mỗi kết quả trung gian là tiền tố của kết quả cuối),
  `[[END]]` không bao giờ bị đọc, câu trả lời không thẻ, dòng nửa thẻ.
- Xong khi: CI xanh.

**T4.3 Nối vào ViewModel (tạm thời, trước khi có ReadingEngine)**
- Việc: `VoiceAgentViewModel` nhận đoạn, tạo `ReadingPlan`, đọc lần lượt từng đoạn qua hàng đợi TTS
  hiện có (mỗi câu một utterance). App phải chạy được đầu–cuối sau task này.
  Lịch sử: `addAssistantMessage` lưu **văn bản đọc** (nối các đoạn) và thêm trường tuỳ chọn
  `reading: ReadingRecord?` vào `Message` (Optional, decode an toàn). `seedHistory` dựng lại dạng v2
  (`ANSWER: <câu đầu>` …). `finishReason == MAX_TOKENS` → đoạn thông báo (N12).
- Giữ: check guard lesson 4 (`.speaking` + `isBargeInPaused = true` trước khi xếp câu, cả đường stream).
  Nếu tên hàm đổi, sửa check guard cho đúng tên mới, **không** bỏ check.
- Logic dựng `ReadingPlan` và `ReadingRecord` từ các đoạn nằm trong kiểu thuần `ReplyAssembler`
  (ViewModel chỉ gọi nó), vì `VoiceAgentViewModel` khó khởi tạo trong test (đụng kính và âm thanh).
- Xong khi: CI xanh; test mới: câu trả lời v2 nhiều bước đi qua `GeminiStub` → `AnswerFormat` →
  `ReplyAssembler` cho plan đúng thứ tự đoạn, và record đủ đoạn với `kind`, `title`, `displayText`.

**T4.4 Gỡ DISPLAY và bộ hiển thị KaTeX**
- Việc: xoá mọi thứ ở 4.8 thuộc màn hình (dùng `scripts/pbxproj_files.py remove` cho
  `SolutionView.swift`; xoá 4 dòng folder reference `SolutionRenderer` trong pbxproj bằng script hoặc
  một hàm `remove-folder` của script; xoá thư mục; sửa `project.yml`). Sửa `VoiceAgentView`,
  `ConversationListView`, onboarding cho hết tham chiếu.
- Guard: bỏ check "DISPLAY channel is rendered (offline KaTeX)"; thêm check: không còn file
  `SolutionView.swift`, thư mục `SolutionRenderer`, chuỗi `SolutionWebView`/`latestSolution` trong `OpenVision/`.
- Xong khi: CI xanh; ghi kích thước IPA trước/sau trong PR (chạy Build Unsigned IPA).

### Phase 5: bộ máy đọc (4.4)

**T5.1 TTSService: hàng đợi mẩu**
- Việc: API xếp `SpeechPiece` với rate và `postUtteranceDelay` riêng; delegate `didPause`, `didContinue`,
  `willSpeakRangeOfSpeechString` → tiến độ công khai; ngôn ngữ theo cả câu trả lời (N5). Giữ hàm cũ
  cho thông báo ngắn (`speak`).
- Xong khi: CI xanh; test `testSpokenAnswerPlaysCompletely…` vẫn pass (sửa cho định dạng v2).

**T5.2 `ReadingEngine`**
- Việc: kiểu dữ liệu, trạng thái, lệnh, chế độ, đọc chép (4.4); protocol `SpeechSynthesizing`.
- Test (`OpenVisionTests/ReadingEngineTests.swift`, bản tổng hợp giả): thứ tự utterance, rate từng mẩu
  (lời văn / công thức / hệ số trực tiếp), nghỉ giữa đoạn, pause/resume, next/previous/repeat ở biên,
  đổi tốc độ giữa chừng đọc lại mẩu hiện tại, đọc chép chờ "tiếp" và tự đi tiếp sau N giây, nối đoạn
  khi đang đọc, `stop` giữ kế hoạch.
- Xong khi: CI xanh.

**T5.3 Điều khiển bằng giọng khi đang đọc (N6–N9)**
- Việc: `ReadingCommand.parse` (thuần) + thay đổi `VoiceCommandService` và ViewModel theo 4.4.
- Test: `ReadingCommandTests` (hai ngôn ngữ, có/không wake word, câu hỏi mới không bị hiểu nhầm là lệnh,
  "ok vision stop" vẫn dừng); test trạng thái: conversation timeout không chạy khi đang đọc.
- Xong khi: CI xanh. Hardware: H14, H15, H16, H17.

**T5.4 Nút kính khi đang đọc**: **gác lại** theo D4, không làm trong đợt này.

**T5.5 Đọc lại từ Lịch sử** bằng `ReadingRecord` (không gọi Gemini). Test: plan dựng lại từ record
giống plan gốc.

### Phase 6: giao diện (4.5)

Không có Xcode để xem giao diện. Mỗi task UI: giữ view nhỏ, tách logic hiển thị ra struct thuần có
test (ví dụ `MathPrettyText`, cách gom lượt hỏi), thêm `#Preview` cho từng view mới, và ghi trong PR
"Cần chủ dự án xem giao diện trên máy (H18)".

**T6.1 Nền tảng giao diện**: token cỡ chữ/khoảng cách/bo góc trong `Theme`; thành phần dùng chung
`StatusChip`, `SegmentRow`, `PlaybackBar`, `MathPrettyText` (+ test); bỏ `ParticleEffect`, đổi nhãn tab
sang tiếng Việt (N16).

**T6.2 Màn hình Trực tiếp**: bố cục 4.5; gõ câu hỏi khi chưa có phiên (N10). Test: logic gom lượt hỏi
(lượt đang diễn ra + các lượt đã lưu) và trạng thái chip.

**T6.3 Lịch sử**: hiển thị đoạn, nút Đọc lại, Tiếp tục hội thoại. Lưu ảnh một lần cho mỗi ảnh (bản thu
nhỏ 1024 px), không lặp lại theo từng câu hỏi (N11). Đọc `conversations.json` lỗi thì **đổi tên file
cũ thành `.bak`** trước khi ghi file mới, không ghi đè mất dữ liệu (N11).

**T6.4 Cài đặt**: sắp xếp lại theo 4.5; thêm 2 màn hình "Đọc câu trả lời" và "Đọc toán tiếng Việt"
(Thử đọc, Từ điển phát âm, Nghe thử); thêm khoá ở 4.6; link repo đúng.

**T6.5 Gỡ lỗi**: màn hình Log, Lượt hỏi, Câu trả lời thô, lớp phủ trên Trực tiếp, Xuất log (4.7); sửa
lượt bị treo trong `MetricsCollector` (N15).

**T6.6 Onboarding**: chữ mới + danh sách quyền và thiết lập.

### Phase 7: ảnh và DAT (từ v1, giữ nguyên nội dung kỹ thuật)
Phụ thuộc quyết định D2 (đường kết nối). Nếu kết quả H1/H9 của chủ dự án cho thấy ảnh đang chặn việc
dùng app, có thể làm Phase 7 **trước** Phase 3–6 (ít đụng chung file, trừ `VoiceAgentViewModel`).

- **T7.1** Nâng DAT 1.0.1 → 1.1.0 (`project.yml` + pbxproj), xử lý `RegistrationError.unauthorized`
  ("Meta chưa cho phép app này đăng ký. Kiểm tra App ID, Bundle ID và Team ID trong Wearables
  Developer Center.") và `DeviceSessionError.notRegistered`. (B15)
- **T7.2** Một lần chụp dùng chung (`captureTask`), bỏ vòng poll `isTakingPhoto` trong ViewModel. (B9)
- **T7.3** Thứ tự nguồn theo cài đặt: 12 MP bật → `Camera.photo .full` trước (timeout 75 s, huỷ nếu 15 s
  không có tiến độ truyền); tắt (mặc định mới) → stream still 10 s rồi video frame. Ghi
  `lastPhotoSource` và log `Photo: <nguồn> <w>x<h> <bytes> bytes in <s> s`. Bỏ reset
  `fullPhotoFailures` mỗi lần gọi. Giữ chuỗi `.photo.capturePhoto(resolution:` (guard). (B8)
- **T7.4** Mặc định `fullResolutionPhotos = false`; nhãn trung thực ("Rất chậm qua Bluetooth, 30–60 giây"
  / "Nhanh, ~1–2 giây"); "Chụp thử" hiện nguồn ảnh.
- **T7.5** `acquireGlassesPhoto` đơn giản: đang ghi hình → stream still (10 s); còn lại →
  `captureFullResolutionPhoto`; nếu không có → quét Camera Roll **một lần**. Xoá `takeGlassesPhoto`,
  `freshLiveFrame`, `waitForFullResolutionGlassesPhoto`, `waitForRecentGlassesPhoto` nếu không còn dùng. (B9)
- **T7.6** Camera Roll chỉ đọc album có tên chứa `meta`, `ray-ban`, `stories`; bỏ luật 4032×3024 và
  ≥ 1200 px; không có album Meta thì log một lần danh sách tên album. Sửa `BlueprintPhotoLibraryE2ETests`
  (tham số `album`; thêm test ảnh ngoài album Meta **không** được nhận). (B6) Hardware: H12.
- **T7.7** Sau mỗi lần chụp: log tuyến âm thanh + `isOtherAudioPlaying`, gọi
  `configureAudioForGlasses(forceRestart: false)`. Không đổi category. Hardware: H11.
- **T7.8 Giữ kết nối kính (D2)**, cần T7.1:
  - Theo dõi `Device.addDeviceStateListener` (link, pin, bản lề, đeo/tháo, nhiệt) → chip Kính + log.
  - Kính quay lại (có trong `devicesStream`, link đã nối): tự tạo lại session với backoff 2, 4, 8 … ≤ 60 s
    (hiện chỉ có cho nút chụp).
  - Giữa các lần chụp: `DeviceSession.pause()` thay cho `endSession()`, `resume()` khi cần chụp, để lần
    chụp sau không phải mở session lại (≤ 15 s). Theo tài liệu DAT: không restart session khi đang
    `paused`, chờ `started`/`paused` trước khi gọi tiếp. Có công tắc trong Gỡ lỗi để tắt cách này nếu
    H20 cho thấy hao pin.
  - Xong khi: CI xanh; log ghi mỗi lần mất/nối lại kết nối. Hardware: H20.
- **T7.9 Camera chỉ chạy khi thật sự chụp** (đèn camera chỉ sáng lúc chụp hoặc ghi hình):
  - Rà mọi chỗ gọi `startStreaming`, `wakeCamera`, `addCamera`, `captureFullResolutionPhoto`. Gọi agent,
    bắt đầu phiên, nút chụp đang liên kết (`addInputs`) **không** được bật camera. Chỉ chụp khi người
    dùng bấm chụp, khi Gemini trả `[[CAPTURE]]`, hoặc khi ghi hình.
  - Log mỗi lần camera bật/tắt kèm lý do; màn hình Lượt hỏi hiện số lần và tổng thời gian camera bật.
  - Guard tĩnh: thân `startSession` và handler wake word không gọi `startStreaming` / `captureFullResolutionPhoto`.
  - Không tìm cách tắt hay che đèn (mục 6). Hardware: H21.

### Phase 8: nghe giọng nói (từ v1)
`T5.3` đã sửa `VoiceCommandService`; các task này phải dựa trên phiên bản sau `T5.3`.
- **T8.1** `requiresOnDeviceRecognition = true` khi `supportsOnDeviceRecognition`; log một lần mỗi locale;
  hiện trạng thái trên chip Mic. (B11) Hardware: H10.
- **T8.2** `taskHint`: `.search` khi chờ wake word, `.dictation` khi đang nghe câu hỏi. Chú ý
  `enterConversationMode()` gọi `restartRecognition()` trước khi đổi `state`. (B11)
- **T8.3** Bỏ `"a vision"`, `"have vision"`, `"heavy vision"`, `"obey vision"` khỏi `wakeWordVariations`;
  giữ các biến thể guard yêu cầu. (B12)

### Phase 9: tài liệu khớp code
- **T9.1** README: app làm gì (trả lời bằng giọng nói, đọc toán tiếng Việt, đọc chép), yêu cầu và thiết
  lập (mục 8), giới hạn (2.1, 2.2, 2.4), lệnh test. Bỏ ghi công KaTeX/marked.
- **T9.2** CONTRIBUTING: bỏ phần lỗi thời (OpenClaw, `rayl15`, `Tests/`, `AIBackend` factory,
  `NativeTool`); giữ quy ước branch/commit/PR/CI; nhắc `scripts/pbxproj_files.py`.
- **T9.3** CHANGELOG `[Unreleased]`: Added / Changed / Removed / Fixed của v2.
- **T9.4** PR template: "PLAN.md §7 (H1–H22)".
- **T9.5** PLAN.md: đánh dấu task nào xong ở commit nào (mục 3), không xoá nội dung khác.

---

## 6. Quyết định của chủ dự án và spike

Quyết định (chủ dự án đã trả lời ngày 21/11/2026):
| ID | Câu hỏi | Quyết định |
|---|---|---|
| D1 | Chế độ đọc | **Luôn đọc hết.** Gemini tự nhận loại bài: trắc nghiệm chỉ đọc "Câu n: X", tự luận đọc từng dòng có nghỉ (4.2). Không còn cài đặt chế độ đọc. |
| D2 | Kết nối kính | **Giữ Bluetooth Classic** (đã so sánh, lý do bên dưới) và làm thêm T7.8 để giữ kết nối. |
| D3 | Tên chữ cái | **Đọc tên tiếng Việt** (`vietnameseNames`: ích, i, dét…), sửa được trong từ điển. |
| D4 | Nút kính điều khiển việc đọc | Làm được (qua `MWDATInputs`) nhưng **gác lại**. |
| D5 | Màn hình | **Hiện đầy đủ** mọi câu, mọi dòng. Giọng đọc **không bao giờ** bảo xem màn hình. |
| D6 | Model | **Giữ Flash-Lite** (chủ yếu toán phổ thông, trắc nghiệm). Trắc nghiệm giữ đơn giản; tự luận đi qua module đọc riêng với tốc độ riêng. |

Lý do giữ Bluetooth Classic (D2). Đường BLE + Wi-Fi là mặc định Meta khuyến nghị cho app phát hành
trên App Store, nhưng với app này (cài tay, chụp ảnh rời theo yêu cầu, cần Internet cho Gemini) thì kém hơn:
- Mỗi lần bật camera, iOS hiện hộp thoại "muốn kết nối Wi-Fi của kính" và iPhone rời mạng Wi-Fi đang
  dùng (mất Internet trong lúc đó) ([DAT #363](https://github.com/meta/meta-wearables-dat-ios/issues/363), [#376](https://github.com/meta/meta-wearables-dat-ios/issues/376)). Hỏng hẳn trải nghiệm rảnh tay.
- Có lỗi Wi-Fi đang mở: không vào được Wi-Fi của kính ([#354](https://github.com/meta/meta-wearables-dat-ios/issues/354)), session mới kẹt ở `.starting` ([#382](https://github.com/meta/meta-wearables-dat-ios/issues/382)).
- Ảnh 12 MP qua Wi-Fi còn chậm hơn (165 s so với 49 s); ảnh nhanh từ stream chỉ hơn 0,3 s.
Bluetooth Classic không có hộp thoại, iPhone giữ Internet. Lý do App Store (MFi PPID) không áp dụng
vì app không lên App Store. Xem lại nếu Meta sửa các lỗi trên hoặc app cần phát hành.

Đèn trắng nhấp nháy khi gọi agent. Đèn trắng phía trước kính là **đèn báo camera đang hoạt động**
cho người xung quanh. Firmware của kính bật nó bất cứ khi nào camera chạy, Meta xác nhận đây là hành
vi cố ý ([DAT #318](https://github.com/meta/meta-wearables-dat-ios/issues/318)), và kính từ chối quay
chụp nếu đèn bị che. **Plan không tìm cách tắt hay che đèn này.** Việc hợp lệ là bảo đảm camera chỉ
chạy khi thật sự chụp ảnh (đèn chỉ sáng lúc chụp), xem T7.9.

Spike (chỉ làm khi chủ dự án yêu cầu; kết quả là ghi chú trong PR hoặc mục mới ở đây):
| ID | Nội dung |
|---|---|
| S1 | `VoiceInvocation` (DAT, experimental): "Hey Meta, mở OpenVision" |
| S2 | `MWDATSpeech`: nhận dạng trên kính thay `SFSpeechRecognizer` + HFP |
| S3 | `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) cho vi-VN |
| S4 | (Không cần theo D6) So `gemini-3.5-flash-lite` với `gemini-3.5-flash` nếu sau này thấy giải sai nhiều |
| S5 | `MWDAT.TeamID` rỗng khi build CI + Sideloadly ký lại: có làm đăng ký thất bại không? |
| S6 | Port giao thức Visor lên iOS qua BLE L2CAP (rất lớn, rủi ro điều khoản) |
| S7 | Nghe thử giọng tiếng Việt bằng màn hình Thử đọc: chữ cái đứng riêng, số, thập phân, chữ Hy Lạp, "lốc", "cốt", "sin"; ghi lại chỗ sai để chỉnh từ điển mặc định |
| S8 | SSML (`ssmlRepresentation`) cho nghỉ và nhấn giọng: có ổn với giọng vi-VN không? |
| S9 | Đọc lời giải dài qua A2DP (rõ hơn HFP) mà không vi phạm lesson 2: có cách nào không? |

---

## 7. Kiểm thử trên phần cứng (chủ dự án chạy)

Chuẩn bị: iPhone 15 Pro (iOS 18+), kính đã ghép đôi và bật Developer Mode, app cài bằng Sideloadly,
quyền Ảnh = Toàn bộ ảnh. Log xem trong Cài đặt → Gỡ lỗi → Log (sau T6.5), hoặc Console.app trên Mac.

| # | Bước | Đạt khi |
|---|---|---|
| H1 | Nhìn đề toán, bấm chụp trên gọng, nói "Ok Vision, giải câu này" | Kính đọc đáp án; log có `Photo: <nguồn> <w>x<h>` và `Attached image payload` |
| H2 | Chụp một trang 10 câu trắc nghiệm, hỏi "giải hết" | Đọc "Câu 1: …" đến "Câu 10: …", không giải thích, không đọc "đô la", "gạch chéo", tên lệnh LaTeX |
| H3 | Quan sát thanh âm lượng và loa kính | Không nhảy, không tiếng click |
| H4 | Trong 120 s hỏi "Tại sao lại ra kết quả đó?" | Trả lời đúng ngữ cảnh; log `not re-uploading` |
| H5 | Ghi hình POV khi đang hội thoại | App không đơ |
| H6 | Không có ảnh, hỏi "giải câu này"; rồi hỏi "Thủ đô của Pháp là gì?" | Câu 1: app tự chụp (`Model asked to see`) hoặc nói không có ảnh. Câu 2: "Paris", không gắn ảnh |
| H7 | Hỏi bằng tiếng Anh sau khi chụp | Trả lời và đọc bằng tiếng Anh, công thức đọc bằng tiếng Anh |
| H8 | Mạng yếu (Network Link Conditioner 3G) | Có câu trả lời, hoặc kính nói "Mạng đang chậm…" trong ≤ 2 phút |
| H9 | Cài đặt → Kính → Chụp thử, 3 lần mỗi chế độ | Ghi kích thước, thời gian, nguồn |
| H10 | Khoá màn hình, iPhone trong túi, nói "Ok Vision…" và bấm chụp | Ghi lại cái gì chạy, cái gì không |
| H11 | Ngay sau một lần chụp, nghe câu trả lời; thử cả khi đang phát nhạc | Kính vẫn phát tiếng |
| H12 | Chụp 1 ảnh bằng camera iPhone, rồi hỏi câu không liên quan | Ảnh iPhone không được gửi |
| H13 | Cài đặt → Đọc toán → Thử đọc 15 mẫu dưới đây, nghe qua kính | Đúng câu mong đợi, nghe rõ; ghi lại chỗ sai |
| H14 | Bài tự luận dài (≥ 8 dòng) | Đọc "Dòng 1…" đến "Đáp số", nghỉ giữa các dòng, tốc độ tự luận; không bị cắt sau 30 s; mic vẫn nghe được lệnh sau 1 phút |
| H15 | Khi đang đọc: "Ok Vision tạm dừng", "tiếp tục", "đọc lại", "dòng tiếp", "dòng trước", "đọc lại câu 3", "chậm lại", "nhanh lên", "dừng lại" | Mỗi lệnh có tác dụng trong ≤ 1,5 s; tiếng đọc của app không tự kích hoạt lệnh |
| H16 | Bật Đọc chép, giải một bài tự luận 4 dòng | Dừng sau mỗi dòng; nói "tiếp" (không cần wake word) thì đọc dòng sau |
| H17 | Khi đang đọc: "Ok Vision, còn câu 2 thì sao?" | Dừng đọc, câu hỏi mới được gửi nguyên văn, không phải hỏi lại |
| H18 | Xem màn hình Trực tiếp và Lịch sử khi đang đọc | Đoạn đang đọc được tô sáng; chạm đoạn để đọc từ đó; Lịch sử "Đọc lại" chạy không cần mạng |
| H19 | Cài đặt → Gỡ lỗi | Log có các danh mục gemini/glasses/voice/tts/reading; Xuất log ra file .txt |
| H20 | Gập kính 30 s rồi mở; đi xa 10 m rồi quay lại; chụp 2 lần liên tiếp | Tự nối lại không cần thao tác; ghi thời gian nối lại và thời gian lần chụp thứ 2 |
| H21 | Nói "Ok Vision" + câu hỏi không cần ảnh; rồi bấm chụp | Câu 1: đèn camera không sáng. Câu 2: đèn chỉ sáng lúc chụp. Nếu có đèn khác nhấp nháy, ghi lại thời điểm và đính kèm log |
| H22 | Đề hỗn hợp (trắc nghiệm + 1 bài tự luận) | Đọc khối "Câu …" trước (tốc độ trắc nghiệm), rồi bài tự luận (tốc độ tự luận) |

15 mẫu cho H13 (cũng là mẫu có sẵn trong màn hình Thử đọc và ca test ở T3.2):
| # | Công thức | Câu đọc mong đợi (tự nhiên) |
|---|---|---|
| 1 | `$x^2 - 5x + 6 = 0$` | x bình phương trừ 5 x cộng 6 bằng 0 |
| 2 | `$\frac{3}{4}$` | ba phần tư |
| 3 | `$\sqrt{x^2+1}$` | căn của x bình phương cộng 1 |
| 4 | `$\int_0^1 x e^x\,dx$` | tích phân từ 0 đến 1 của x e mũ x, đê x |
| 5 | `$\lim_{x \to 0} \frac{\sin x}{x} = 1$` | giới hạn khi x tiến tới 0 của sin x trên x bằng 1 |
| 6 | `$\log_2 8 = 3$` | lô-ga-rít cơ số 2 của 8 bằng 3 |
| 7 | `$f'(x) = 3x^2 - 3$` | f phẩy x bằng 3 x bình phương trừ 3 |
| 8 | `$\overrightarrow{AB} \perp \overrightarrow{CD}$` | véc-tơ A B vuông góc với véc-tơ C D |
| 9 | `$x \in [1; 3]$` | x thuộc đoạn từ 1 đến 3 |
| 10 | `$\Delta = b^2 - 4ac$` | đen-ta bằng b bình phương trừ 4 a c |
| 11 | `2,5 cm` (trong câu tiếng Việt) | 2 phẩy 5 xen-ti-mét |
| 12 | `$(x+1)^2$` | x cộng 1, tất cả bình phương |
| 13 | `$\begin{cases} x+y=3 \\ x-y=1 \end{cases}$` | hệ phương trình: x cộng y bằng 3; x trừ y bằng 1 |
| 14 | `$C_5^2 = 10$` | tổ hợp chập 2 của 5 bằng 10 |
| 15 | `$-3 < x \le 2$` | âm 3 nhỏ hơn x nhỏ hơn hoặc bằng 2 |

Mẫu báo cáo phần cứng:
```
Ngày / build: ____  iOS: ____  Firmware kính: ____  Meta AI: ____  Mạng: ____
H1 ☐ H2 ☐ H3 ☐ H4 ☐ H5 ☐ H6 ☐ H7 ☐ H8 ☐ H9 ☐ H10 ☐ H11 ☐ H12 ☐
H13 ☐ (mẫu sai: ___) H14 ☐ H15 ☐ H16 ☐ H17 ☐ H18 ☐ H19 ☐ H20 ☐ H21 ☐ H22 ☐
H9 nhanh: ___×___ ___ s | 12 MP: ___×___ ___ s
Thời gian từ lúc nói xong tới tiếng đầu tiên (H1): ____ s
Ghi chú / log lỗi (đính kèm file Xuất log):
```

---

## 8. Thiết lập tài khoản và thiết bị

1. `cp Config.xcconfig.example Config.xcconfig` và
   `cp OpenVision/Config/Config.swift.example OpenVision/Config/Config.swift` (cả hai bị gitignore).
   Điền `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER`, `META_APP_ID`, `CLIENT_TOKEN`
   (dạng đầy đủ `AR|<app id>|<hash>`), `APP_LINK_URL_SCHEME`. Ở Developer Mode, `META_APP_ID` có thể là `0`.
2. [Wearables Developer Center](https://wearables.developer.meta.com/): tạo app, điền Apple Team ID,
   bật quyền Camera. Sau khi đổi cấu hình: trong app bấm Huỷ đăng ký rồi Đăng ký lại.
3. Meta AI app: bật Developer Mode (Cài đặt → Thiết bị → Kính → Developer Mode, hoặc
   Cài đặt → Giới thiệu → chạm số phiên bản 5 lần, tuỳ phiên bản).
4. Trong app: Cài đặt → Kính → "Cài/cập nhật thành phần trên kính"
   (`Wearables.shared.openDATGlassesAppUpdate()`). Cần firmware kính V126+, Meta AI V282+, iOS 17.2+.
5. Cài đặt → Gemini: dán API key (nhiều key cách nhau bằng dấu phẩy, nên từ các project khác nhau).
   Key lưu trong Keychain, không bao giờ nằm trong code.
6. Cài đặt iOS → Trợ năng → Nội dung được đọc → Giọng nói: tải giọng tiếng Việt Enhanced/Premium.
7. Cài IPA: chạy workflow **Build Unsigned IPA**, tải artifact `OpenVision-unsigned`, ký và cài bằng
   Sideloadly, tin cậy nhà phát triển trong Cài đặt → Cài đặt chung → Quản lý VPN & Thiết bị.
   Với Apple ID miễn phí, app hết hạn sau 7 ngày.

---

## 9. Cách xem CI từ sandbox Linux

`gh run list` **không chạy** trong sandbox (GH_HOST không khớp remote). Dùng `gh api`:
```bash
REPO=darwnlinz1/Visor-iOS-Solver
BR=feature/voice-v2

# Mở PR (một lần). Không dùng `gh pr create`.
gh api repos/$REPO/pulls -f title="Voice-only answers per PLAN.md v2" -f head="$BR" -f base="main" \
  -f body="Thực hiện PLAN.md v2. Xem từng commit (Task: Tx.y)."

# Các lần chạy của branch, rồi job và log job lỗi
gh api "repos/$REPO/actions/runs?branch=$BR&per_page=10" \
  --jq '.workflow_runs[] | "\(.id) \(.name) \(.status)/\(.conclusion) \(.head_sha[0:7])"'
gh api repos/$REPO/actions/runs/<RUN_ID>/jobs --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'
gh api repos/$REPO/actions/jobs/<JOB_ID>/logs > /projects/sandbox/ci.log
grep -n -E "##\[error\]|Executed [0-9]+ tests|error:" /projects/sandbox/ci.log | head -80
```
- Lưu log ra `/projects/sandbox/` (thư mục `/tmp` không giữ file giữa các lệnh). Xoá file tạm khi xong.
- CI mất 10–40 phút; chờ bằng vòng `sleep 45` kiểm tra trạng thái, tối đa 90 phút cho một lần chạy.
- Workflow có `cancel-in-progress`: push mới sẽ **huỷ** run đang chạy. Muốn biết kết quả một commit
  thì chờ run của nó xong rồi mới push tiếp (có thể commit nhiều task ở local trong lúc chờ).
- Khi app test host chết lúc khởi động, xem nhóm log "App launch console" và "OpenVision crash
  reports" do `run-simulator-tests.sh` in ra.
- Không chạy song song hai lệnh sửa cùng một file.

---

## 10. Mẫu báo cáo cuối của agent

```
PR: <link>
Task đã xong: T2.1 (sha) ✅ CI xanh | T2.2 (sha) ✅ | …
Task chưa xong / bị chặn: Tx.y: lý do, đã thử gì
Test fail còn lại: <tên test>: có từ trước? nguyên nhân?
Cần chủ dự án chạy trên kính / xem giao diện: H…
Quyết định đã dùng giá trị mặc định tạm: D…
Phát hiện mới (không có trong PLAN): …
```

## 11. Chia việc: đợt song song và đợt tuần tự

**Đợt 1 (3 agent song song).** Mỗi agent một thư mục `git worktree`, một branch, một PR vào
`feature/voice-v2` (không vào `main`). Ba nhóm **không sửa chung file nào**:
| Agent | Branch | Task | Chỉ được sửa / tạo |
|---|---|---|---|
| A (hạ tầng) | `feature/voice-v2-infra` | T2.1, T2.2, T2.3, T2.5 | `scripts/pbxproj_files.py` (mới), `scripts/blueprint/verify_blueprint.py`, `scripts/e2e/run-simulator-tests.sh`, `OpenVisionTests/BlueprintPhotoLibraryE2ETests.swift`, `OpenVision/App/OpenVisionApp.swift`, `OpenVision/Managers/GlassesManager.swift`, `OpenVision/Views/Settings/GlassesSettingsView.swift` |
| B (đọc toán) | `feature/voice-v2-math` | T3.1, T3.2, T3.4 và phần thuần của T3.3 (chuẩn hoá lời văn, số, đơn vị, `EnglishMathReader`; **không** sửa `TTSService`) | File **mới** trong `OpenVision/Services/Speech/` (splitter, lexer, parser, node, reader, từ điển, `VietMathSpeech`) và `OpenVisionTests/VietMath*Tests.swift` |
| C (định dạng) | `feature/voice-v2-format` | T4.2 (chỉ phần thuần), `ReadingModel`, `ReplyAssembler` (gồm câu đọc của từng mục: "Câu 3: a đúng, b sai.", "Dòng 1. …"), văn bản prompt v2.1 | File **mới**: `OpenVision/Services/Speech/AnswerFormat.swift`, `ReadingModel.swift`, `ReplyAssembler.swift`, `PromptV2.swift` (hàm trả về chuỗi prompt, **chưa nối** vào `GeminiLiveService`), `OpenVisionTests/AnswerFormatTests.swift`, `ReplyAssemblerTests.swift`, `PromptV2Tests.swift` |

Quy tắc Đợt 1:
- B và C **không** sửa `project.pbxproj`, `run-simulator-tests.sh`, `PLAN.md` hay bất kỳ file có sẵn nào;
  chỉ tạo file mới trong danh sách của mình. File mới được đăng ký vào pbxproj ở bước tích hợp (bằng
  script của A).
- Vì file chưa đăng ký, trên branch B và C check `project` của guard **sẽ báo lỗi cho đúng các file
  mới đó**. Đó là lỗi duy nhất được phép; mọi check khác phải xanh.
- B và C **chỉ push branch, không mở PR** (CI của họ chưa có ý nghĩa). Họ kiểm chứng bằng
  `scripts/swift-local/run.sh`: phải biên dịch sạch (không warning mới) và mọi test pass.
- A mở PR vào `feature/voice-v2` và chờ CI như mục 9.
- Code thuần phải biên dịch được cả trên Linux lẫn iOS: chỉ `import Foundation`; không dùng
  `as NSString` (Linux không tự chuyển `String` sang `NSString`), dùng `NSRange(s.startIndex..., in: s)`
  và `Range(nsRange, in: s)`; không dùng API chỉ có trên Apple.
- Kiểu dùng chung giữa B và C: C định nghĩa `ReadingModel.swift`; B định nghĩa `SpeechPiece` trong
  `VietMathSpeech.swift`. Không ai định nghĩa trùng tên kiểu của người kia.

**Review.** Một agent review đọc diff của 3 PR theo `PLAN.md`, ghi lỗi theo mức độ. Agent làm việc sửa
theo review trên đúng branch của mình rồi chạy lại test.

**Tích hợp (tuần tự).** Gộp 3 branch vào `feature/voice-v2`; đăng ký file mới bằng
`scripts/pbxproj_files.py`; thêm các suite test mới vào `run-simulator-tests.sh`; CI phải xanh.

**Các đợt sau (tuần tự, mỗi đợt một phiên):**
| Đợt | Phạm vi |
|---|---|
| 2 | T2.4 (`AppLog`), T3.3 (nối module đọc toán vào `TTSService`), T4.1 (nối prompt v2.1), T4.3, T4.4 |
| 3 | Phase 5 (T5.1, T5.2, T5.3, T5.5) |
| 4 | Phase 6 (giao diện) |
| 5 | Phase 7–8 (ảnh, DAT 1.1.0, giữ kết nối, camera/đèn, nghe) |
| 6 | Phase 9 (tài liệu) |
