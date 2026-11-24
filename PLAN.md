# PLAN.md v2.2: OpenVision iOS, trả lời hoàn toàn bằng giọng nói (dành cho coding agent)

> Cập nhật: 21/11/2026, bản v2, thay thế v1. Thay đổi so với v1:
> - **Bỏ kênh DISPLAY** (lời giải LaTeX hiện trên iPhone). Mọi câu trả lời được **đọc qua loa kính**.
> - Thêm: module đọc toán tiếng Việt, bộ máy đọc lời giải nhiều bước có chỉnh tốc độ, màn hình
>   "Trực tiếp" (hội thoại đang diễn ra), Cài đặt mới, công cụ gỡ lỗi, thiết kế lại giao diện.
> - Phase 0–1 của v1 đã xong (PR #2). Việc còn lại của v1 (DAT 1.1.0, đường ảnh, nhận dạng giọng)
>   được giữ và đánh số lại (Phase 7–8).
> - **v2.1 (21/11/2026):** chủ dự án đã trả lời D1–D6 (mục 6). App chỉ dùng cho bài tập và thi:
>   trắc nghiệm đọc "Câu 1: A. Câu 2: B."; tự luận đọc từng dòng "Dòng 1: …" có nghỉ, tốc độ riêng.
>   Luôn đọc hết; màn hình hiện đầy đủ; không bao giờ bảo "xem màn hình điện thoại".
> - **v2.2 (22/11/2026):** Đợt 1 xong (3 agent song song, 1 review, 1 vòng sửa) và đã tích hợp vào
>   `feature/voice-v2` (PR #4 vào `main`; CI + E2E xanh ở `8402cec`: 218 test, 0 lỗi). Module đọc toán và
>   parser v2.1 đã được biên dịch vào app nhưng **chưa được gọi**; đợt 2 nối chúng vào. Mới trong bản này:
>   trạng thái từng task (§3.1, §5), quy tắc branch theo đợt (§0.2), luật đọc thêm sau review (§4.3),
>   thứ tự an toàn cho đợt 2 (§11), hướng dẫn test (§12), prompt mẫu cho agent (§13).
>   Agent mới bắt đầu từ `AGENTS.md`.
> Nếu comment trong code mâu thuẫn với file này, tin file này. Nếu file này mô tả hiện trạng khác
> với code, tin code và ghi chú lại trong PR.

---

## 0. Quy tắc làm việc cho agent (đọc trước khi làm bất cứ gì)

1. **Thứ tự:** làm theo đợt ở §11; trong đợt làm theo thứ tự ghi ở đó (thường là số task; đợt 2 có
   ngoại lệ có chủ đích). Mỗi task là **một commit**.
2. **Branch và PR:** `feature/voice-v2` là branch tích hợp của v2, và PR #4
   (`feature/voice-v2` → `main`) là PR duy nhất vào `main`. Mỗi đợt làm trên branch riêng tạo từ
   `feature/voice-v2` mới nhất (ví dụ `feature/voice-v2-wave2`; đợt song song thì mỗi agent một branch)
   và mở PR vào `feature/voice-v2`. Khi PR của đợt xanh và đã review, merge nó; PR #4 tự cập nhật.
   Trước khi bắt đầu, xem trạng thái PR: `gh api "repos/darwnlinz1/Visor-iOS-Solver/pulls?state=all&per_page=10"`.
   Nếu PR #4 đã merge hoặc đã đóng, mở PR mới `feature/voice-v2` → `main` khi đợt xong.
   Không commit thẳng `main`, không force push, không viết lại lịch sử đã push.
3. **Commit message:** `Fix: …`, `Add: …`, `Refactor: …`, `Docs: …`, `Chore: …`, `Test: …`
   (dòng đầu ≤ 72 ký tự), dòng sau ghi `Task: Tx.y`.
4. **Môi trường:** sandbox Linux, **không có Xcode**. Chạy được ở local:
   `python3 scripts/blueprint/verify_blueprint.py` (luôn 0 failed), các script Python, và
   `scripts/swift-local/run.sh` (Swift 6.3 có sẵn trong sandbox: biên dịch và chạy test cho code thuần
   trong `OpenVision/Services/Speech/`, xem §12).
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

### 3.1 Đã xong

**Phase 0–1 của v1** (PR #2, CI + E2E xanh ở `dd04593`): E2E chạy được lần đầu (ký ad-hoc simulator);
tham chiếu tài liệu cũ đã sửa; Info.plist `arm64`, bỏ `NSAllowsArbitraryLoads`; không in config; TTL ảnh
120 s / 5 lần; không gửi lại ảnh đã có trong lịch sử; upload 3072 px q0.85; bỏ danh sách từ khoá, chỉ
dùng `[[CAPTURE]]`.

**Đợt 1 của v2** (22/11/2026). Agent A mở PR #3, đã merge vào `feature/voice-v2`. Branch B và C chỉ
push, được merge ở bước tích hợp. PR #4 (`feature/voice-v2` → `main`) có CI + E2E xanh ở `8402cec`.
App **chưa đổi hành vi**: mọi file mới đã được biên dịch và test, nhưng chưa có code nào gọi chúng.
| Task | Commit | Kết quả |
|---|---|---|
| T2.1 | `ca6736d` | `scripts/pbxproj_files.py` (`add`, `remove`, `remove-folder-ref`, `--dry-run`, `--self-test`); guard kiểm cả chiều ngược (file trong pbxproj phải tồn tại) |
| T2.2 | `8d29c96`, `0da02df`, `7045d52` | E2E chạy **mọi** suite, cả trên PR. `blueprint_only` (workflow_dispatch) và `make e2e-blueprint` để chạy riêng Blueprint |
| T2.3 | `324b3a6`, `dd13d9e` | 3 test Ảnh chạy thật (script ghi lại dòng TCC thành `auth_version 2`); trên CI, một test Ảnh bị skip làm job đỏ |
| T2.5 | `89af8da` | `WearablesBootstrap` ghi lỗi `configure()`; `GlassesManager` lấy SDK lười qua `requireSDK`; biến Debug `OPENVISION_SIMULATE_DAT_CONFIG_FAILURE=1`; `launch_smoke` chạy thêm một lần không có SDK |
| T3.1 | `613e5a1`, sửa sau review `8834e22`, `f89ffd8`, `3fef42b`, `d349c8e`, `a1786ff` | splitter, lexer, parser, `MathNode` |
| T3.2 | `6699e99`, sửa `0dc9acb`, `baee22a` | `VietnameseMathReader`, `PronunciationDictionary`, `MathReadingStyle`; đủ bảng 4.3 và 15 mẫu H13 |
| T3.3 (phần thuần) | `f087dab`, `89907f8`, `0c38800`, `a7f97b4` | số, đơn vị, ký hiệu trong lời văn; `EnglishMathReader`. **Còn:** nối vào `TTSService` (đợt 2) |
| T3.4 | `f1bd04f` | fuzz 1000 chuỗi seed cố định, 0,3 s |
| T4.1 (chỉ văn bản) | `be7c365` | `PromptV2.systemPrompt(now:timeZone:userPrompt:memories:)`. **Còn:** thay `buildSystemPrompt()` (đợt 2) |
| T4.2 (phần thuần) | `09bbc97`, `06e1a59`, `06f6bb7` | `AnswerFormat`. **Còn:** nối vào `GeminiLiveService` (đợt 2) |
| T4.3 (phần thuần) | `07f80d3`, `7695a01`, `06e1a59` | `ReadingModel`, `ReplyAssembler`. **Còn:** nối vào ViewModel, Lịch sử (đợt 2) |
| Tích hợp | `3f3c954`, `8402cec` | đăng ký 20 file bằng script; `ReplyAssemblerSpeechTests` đọc cả câu trả lời qua 3 module |

Ghi chú: `07f80d3` và `7695a01` ghi `Task: T4.2` nhưng thuộc T4.3 (phần thuần).

Review đợt 1 (kết luận ban đầu: cần sửa) tìm ra 2 lỗi chặn, **đều đã sửa**:
- X1: đáp án ngắn không phải số trơn bị đọc như phép chia ("Câu 12: 3/4" → "Câu … 12 chia 3, trên 4").
- B1: `\Delta'` bị đọc "Delta".

Các lỗi nhỏ hơn cũng đã sửa: B2–B8 (luật đọc, xem bảng bổ sung ở 4.3), C1 (loại bài sai khi stream),
C2 ("1." bị tách thành một đoạn), A1 (CI không bắt được test Ảnh skip), I1 (PR chỉ chạy suite Blueprint),
I4 (Makefile). Số test: local 143 (`scripts/swift-local/run.sh`), E2E 218 (3 test Gemini thật skip có chủ ý).

Đã kiểm tra trong review, không cần kiểm lại trừ khi sửa đúng chỗ đó:
- Đủ 40 dòng bảng 4.3 và 15 mẫu H13, so chuỗi chính xác, cả hai `letterStyle`.
- Ràng buộc đầu ra (không `\ $ { } ^ _`, mỗi mẩu ≤ 200 ký tự, không crash), tính chất tiền tố khi stream,
  ID đoạn ổn định, câu thông báo MAX_TOKENS.
- Prompt đúng hợp đồng 4.2.
- `WearablesBootstrap` chỉ gọi `configure()` một lần, mọi lối vào SDK đều trả về sớm khi lỗi, biến môi
  trường chỉ có trong Debug, bất biến âm thanh không bị đụng.
- Không trùng tên kiểu với phần còn lại của app (build iOS xanh xác nhận).

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
| N1 | 3 test `BlueprintPhotoLibraryE2ETests` luôn bị skip trên CI (quyền Ảnh chưa `.authorized` lúc chạy test). | `scripts/e2e/run-simulator-tests.sh` | T2.3 ✅ `324b3a6` |
| N2 | `GlassesManager.init` dùng `Wearables.shared` vô điều kiện; nếu `Wearables.configure()` lỗi thì app crash lúc khởi động (đã thấy trên CI). | `GlassesManager.swift` (`private let wearables`) | T2.5 ✅ `89af8da` |
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
| N13 | `SettingsSecretsTests`, `TextChunkingTests` không bao giờ chạy trên CI (script chỉ chạy các suite Blueprint*). | `run-simulator-tests.sh` | T2.2 ✅ `8d29c96`, `0da02df` |
| N14 | 147 lệnh `print(` không vào OSLog; 60 `NSLog` (đếm lại 22/11, regex `\bprint\(`); không có logger chung → không làm được màn hình log. | toàn bộ `OpenVision/` | T2.4 |
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
| `OpenVision/Services/Speech/` (đợt 1) | **Chỉ Foundation** (biên dịch cả trên Linux bằng `scripts/swift-local/run.sh`). Không đặt `ObservableObject`, Combine, SwiftUI, AVFoundation ở đây. Các file ở bảng dưới |
| **Mới (T2.4)** `OpenVision/Utilities/Helpers/AppLog.swift` | Logger chung + bộ đệm cho màn hình Log (thư mục `Helpers/` đã có) |
| `scripts/pbxproj_files.py` | Đăng ký / gỡ file Swift và folder reference trong pbxproj (`--help`, `--dry-run`, `--self-test`) |
| `scripts/swift-local/run.sh` | Build + test code thuần trong `Services/Speech/` bằng SwiftPM trên Linux |

Các file trong `OpenVision/Services/Speech/` (đợt 1) và API chính:
| File | Việc | API chính |
|---|---|---|
| `VietMathSpeech.swift` | Điểm vào của bộ đọc toán; `SpeechPiece` | `render(_:vietnamese:style:) -> [SpeechPiece]`, `renderWithDiagnostics(...)` → `Rendering { pieces, warnings }`, `spokenText(_:)` |
| `MathSpanSplitter.swift` | Tách lời văn / công thức: `$…$`, `\(…\)`, `\[…\]`, `$$…$$`, công thức trần (Unicode, ASCII); nhận nhãn "Câu 12:", "Dòng 3.", "b)" | dùng nội bộ |
| `MathLexer.swift` | Token LaTeX, bảng ký tự Unicode → lệnh, tên chữ Hy Lạp | `greekLetterNames` |
| `MathParser.swift` | Đệ quy xuống → `MathNode`, **không bao giờ throw**; dấu `:` đặt tên và sau lượng từ; toạ độ véc-tơ; đơn vị | dùng nội bộ |
| `MathNode.swift` | Cây biểu thức | `topRelation`, `startsWithWordsOrNothing` |
| `VietnameseMathReader.swift` | `MathNode` → lời tiếng Việt; `ProseNormalizer` cho số, đơn vị, số mục ("Bài 2.15") trong lời văn | dùng nội bộ |
| `EnglishMathReader.swift` | Bản tiếng Anh (thay `SpokenMath`) | dùng nội bộ |
| `PronunciationDictionary.swift` | Hàm, chữ Hy Lạp, đơn vị, tên chữ cái + ghi đè của người dùng (theo token nguyên) | |
| `MathReadingStyle.swift` | Kiểu đọc (4.3) | `MathReadingStyle.default`; `init(mathVerbosity:symbolicFractionWord:negativeWord:letterStyle:pronunciationOverrides:)` nhận chuỗi từ Cài đặt, giá trị lạ → mặc định (N18) |
| `AnswerFormat.swift` | Parser định dạng v2.1 (4.2) | `parse(_:finishReason:) -> ParsedAnswer`, `partialAnswer(in:) -> ParsedAnswer` (stream), `completedSections(in:)`, `truncationNotice(after:languageCode:)`, `captureToken`, `endToken`, `maxTokensFinishReason` |
| `ReadingModel.swift` | `AnswerType`, `ReadingSegment`, `ReadingPlan`, `ReadingRecord` (Codable, giá trị lạ decode thành `.other` / `.answer`) | `ReadingPlan(record:turnID:)`, `plan.record` |
| `ReplyAssembler.swift` | Đoạn → chữ hiển thị + câu đọc (bảng 4.2), cả tiếng Việt và tiếng Anh | `init(languageCode:readLineNumbers:)`, `emptyPlan(turnID:)`, `update(_:streamed:)`, `finish(_:with:)`, `plan(turnID:parsed:)`, `record(for:)` |
| `PromptV2.swift` | Văn bản system prompt v2.1 (chưa nối) | `systemPrompt(now:timeZone:userPrompt:memories:)`, `noScreenRule` |
| `scripts/blueprint/verify_blueprint.py`, `verify_ipa_symbols.sh` | Guard tĩnh, kiểm tra ký hiệu trong IPA |
| `scripts/e2e/run-simulator-tests.sh`, `.github/workflows/*` | Test simulator, CI, build IPA |

---

## 4. Thiết kế mới

### 4.1 Luồng từ câu hỏi tới giọng đọc
```
Câu hỏi + ảnh → Gemini (định dạng v2.1: TYPE + Q / P / L / FINAL / ANSWER, toán trong $…$)
  → AnswerFormat.partialAnswer(in:) / parse(_:)     tách đoạn theo thẻ khi stream tới, rồi khi xong
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
- Loại bài **chốt một lần** (đợt 1, C1): dòng `TYPE:` hoàn chỉnh đầu tiên có giá trị hợp lệ; nếu không có
  thì thẻ hoàn chỉnh đầu tiên quyết định. Sau đó loại không đổi nữa (dòng `TYPE:` thứ hai bị bỏ qua).
  Khi stream dùng `AnswerFormat.partialAnswer(in: accumulated)`: `sections` giống `completedSections`,
  `type` đúng ngay khi biết, `isTypeKnown` cho biết đã biết chưa (trước đó `type == .other`).
- Số thứ tự danh sách ("1.", "2.", "a.") không tự thành một câu: "1. Mở app. 2. Chụp ảnh." → hai câu (C2).
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
| `VietnameseMathReader` | `MathNode` → mảng `SpeechPiece`, theo `MathReadingStyle`. `enum SpeechPiece: Equatable, Codable { case words(String, isMath: Bool); case pause(milliseconds: Int) }` định nghĩa trong `VietMathSpeech.swift`. |
| `EnglishMathReader` | Bộ đọc tối giản cho câu trả lời tiếng Anh (chuyển các từ tiếng Anh của `SpokenMath` sang đây). |
| `PronunciationDictionary` | Bảng mặc định (hàm, chữ Hy Lạp, đơn vị, tên chữ cái) + ghi đè của người dùng (Cài đặt). Áp dụng theo **token nguyên**, không theo chuỗi con. |
| `VietMathSpeech.render(_ text: String, vietnamese: Bool, style: MathReadingStyle) -> [SpeechPiece]` | Điểm vào duy nhất. Lời văn giữ nguyên (chỉ chuẩn hoá số, đơn vị, ký hiệu). `vietnamese == false` dùng `EnglishMathReader`. |

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

Luật thêm sau review đợt 1 (đã có test so chuỗi chính xác; viết theo kiểu bảng trên, mặc định
`vietnameseNames` thì chữ cái đứng riêng đọc bằng tên, ví dụ "đê: ích cộng 2 i trừ 3 bằng 0"):
| Viết | Đọc | Mã review |
|---|---|---|
| `Câu 12: 3/4.`, `Bước 1: x = 2.`, `Dòng 100. x = 2.`, `b) x = 2.` | Câu 12: ba phần tư; Bước 1: x bằng 2; Dòng 100. x bằng 2; b) x bằng 2 (nhãn kết thúc bằng `:`, `.` hoặc `)` không bao giờ thành một phần của công thức) | X1 |
| `Lúc 10:30 sáng.`, `Tỉ số 3:2.`, `Câu 4: -2,5.` | giữ nguyên; giữ nguyên; Câu 4: âm 2 phẩy 5 | X1 |
| `\Delta'`, `Δ' > 0`, `\alpha' = 30^\circ` | đen-ta phẩy; đen-ta phẩy lớn hơn 0; an-pha phẩy bằng 30 độ (tiếng Anh: delta prime) | B1 |
| `d: x + 2y - 3 = 0`, `(P): 2x - y + z = 0`, `\Delta: x - y + 1 = 0` | d: x cộng 2 y trừ 3 bằng 0 (dấu `:` sau tên đường, mặt, đầu công thức, và vế sau có quan hệ, là khoảng nghỉ) | B2 |
| `\exists x \in \mathbb{R}: x^2 < 0`, `\forall x \in \mathbb{R}: x^2 \ge 0` | tồn tại x thuộc tập số thực sao cho …; với mọi x thuộc tập số thực, … | B2 |
| `a : b = 2 : 3`, `x : 3 = 4` | a chia b bằng 2 chia 3; x chia 3 bằng 4 (các trường hợp khác vẫn là phép chia) | B2 |
| `\vec{u} = (1; 2)`, `\overrightarrow{AB} = (3; -4)` | véc-tơ u bằng 1, 2; véc-tơ A B bằng 3, âm 4 (chỉ khi vế trái là véc-tơ) | B3 |
| `S = (2; +\infty)`, `D = (1; +\infty)`, `x \in (1; 2)` | vẫn đọc khoảng: "khoảng từ 2 đến dương vô cùng" | B3 |
| `12\text{ cm}^2`, `8 \text{ cm}^3`, `9{,}8\,\text{m/s}^2` | 12 xen-ti-mét vuông; 8 xen-ti-mét khối; 9 phẩy 8 mét trên giây bình phương | B4 |
| `Bài 2.15.`, `Mục 4.3`, (sau Bài, Câu, Ví dụ, Hình, Mục, Bảng, Trang, Chương, Phần, Định lí/lý) | Bài 2 chấm 15; Mục 4 chấm 3. Ở chỗ khác `3.14` vẫn là "3 phẩy 14"; `2.500.000` giữ nguyên | B5 |
| `ΔABC ∽ ΔDEF`, `\triangle ABC \backsim \triangle DEF`, `\Delta ABC \sim \Delta DEF` | tam giác A B C đồng dạng với tam giác D E F (Δ + đúng 3 chữ hoa là tam giác; `\Delta = …`, `\Delta x` vẫn là đen-ta) | B6 |
| `f(x) = \begin{cases} x & x \ge 0 \\ -x & x < 0 \end{cases}` | f x bằng x nếu x lớn hơn hoặc bằng 0; âm x nếu x nhỏ hơn 0 (thêm "nếu" khi ô điều kiện không bắt đầu bằng chữ) | B7 |
| `Đổi ra km/h.`, `Đơn vị là m/s.` (lời văn, không có số) | Đổi ra ki-lô-mét trên giờ; Đơn vị là mét trên giây | B8 |

Ngoài phạm vi bản này: công thức hoá học (`H_2O` đọc thành "H 2 O"), đạo hàm riêng, tích phân bội
ngoài `\iint` cơ bản. Ghi vào Gỡ lỗi khi gặp để bổ sung sau.

Còn thiếu, đã biết sau đợt 1 (làm khi H13 hoặc người dùng báo cần; mỗi mục là một commit có test):
- `\vec{u}(1; 2)` (không có `=`) vẫn đọc như khoảng; `\colon` là lệnh lạ.
- "1/3 m" đọc "1 trên 3 mét" (nên là "một phần ba mét").
- Khối `cases` canh bằng `&=` bị coi là hàm từng khúc ("gồm 2 trường hợp" ở kiểu rõ ràng).
- "BÀI 2.15" (viết hoa) và "Bài tập 2.15" vẫn đọc "phẩy".
- Lời văn không có `$`: "6: 2 = 3" (không cách trước dấu `:`) đọc «6:» rồi "2 bằng 3".
- "h/s" (viết tắt "học sinh") vẫn đọc "hát/ét".
- `AnswerFormat`: "Các bước: 1. Mở app." vẫn tách sau "1."; số thứ tự 3 chữ số ("100.") vẫn kết thúc câu.

### 4.4 Bộ máy đọc: `ReadingPlan` + `ReadingEngine`
File mới `OpenVision/Services/Speech/ReadingEngine.swift` (logic) và mở rộng `TTSService` (âm thanh).

Kiểu dữ liệu (thuần, `Codable` để lưu vào Lịch sử):
- `ReadingSegment { id, kind, title, displayText, speechText }` (file `Services/Speech/ReadingModel.swift`):
  `displayText` để hiện trên màn hình ("Câu 3: a Đ, b S"), `speechText` là câu sẽ đưa qua `VietMathSpeech`
  ("Câu 3: a đúng, b sai.", "Dòng 1. Ta có $\Delta = 9$."), do `ReplyAssembler` dựng theo ngôn ngữ và
  `readLineNumbers`. `kind` là
  `mcq(n) | problem(n) | line(n) | final | answer | notice`. `title` ví dụ "Câu 3", "Dòng 2".
  Công thức trong `displayText` giữ dạng chữ model viết, màn hình làm đẹp bằng `MathPrettyText` (4.5).
- `ReadingPlan { turnID, languageCode ("vi"|"en"), answerType (mcq|essay|mixed|other), segments, isComplete }`,
  được **nối thêm đoạn** khi stream tới. Mẩu đọc (`[SpeechPiece]`) **không** lưu trong đoạn: `ReadingEngine`
  dựng chúng bằng `VietMathSpeech` lúc đọc tới đoạn đó, theo cài đặt hiện tại.
- `ReadingRecord { languageCode, answerType, segments }`: bản lưu vào Lịch sử (trường tuỳ chọn
  `Message.reading`). Đọc lại thì dựng mẩu đọc mới theo cài đặt hiện tại (từ điển vừa sửa cũng có hiệu lực).
- Mẩu lời văn dài hơn 200 ký tự được tách tiếp tại dấu phẩy hoặc chấm phẩy gần nhất.
- Cách dùng đã có (đợt 1), cho một lượt hỏi:
  ```swift
  let assembler = ReplyAssembler(languageCode: "vi", readLineNumbers: settings.readLineNumbers)
  var plan = assembler.emptyPlan(turnID: turnID)
  // mỗi lần stream có thêm chữ (accumulated = toàn bộ chữ đã nhận):
  let added = assembler.update(&plan, streamed: AnswerFormat.partialAnswer(in: accumulated))
  // khi stream xong (thêm đoạn thông báo nếu finishReason == "MAX_TOKENS"):
  let tail = assembler.finish(&plan, with: AnswerFormat.parse(accumulated, finishReason: finishReason))
  // đọc: VietMathSpeech.render(segment.speechText, vietnamese: plan.languageCode == "vi", style: style)
  // lưu Lịch sử: plan.record; đọc lại: ReadingPlan(record: record)
  ```
  `update` chỉ **nối thêm** đoạn (mỗi kết quả là tiền tố của kết quả cuối, ID 0…n−1 không đổi), nên
  đoạn nào đã đọc thì không bao giờ bị đổi. `readLineNumbers` chưa có trong `AppSettings` (thêm ở T6.4);
  tới lúc đó dùng mặc định `true`.

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

**T2.1 Script đăng ký file Swift vào pbxproj** ✅ đợt 1 (`ca6736d`)
- Việc: `scripts/pbxproj_files.py add <path>` / `remove <path>`. File dưới `OpenVision/` vào target app
  (Sources phase `5B369180DFE2DD0B99684491`), dưới `OpenVisionTests/` vào target test
  (`4082EAA7B9C9E911E29F7B44`). Thêm đủ 4 mục (PBXBuildFile, PBXFileReference, con của group, mục
  trong Sources phase); tạo PBXGroup nếu thư mục chưa có (ví dụ `Services/Speech`). ID 24 ký tự hex
  in hoa, sinh tất định từ SHA-1 của đường dẫn, kiểm tra không trùng. Lệnh chạy lại không đổi gì.
  Có `--self-test` chạy trên bản sao tạm của pbxproj: thêm rồi xoá một file giả, kết quả phải giống hệt ban đầu.
- Guard: check `project` thêm chiều ngược lại: mọi `path = X.swift;` trong pbxproj phải có file thật.
- Xong khi: `--self-test` pass ở local; guard xanh; CI build xanh.

**T2.2 CI chạy mọi suite test (N13)** ✅ đợt 1 (`8d29c96`, `0da02df`, `7045d52`)
- Việc: trong `run-simulator-tests.sh`, mặc định chạy **toàn bộ** target `OpenVisionTests` (bỏ danh sách
  `-only-testing`), giữ `SUITE=blueprint` làm tuỳ chọn. Suite mới tự được chạy. `GeminiLiveSmokeTests` tự skip.
- Xong khi: log E2E có dòng "Executed" cho từng suite, 0 fail.

**T2.3 Test thư viện Ảnh không bị skip (N1)** ✅ đợt 1 (`324b3a6`, `dd13d9e`)
- Việc: tìm nguyên nhân (in `PHPhotoLibrary.authorizationStatus` trong `setUp`, kiểm tra
  `xcodebuild test-without-building` có cài lại app sau `simctl privacy grant` không). Sửa tối thiểu.
- Xong khi: 3 test `BlueprintPhotoLibraryE2ETests` được chạy (không skip) và pass. Nếu sau 2 lần thử
  vẫn không được: ghi rõ nguyên nhân trong PR và chuyển sang task sau.

**T2.4 `AppLog` và chuyển log** ⏳ đợt 2
- Việc: tạo `AppLog` (4.7) trong `OpenVision/Utilities/Helpers/AppLog.swift` (thư mục đã có), đăng ký bằng
  `python3 scripts/pbxproj_files.py add OpenVision/Utilities/Helpers/AppLog.swift`. Thay `print(`/`NSLog(`
  bằng `AppLog` trong: `VoiceAgentViewModel`, `GeminiLiveService`, `TTSService`, `VoiceCommandService`,
  `GlassesManager`, `AudioSessionManager`, `OpenVisionApp`. Giữ nguyên nội dung thông điệp. Thông điệp có
  văn bản người dùng chỉ ghi khi `verboseLogging` bật.
- Chi tiết (số dòng tính ở `8402cec`):
  - Số lệnh cần thay, đếm bằng `grep -cE '\bprint\('` (chuỗi "print(" trơn cũng khớp `fingerprint(`):
    `GlassesManager` 51 print + 1 NSLog, `VoiceAgentViewModel` 32 + 18, `VoiceCommandService` 29 + 0,
    `GeminiLiveService` 0 + 17, `AudioSessionManager` 6 + 0, `OpenVisionApp` 6 + 2, `TTSService` 0.
  - `AppLog` ghi vào `os.Logger`, vào bộ đệm vòng, **và** một dòng ra stderr (`FileHandle.standardError`).
    Lý do: `launch_smoke` trong `run-simulator-tests.sh` đọc console bằng `simctl launch --console`, chỉ
    thấy stdout/stderr, và **làm đỏ job** nếu thiếu dòng "SDK kính chưa khởi tạo được".
  - Thêm `verboseLogging: Bool = false` vào `AppSettings` (file cũ vẫn decode nhờ bước gộp trong
    `SettingsManager.loadSettings`; mở rộng `testOlderSettingsFilesStillDecode`).
  - Văn bản người dùng (chỉ ghi khi `verboseLogging`): câu lệnh trong VM (khoảng L956, L1166, L1190) và
    transcript trong `VoiceCommandService` (khoảng L295, L695, L768, L846, L894).
  - Bí mật, sửa luôn: `GeminiLiveService` log `key.prefix(6)` (khoảng L258–259, L272, L277) → chỉ ghi số
    thứ tự key ("key 2/3"); thân lỗi HTTP tới 4000 ký tự (khoảng L516) → tối đa 300 ký tự; `OpenVisionApp`
    log cả URL callback (khoảng L74) → chỉ scheme và host.
- Guard: check mới `logging`: 7 file trên không còn `\bprint\(` / `\bNSLog\(` (bỏ qua dòng comment), và
  không có `prefix(6)` cạnh chữ `key` trong `GeminiLiveService`.
- Xong khi: guard xanh, CI xanh, log khởi động trong E2E vẫn hiện thông điệp của app (cả dòng
  "SDK kính chưa khởi tạo được" của lần chạy không có SDK).

**T2.5 Không crash khi SDK kính không khởi tạo được (N2)** ✅ đợt 1 (`89af8da`; cần chủ dự án chạy H1, H9)
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

**T3.1 Tách mẩu, lexer, parser, AST** ✅ đợt 1
- Việc: `MathSpanSplitter`, `MathLexer`, `MathParser`, `MathNode` trong `Services/Speech/`.
- Test (`OpenVisionTests/VietMathParserTests.swift`): mỗi cấu trúc ở bảng 4.3 parse ra đúng cây;
  ngoặc thiếu, lệnh lạ, chuỗi rỗng không crash.
- Xong khi: CI xanh.

**T3.2 `VietnameseMathReader` + `PronunciationDictionary` + `MathReadingStyle`** ✅ đợt 1
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
- Trạng thái: phần thuần ✅ đợt 1. **Phần nối vào `TTSService` ⏳ đợt 2**, chi tiết:
  - `TTSService.enqueue(_:)` hiện chạy `cleanSpokenAudio` → `sentenceIsVietnamese` → `SpokenMath.normalize`
    → một utterance; đó chính là lỗi N4. Thứ tự mới: chọn ngôn ngữ (giữ `sentenceIsVietnamese` /
    `replyIsVietnamese` tới T5.1) → `VietMathSpeech.render(text, vietnamese:, style: .default)` → mỗi
    `.words` qua `cleanSpokenAudio` rồi thành **một** utterance; `.pause(ms)` cộng vào `postUtteranceDelay`
    của utterance trước (không xếp utterance rỗng). Giữ `preUtteranceDelay = bluetoothLeadIn` cho utterance
    đầu và cách đếm `activeUtterances` (một id cho mỗi utterance).
  - Đặt phần thuần vào một hàm static test được, ví dụ trong `TTSService.swift`:
    `static func spokenPieces(for text: String, vietnamese: Bool, style: MathReadingStyle) -> [(text: String, delayAfter: TimeInterval)]`.
  - `cleanSpokenAudio` mới chỉ bỏ thẻ `SPOKEN:`/`DISPLAY:` (còn cần tới T4.4), `**`, `#`, backtick và ký tự
    `$ { } \ ^ _` còn sót. Giữ nguyên chuỗi `static func cleanSpokenAudio` và lời gọi `cleanSpokenAudio(text)`
    (guard lesson5 tìm đúng hai chuỗi này; `verify_ipa_symbols.sh` tìm ký hiệu `cleanSpokenAudio`).
  - Xoá `enum SpokenMath` (cuối `TTSService.swift`) và `BlueprintSolverTests.testSpokenMathReadsSymbolsAsWords`.
  - `BlueprintSolverTests.testCleanSpokenAudioStripsLatexAndMarkdownButKeepsVietnamese` đang khẳng định hành
    vi lỗi N4 ("Ta có 12 cộng 4 bằng 2,5 và Hết") → viết lại theo hành vi mới. Thêm test N4 qua
    `spokenPieces` (đầu ra đã kiểm bằng `VietMathSpeech`, kiểu mặc định):
    | Đầu vào | Các mẩu đọc |
    |---|---|
    | `Ta có $\frac{1}{2}$ cộng $\sqrt{4}$ bằng **2,5**.` | "Ta có", "một phần hai", "cộng", "căn 4", "bằng 2 phẩy 5." |
    | `$\sqrt{x}$`, `$x \le 2$` | "căn ích"; "ích nhỏ hơn hoặc bằng 2" |
    | `-2x + 4 = 0`, `2*3*4 = 24` | "âm 2 ích cộng 4 bằng 0"; "2 nhân 3 nhân 4 bằng 24" |
    | `Đáp án $\boxed{B}$`, `\[ x = 2 \]` | "Đáp án", "bê"; "ích bằng 2" |
  - `TextChunking.sentences` (cuối `VoiceAgentViewModel.swift`) tách câu trước khi xếp hàng. Thêm test bảo
    đảm không tách bên trong `$…$` (ví dụ "Ta có $x = 2.5$. Vậy $y = 1$." → 2 câu); sửa nếu cần.
  - E2E `testSpokenAnswerPlaysCompletelyAndBargeInStaysClosedUntilTheEnd` phải vẫn pass.
  - Cài đặt đọc toán (4.6) chưa có trong `AppSettings`: dùng `MathReadingStyle.default` (đúng D3); T6.4
    thêm khoá và truyền style vào.

**T3.4 Kiểm tra độ bền** ✅ đợt 1 (`f1bd04f`)
- Việc: test sinh 1000 chuỗi ngẫu nhiên (seed cố định) gồm ký tự LaTeX, Unicode toán, chữ Việt.
- Xong khi: không crash; đầu ra không chứa `\ $ { } ^ _`; mỗi mẩu ≤ 200 ký tự; tổng thời gian < 2 s.

### Phase 4: định dạng trả lời v2, bỏ DISPLAY

**T4.1 Prompt v2** (văn bản ✅ đợt 1 `be7c365`; nối ⏳ đợt 2, làm **sau** T4.3, xem §11)
- Việc: viết lại `buildSystemPrompt()` theo 4.2 (Gemini tự nhận loại bài). Giữ các phần ảnh, `[[CAPTURE]]`,
  `[[END]]`, ngôn ngữ, kiểm tra lại kết quả toán, ngày giờ, hướng dẫn riêng, ghi nhớ. Bỏ hẳn
  "DUAL-CHANNEL", `SPOKEN:`, `DISPLAY:`, "2 to 4 complete sentences", câu "shown on the phone screen".
  Sửa N17.
- Guard (sửa `verify_blueprint.py`): thay check "2 to 4 complete sentences" và "SPOKEN:/DISPLAY:"
  bằng: prompt chứa `TYPE:`, `Q1:`, `L1:`, `FINAL:`; không chứa `DISPLAY:`; không còn câu cũ
  "shown on the phone screen"; có câu cấm bảo người dùng nhìn điện thoại hoặc màn hình.
  Giữ check "language the user used", "under 250 characters" (không có), `captureToken`.
- Test: thay `testSystemPromptKeepsTheDualChannelContractAndIsBilingual` bằng bản v2.1 (có đủ khuôn
  MCQ / ESSAY / MIXED / OTHER, có câu cấm nhắc màn hình điện thoại, không còn chế độ Gia sư).
- Xong khi: guard xanh, CI xanh.
- Phần còn lại (đợt 2), chi tiết:
  - Thân `GeminiLiveService.buildSystemPrompt()` chỉ còn một lời gọi
    `PromptV2.systemPrompt(now: Date(), timeZone: .current, userPrompt: settings.userPrompt, memories: settings.memories)`.
    Giữ tên `buildSystemPrompt()` (`makeRequestBody` và các test gọi nó). Sửa comment đầu `PromptV2.swift`
    (đang ghi "not wired yet").
  - Guard, cùng commit: check lesson5 "2 to 4 complete sentences" và check "SPOKEN:/DISPLAY:" (đang đọc
    `GeminiLiveService.swift`) → đổi sang đọc `PromptV2.swift` với nội dung ở dòng "Guard" trên; check
    workflow "language the user used" → đọc `PromptV2.swift` (câu này ở khoảng dòng 70 của file đó).
  - Test, cùng commit: `BlueprintSolverTests.testSystemPromptKeepsTheDualChannelContractAndIsBilingual` →
    bản v2.1 (dùng `PromptV2.noScreenRule`); E2E `testShutterPhotoQuestion…` đang kiểm system prompt chứa
    "DISPLAY:" → đổi thành "TYPE:"; `testGoodbyeTokenEndsTheSessionAndIsNeverSpoken` vẫn kiểm prompt có `endToken`.
  - Vì sao làm sau T4.3: khi prompt đổi, Gemini thật trả định dạng v2.1. Nếu app còn đọc bằng
    `parseDualChannel`, câu trả lời không có `SPOKEN:` sẽ đi vào `generateSpokenSummary`, và kính sẽ đọc
    "Các bước giải chi tiết đã hiển thị trên màn hình điện thoại" (trái D5).

**T4.2 `AnswerFormat` (parser v2)** (phần thuần ✅ đợt 1; nối vào `GeminiLiveService` ⏳ đợt 2)
- Việc: file mới `OpenVision/Services/Speech/AnswerFormat.swift` (thuần): `parse(_ raw:) -> [AnswerSection]`
  và `completedSections(in accumulated:) -> [AnswerSection]` cho stream (4.2). `GeminiLiveService` gọi
  callback mới `onPartialSections([AnswerSection])` thay cho `onPartialSpoken`. Mất kết nối giữa chừng:
  giữ câu trả lời nếu đã có `ANSWER` (thay điều kiện dùng `parseDualChannel` hiện nay).
- Test: chuyển các test parser cũ sang v2: biến thể thẻ, chữ "display"/`\displaystyle` trong nội dung
  không cắt câu, tính "tiền tố" khi stream (mỗi kết quả trung gian là tiền tố của kết quả cuối),
  `[[END]]` không bao giờ bị đọc, câu trả lời không thẻ, dòng nửa thẻ.
- Xong khi: CI xanh.
- Phần còn lại (đợt 2), chi tiết (số dòng tính ở `8402cec`):
  - Callback mới trong `GeminiLiveService`: `var onPartialAnswer: ((ParsedAnswer) -> Void)?`. Nó thay cho ý
    `onPartialSections([AnswerSection])` ở trên, vì `ReplyAssembler.update` cần cả loại bài. Trong vòng SSE
    của `performStreamingRequest` (sau `accumulated +=`, khoảng L528–530): nếu chữ đã nhận có thẻ
    `SPOKEN:`/`DISPLAY:` (`spokenTagRegex` / `displayTagRegex`) thì đi đường cũ `onPartialSpoken`; ngược
    lại gọi `onPartialAnswer?(AnswerFormat.partialAnswer(in: accumulated))`. Đường cũ bị xoá ở T4.4. Nhờ
    vậy app chạy đúng với cả hai định dạng trong lúc chuyển.
  - `finishReason`: đã được parse vào `StreamChunk.finishReason` nhưng chưa ai đọc. Đọc nó ngay sau
    `guard let chunk = parseSSELine(line)` (khoảng L522), **trước** `guard !chunk.text.isEmpty` (khoảng L527),
    vì chunk cuối có thể không có chữ. Mang nó qua `.success`, `TurnResult`, `deliver`, tới ViewModel bằng
    callback mới `onAnswerComplete: ((_ raw: String, _ finishReason: String?) -> Void)?`
    (`agentMessageCallback` giữ cho đường cũ tới T4.4).
  - Mất kết nối giữa chừng (`case .network`, khoảng L316–327): với câu trả lời v2.1, giữ phần đã có nếu
    `!AnswerFormat.parse(partial).sections.isEmpty`.
  - `GeminiStub.stream(_:dropAtEnd:signature:)` (cuối `BlueprintGeminiE2ETests.swift`) thêm tham số
    `finishReason: String? = nil`: khi có, thêm một chunk cuối không có chữ, mang `finishReason`.
  - Test E2E mới (giữ test cũ tới T4.4): câu trả lời v2.1 qua `GeminiStub` → `sections` của mỗi
    `onPartialAnswer` là tiền tố của `AnswerFormat.parse(final).sections`; `[[CAPTURE]]` không bao giờ nằm
    trong một section; `finishReason: "MAX_TOKENS"` tới được `onAnswerComplete`.

**T4.3 Nối vào ViewModel (tạm thời, trước khi có ReadingEngine)** (phần thuần ✅ đợt 1; nối ⏳ đợt 2)
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
- Trạng thái: `ReplyAssembler`, `ReadingModel` ✅ đợt 1. **Nối vào ViewModel ⏳ đợt 2**, chi tiết:
  - Một lượt v2.1 trong `VoiceAgentViewModel` (code mẫu ở 4.4, mục "Cách dùng đã có"):
    1. `onPartialAnswer` lần đầu của lượt: `agentState = .speaking` và `isBargeInPaused = true` **trước**
       khi xếp câu nói (lesson 4); `plan = assembler.emptyPlan(turnID:)`; `ttsService.beginStreaming()`.
    2. Mỗi `onPartialAnswer`: `assembler.update(&plan, streamed:)`; mỗi đoạn mới →
       `ttsService.speakChunk(segment.speechText)` (sau T3.3, TTS tự đọc công thức bằng `VietMathSpeech`).
    3. `onAnswerComplete(raw, finishReason)`: `assembler.finish(&plan, with: AnswerFormat.parse(raw, finishReason:))`;
       đọc các đoạn mới (gồm thông báo MAX_TOKENS, N12); `ttsService.endStreaming()`; lưu Lịch sử.
    4. Không có partial nào (trả lời một lần): `assembler.plan(turnID:parsed:)` rồi đọc các đoạn theo thứ tự,
       vẫn đặt `.speaking` + `isBargeInPaused = true` trước.
    5. `parsed.endsConversation` → xử lý như `endSessionAfterSpeaking` hiện có. Không bao giờ đọc
       `[[CAPTURE]]` (`GeminiLiveService` đã tự chụp và hỏi lại).
  - `lastSpokenAnswer` = các `speechText` nối bằng dấu cách (cho "nghe lại"). `latestSolution = nil` cho câu
    trả lời v2.1 (T4.4 xoá hẳn).
  - Lịch sử: thêm `var reading: ReadingRecord? = nil` vào `Message` (tham số `reading:` mặc định `nil` ở
    `init`; file cũ không có khoá vẫn decode, vì Codable tự sinh coi Optional thiếu khoá là `nil`). Thêm
    `ConversationManager.addAssistantMessage(_ text: String, reading: ReadingRecord?)`; `content` là các
    `displayText` nối bằng xuống dòng. `recordAssistantReply` gọi bản mới.
  - `seedHistory(from:)` (khoảng L55–64 của `GeminiLiveService`, gọi từ `ConversationListView` khoảng L166):
    nhận thêm `reading` của từng tin. Tin có `reading` → dựng lại văn bản v2.1 từ record bằng một hàm thuần
    mới (ví dụ `AnswerFormat.text(for: ReadingRecord) -> String`, có test: `parse(text(for: r))` cho lại đúng
    các đoạn). Tin cũ không có `reading` → giữ `dualChannelFromHistory` tới T4.4.
  - Guard lesson4 hiện tìm `"onPartialSpoken = {"` rồi kiểm `isBargeInPaused = true` đứng trước
    `feedStreamingSpeech`. Thêm check tương tự cho thân `onPartialAnswer = {` (`isBargeInPaused = true` trước
    lời gọi xếp câu đầu tiên). Giữ check cũ tới khi T4.4 xoá `onPartialSpoken`.
  - Nút "Đọc lại", điều khiển nhịp đọc và tốc độ theo loại bài thuộc Phase 5; ở task này mọi đoạn dùng
    `speechRate`.

**T4.4 Gỡ DISPLAY và bộ hiển thị KaTeX** ⏳ đợt 2 (task cuối của đợt)
- Việc: xoá mọi thứ ở 4.8 thuộc màn hình (dùng `scripts/pbxproj_files.py remove` cho
  `SolutionView.swift`; xoá 4 dòng folder reference `SolutionRenderer` trong pbxproj bằng script hoặc
  một hàm `remove-folder` của script; xoá thư mục; sửa `project.yml`). Sửa `VoiceAgentView`,
  `ConversationListView`, onboarding cho hết tham chiếu.
- Guard: bỏ check "DISPLAY channel is rendered (offline KaTeX)"; thêm check: không còn file
  `SolutionView.swift`, thư mục `SolutionRenderer`, chuỗi `SolutionWebView`/`latestSolution` trong `OpenVision/`.
- Xong khi: CI xanh; ghi kích thước IPA trước/sau trong PR (chạy Build Unsigned IPA).
- Chi tiết (đợt 2; số dòng tính ở `8402cec`):
  - File: `python3 scripts/pbxproj_files.py remove OpenVision/Views/Components/SolutionView.swift`,
    `python3 scripts/pbxproj_files.py remove-folder-ref OpenVision/Resources/SolutionRenderer` (xoá đúng 4
    dòng), rồi `git rm -r` hai đường dẫn đó. `project.yml`: bỏ exclude `"SolutionRenderer/**"` và mục resource
    folder (khoảng L59–63).
  - Giao diện: `VoiceAgentView` (`openSolution` khoảng L27–28, `.sheet` L101–105, `SolutionButton` L260–266);
    `ConversationListView.MessageBubble` (`hasRichSolution`, nút "Xem công thức", sheet: khoảng L181–231);
    `OnboardingView` ("Lời giải có công thức", khoảng L183–184 và L279).
  - ViewModel: `latestSolution` (L593–595 và các chỗ reset), `solutionWorthShowing` (L1099–1103),
    `parseDualChannelResponse` (L1106–1108), đường cũ trong `agentMessageCallback` và `onPartialSpoken`.
  - `GeminiLiveService`: `dualChannelFromHistory`, `streamingSpokenPrefix`, `spokenTagRegex`/`displayTagRegex`,
    `parseDualChannel`, `generateSpokenSummary`, `cleanChannelText` (nếu hết dùng), `onPartialSpoken`, đường
    cũ trong vòng SSE. Câu "không chụp được ảnh" (khoảng L195, L198–202) đổi sang `TYPE: OTHER\nANSWER: …`.
    `deliver` (khoảng L551) dùng `AnswerFormat` thay `parseDualChannel`. `cleanSpokenAudio` bỏ phần thẻ.
  - Guard: xoá check workflow KaTeX (đọc `SolutionView.swift` và `katex.min.js`; helper `read()` báo lỗi khi
    file thiếu) và check lesson4 `onPartialSpoken` (đã có check `onPartialAnswer` từ T4.3); thêm check như dòng
    "Guard" trên.
  - Test viết lại hoặc xoá (đã có test tương đương trong `AnswerFormatTests`): trong `BlueprintSolverTests`
    các test `parseDualChannel` (khoảng L17–67), `testStreamingSpokenPrefix…` (L107–127),
    `testSolutionIsOfferedOnlyWhenItAddsSomething` (L236–239), `testFallbackSpokenSummaryUsesTheAnswersLanguage`
    (L326–331); `testGoodbyeTokenEndsTheSessionAndIsNeverSpoken` và `testHistoryRepliesAreFedBackInTheDualChannelShape`
    chuyển sang v2.1. Trong `BlueprintGeminiE2ETests`: fixture `answer` (L24) sang v2.1 và mọi test dùng
    `onPartialSpoken` / `parseDualChannel`. `GeminiLiveSmokeTests` (L46–63) dùng `AnswerFormat`.
  - Tài liệu: README dòng "Two channels … KaTeX" và dòng ghi công KaTeX/marked; CHANGELOG `[Unreleased]`.

### Phase 5: bộ máy đọc (4.4)

**T5.1 TTSService: hàng đợi mẩu**
- Việc: API xếp `SpeechPiece` với rate và `postUtteranceDelay` riêng; delegate `didPause`, `didContinue`,
  `willSpeakRangeOfSpeechString` → tiến độ công khai; ngôn ngữ theo cả câu trả lời (N5). Giữ hàm cũ
  cho thông báo ngắn (`speak`).
- Xong khi: CI xanh; test `testSpokenAnswerPlaysCompletely…` vẫn pass (sửa cho định dạng v2).

**T5.2 `ReadingEngine`**
- Việc: kiểu dữ liệu, trạng thái, lệnh, chế độ, đọc chép (4.4); protocol `SpeechSynthesizing`.
- Cách chia file (bắt buộc): `scripts/swift-local/run.sh` biên dịch **mọi** file trong `Services/Speech/` trên
  Linux, nơi không có Combine, SwiftUI hay AVFoundation. Vì vậy máy trạng thái đọc là kiểu thuần
  `ReadingMachine` (struct, chỉ Foundation) trong `Services/Speech/ReadingMachine.swift`, nhận lệnh và sự kiện
  "utterance xong", trả về việc cần làm (đọc mẩu nào, rate, delay, chờ lệnh). Lớp `@MainActor
  ObservableObject` `ReadingEngine` đặt ở `Services/TTS/ReadingEngine.swift`, chỉ nối `ReadingMachine` với
  `TTSService`. Test `ReadingEngineTests` kiểm `ReadingMachine` với bản tổng hợp giả, chạy được cả local.
- Test (`OpenVisionTests/ReadingEngineTests.swift`, bản tổng hợp giả): thứ tự utterance, rate từng mẩu
  (lời văn / công thức / hệ số trực tiếp), nghỉ giữa đoạn, pause/resume, next/previous/repeat ở biên,
  đổi tốc độ giữa chừng đọc lại mẩu hiện tại, đọc chép chờ "tiếp" và tự đi tiếp sau N giây, nối đoạn
  khi đang đọc, `stop` giữ kế hoạch.
- Xong khi: CI xanh.

**T5.3 Điều khiển bằng giọng khi đang đọc (N6–N9)**
- Việc: `ReadingCommand.parse` (thuần, file `Services/Speech/ReadingCommand.swift`) + thay đổi
  `VoiceCommandService` và ViewModel theo 4.4.
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
sang tiếng Việt (N16). Phần biến đổi chuỗi của `MathPrettyText` là hàm thuần đặt trong
`Services/Speech/MathPrettyText.swift` (test `MathPrettyTextTests` chạy được local); view SwiftUI hiển thị
nó đặt trong `Views/Components/`.

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
- **T9.4** PR template: "PLAN.md §7 (H1–H22)". ✅ làm sớm ở bản v2.2.
- **T9.5** PLAN.md: đánh dấu task nào xong ở commit nào (mục 3), không xoá nội dung khác.
- Đã làm sớm ở bản v2.2 (22/11): `AGENTS.md` mới; CONTRIBUTING bỏ phần lỗi thời (OpenClaw, `rayl15`, `Tests/`,
  `AIBackend` factory, `NativeTool`) và ghi quy trình test thật; README thêm mục trạng thái, sửa lệnh test và
  link clone; CHANGELOG ghi đợt 1. Phase 9 vẫn phải viết lại README và CHANGELOG theo tính năng v2 khi các
  đợt 2–5 xong.

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

Chạy bước nào sau đợt nào (agent ghi trong PR "Cần chủ dự án chạy H…" theo bảng này):
| Sau đợt | Bước | Vì sao |
|---|---|---|
| 1 (PR #4) | H1, H9 | `GlassesManager` chỉ dùng SDK sau khi `configure()` thành công (T2.5); cách trả lời chưa đổi |
| 2 | H1, H2, H6, H7, H14 (chỉ phần đọc và nghỉ), H22 (thứ tự đọc) | prompt v2.1, đọc toán tiếng Việt, bỏ DISPLAY |
| 3 | H14, H15, H16, H17 | bộ máy đọc, lệnh giọng nói khi đang đọc |
| 4 | H13, H18, H19 | giao diện, màn hình Thử đọc, Gỡ lỗi |
| 5 | H3, H4, H5, H8, H9, H10, H11, H12, H20, H21 | ảnh, DAT 1.1.0, giữ kết nối, đèn camera, nghe |

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
   (`Wearables.shared.openDATGlassesAppUpdate()`). Cần firmware kính V128+, Meta AI V292+, iOS 17.2+ (DAT 1.0.1).
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
BR=feature/voice-v2-wave2          # branch của đợt (§0.2)

# Xem PR hiện có trước khi mở PR mới
gh api "repos/$REPO/pulls?state=all&per_page=10" \
  --jq '.[] | "\(.number) \(.state) \(.head.ref) -> \(.base.ref) \(.title)"'

# Mở PR của đợt vào branch tích hợp (một lần). Không dùng `gh pr create` (GraphQL, luôn lỗi ở đây).
gh api repos/$REPO/pulls -f title="Wave 2: …" -f head="$BR" -f base="feature/voice-v2" \
  -F body=@/projects/sandbox/pr-body.md --jq '.html_url'

# Các lần chạy của branch, rồi job và log job lỗi
gh api "repos/$REPO/actions/runs?branch=$BR&per_page=10" \
  --jq '.workflow_runs[] | "\(.id) \(.name) \(.status)/\(.conclusion) \(.head_sha[0:7])"'
gh api repos/$REPO/actions/runs/<RUN_ID>/jobs --jq '.jobs[] | "\(.id) \(.name) \(.conclusion)"'
gh api repos/$REPO/actions/jobs/<JOB_ID>/logs > /projects/sandbox/ci.log
grep -n -E "##\[error\]|Executed [0-9]+ tests|error:" /projects/sandbox/ci.log | head -80
```
- Lưu log ra `/projects/sandbox/` (thư mục `/tmp` không giữ file giữa các lệnh). Xoá file tạm khi xong.
- Workflow chạy trên mọi PR (đo ở `8402cec`):
  | Workflow | Job | Thời gian | Làm gì |
  |---|---|---|---|
  | `CI` (`ci.yml`) | Build app + tests (iOS device, unsigned) | ~2,5 phút | Biên dịch app và target test cho thiết bị, không ký. Bắt lỗi biên dịch iOS mà Linux không thấy |
  | `E2E (Blueprint)` (`e2e.yml`) | Blueprint guard (static) | ~5 giây | `verify_blueprint.py` |
  | | Blueprint E2E (iOS simulator) | ~11 phút | `run-simulator-tests.sh`: build, cài app, cấp quyền Ảnh, 2 lần khởi động thử (thường và không SDK kính), rồi **mọi** suite test |
  | `Build Unsigned IPA` (`build-ipa.yml`) | | chỉ chạy tay | IPA để cài bằng Sideloadly |
- Đọc kết quả E2E: `grep -nE "Test suites:|Test Suite '|Executed [0-9]+ tests|CI skip check|SDK kính" e2e.log`.
  Ở `8402cec`: "Test suites: all", 13 suite, `Executed 218 tests, with 3 tests skipped and 0 failures`;
  3 test skip là `GeminiLiveSmokeTests` (chỉ chạy khi bật `live_gemini`). Suite mới phải có dòng
  `Test Suite '<Tên>' started` và `Executed`. Nếu không có, file test chưa được đăng ký vào pbxproj.
- `workflow_dispatch` của E2E có hai tuỳ chọn: `live_gemini` (gọi Gemini thật, tốn quota, cần secret
  `GEMINI_API_KEYS`) và `blueprint_only` (chỉ chạy các suite Blueprint).
- CI mất 3–15 phút; chờ bằng vòng `sleep 45` kiểm tra trạng thái, tối đa 90 phút cho một lần chạy.
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
Kiểm chứng: guard <n> passed/warned, 0 failed | local <n> test (scripts/swift-local/run.sh) |
            CI run <id> ✅ | E2E run <id> ✅, Executed <n> tests, <k> skipped (tên suite skip và lý do)
Test fail còn lại: <tên test>: có từ trước? nguyên nhân?
Cần chủ dự án chạy trên kính / xem giao diện: H…
Quyết định đã dùng giá trị mặc định tạm: D…
Phát hiện mới (không có trong PLAN): …
```

## 11. Chia việc: đợt song song và đợt tuần tự

Một đợt đi qua 4 bước: **làm** (một hoặc nhiều agent) → **review** (một agent) → **sửa theo review** (agent
làm việc, trên branch của mình) → **tích hợp** (một agent, tuần tự). Prompt mẫu cho từng vai ở §13.

**Đợt 1 ✅ xong (22/11/2026; 3 agent song song; kết quả ở §3.1).** Mỗi agent một thư mục `git worktree`,
một branch; chỉ A mở PR vào `feature/voice-v2`. Ba nhóm **không sửa chung file nào**. Bảng và quy tắc dưới
đây là mẫu cho các đợt song song sau:
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

**Review.** Một agent review đọc diff của đợt (gộp các branch vào một worktree tạm để đọc chung) theo
`PLAN.md`, **chạy thử** chứ không chỉ đọc (probe SwiftPM, chạy script trên bản sao), và ghi file review
(ở đợt 1: `/projects/sandbox/reviews/wave1-review.md`, ngoài repo). Mỗi lỗi có: mã (`A1`, `B3`, `C2`; `X1` cho
lỗi cần cả hai module; `I1` cho việc của người tích hợp), mức (`blocker` = đọc sai đáp án, crash, hỏng build,
hoặc trượt tiêu chí "Xong khi"; `should-fix`; `nit`), `file:dòng`, bằng chứng (đầu vào → kết quả → mong đợi),
cách sửa, test cần thêm. Cuối file có mục "Đã kiểm tra, không có lỗi" để vòng sửa không kiểm lại.
Agent làm việc sửa trên đúng branch của mình, **mỗi mã lỗi một commit** (`Task: T3.1 (review X1)`), chạy lại
test, push. Người tích hợp tự kiểm lại các lỗi `blocker` bằng probe trước khi gộp.

**Tích hợp (tuần tự).** Trong một worktree của `feature/voice-v2`:
1. Merge PR của agent có PR (`gh api -X PUT repos/$REPO/pulls/<n>/merge -f merge_method=merge -f sha=<sha đủ 40 ký tự>`;
   sha rút gọn bị từ chối với lỗi 422), rồi `git merge --no-ff origin/<branch>` cho các branch chỉ push.
2. `scripts/swift-local/run.sh` (mọi suite thuần cùng lúc, để bắt trùng tên kiểu giữa các agent).
3. Đăng ký file mới: `python3 scripts/pbxproj_files.py --dry-run add <các file>` để xem, rồi chạy thật; chạy lại
   lần nữa phải không đổi gì. Guard phải 0 failed.
4. Thêm test xuyên module nếu đợt có hai module nói chuyện với nhau (đợt 1: `ReplyAssemblerSpeechTests`).
5. Push một lần, chờ CI + E2E (§9), kiểm từng suite mới có dòng `Executed`.
6. Cập nhật `PLAN.md` §3.1 và trạng thái task ở §5 (commit `Docs:`), dọn worktree tạm.

**Các đợt sau:**
| Đợt | Phạm vi | Cách chia |
|---|---|---|
| 2 | T2.4, T3.3 (nối vào `TTSService`), T4.2 (nối), T4.3 (nối), T4.1 (nối prompt), T4.4 | **Một agent, tuần tự**, theo đúng thứ tự này (xem dưới). Branch `feature/voice-v2-wave2`, PR vào `feature/voice-v2` |
| 3 | Phase 5 (T5.1, T5.2, T5.3, T5.5) | Song song 3 agent: A `TTSService` (T5.1); B `ReadingMachine` thuần + test (T5.2, file mới trong `Services/Speech/`); C `ReadingCommand` thuần + test (phần thuần T5.3). Sau đó tuần tự: `ReadingEngine` (lớp nối), `VoiceCommandService` + ViewModel (T5.3), T5.5 |
| 4 | Phase 6 (giao diện) | Song song 2 agent: A phần thuần (`MathPrettyText`, gom lượt hỏi, trạng thái chip, + test); B Cài đặt mới (T6.4) và khoá ở 4.6. Sau đó tuần tự T6.2, T6.3, T6.5, T6.6 |
| 5 | Phase 7–8 (ảnh, DAT 1.1.0, giữ kết nối, camera/đèn, nghe) | Song song 2 agent, **cả hai có PR** (đều cần CI): A `GlassesManager`, `project.yml`/pbxproj cho DAT 1.1.0, đường ảnh trong ViewModel (T7.1–T7.9); B `VoiceCommandService` (T8.1–T8.3). B không tạo file Swift mới |
| 6 | Phase 9 (tài liệu) | Một agent |

Thứ tự đợt 2 và lý do (khác thứ tự số task ở Phase 4, có chủ đích):
1. **T2.4** trước, vì nó sửa dòng log trong hầu hết các file mà các task sau cũng sửa.
2. **T3.3** (nối): TTS đọc công thức bằng `VietMathSpeech`; câu trả lời dạng cũ (SPOKEN) cũng được lợi ngay.
3. **T4.2** (nối): `GeminiLiveService` nhận cả hai định dạng: có thẻ `SPOKEN:`/`DISPLAY:` thì đi đường cũ,
   còn lại đi `AnswerFormat` (`onPartialAnswer`, `onAnswerComplete`, `finishReason`).
4. **T4.3** (nối): ViewModel dựng `ReadingPlan`, đọc từng đoạn, lưu `ReadingRecord`.
5. **T4.1** (nối prompt): đến lúc này app đã đọc được v2.1. Nếu làm trước, câu trả lời v2.1 sẽ rơi vào
   `generateSpokenSummary` và kính đọc "đã hiển thị trên màn hình điện thoại".
6. **T4.4**: gỡ DISPLAY, KaTeX và đường cũ; chuyển các test cũ sang v2.1.
Sau mỗi task app phải chạy được đầu–cuối. Mỗi task một commit; push và chờ CI + E2E xanh trước task sau.
Sau T4.4: review đợt 2, vòng sửa, rồi ghi "Cần chủ dự án chạy H1, H2, H6, H7, H14, H22" trong PR.

Quy tắc chung cho đợt song song (rút ra từ đợt 1):
- Mỗi agent một worktree: `git -C <repo> worktree add -b feature/voice-v2-<tên> /projects/sandbox/wt-<tên> origin/feature/voice-v2`.
- Mỗi agent một danh sách file được sửa/tạo, không giao nhau. `project.pbxproj` chỉ do **một** người sửa
  trong đợt: người tích hợp, hoặc agent có PR được ghi rõ trong bảng (nó cần CI cho file của chính nó). Hai
  branch cùng thêm dòng vào pbxproj dễ xung đột khi merge.
- Agent không có PR: file mới chỉ đặt trong `Services/Speech/` (kiểm được bằng `scripts/swift-local/run.sh`).
  Code đụng AVFoundation, UIKit, SwiftUI, DAT cần CI, nên thuộc về agent có PR hoặc bước tuần tự.
- Không chạy hai lệnh sửa cùng một file song song; sau khi sửa, `grep` lại để chắc thay đổi còn đó.

---

## 12. Kiểm thử: agent tự chạy gì, ở đâu

Năm lớp, từ nhanh tới chậm. Một task chỉ xong khi mọi lớp liên quan tới nó xanh. Trên máy Mac có Xcode,
chạy đủ các lớp (cả Gemini thật và iPhone) theo prompt ở §13.6.
| Lớp | Lệnh | Ở đâu, bao lâu | Bắt được gì |
|---|---|---|---|
| 1. Guard tĩnh | `python3 scripts/blueprint/verify_blueprint.py` (hoặc `make blueprint-check`) | sandbox, vài giây | bất biến âm thanh (lesson 1–4), prompt, pbxproj hai chiều, Info.plist, chuỗi giống API key |
| 2. Swift thuần | `scripts/swift-local/run.sh [lọc theo tên file test]` | sandbox Linux, ~12 s lần đầu, ~3 s lần sau | logic trong `Services/Speech/` |
| 3. Build iOS | job CI `Build app + tests (iOS device, unsigned)` | GitHub, ~2,5 phút | lỗi biên dịch toàn app (Swift 5 mode, iOS 18, Xcode 26.6) |
| 4. E2E simulator | job `Blueprint E2E (iOS simulator)` (trên Mac: `make e2e`) | GitHub, ~11 phút | mọi suite XCTest; Gemini giả (`GeminiStub`); thư viện Ảnh thật; khởi động có và không có SDK kính |
| 5. Phần cứng | §7 | chủ dự án | kính, Bluetooth, loa, mic, đèn camera |

### 12.1 Guard
- Luôn "0 failed". `[WARN] ci build-ipa.yml only runs on workflow_dispatch` có từ trước, không phải việc của đợt nào.
- Khi thiết kế đổi làm một check sai: sửa check trong cùng commit; không xoá check nếu không có check thay thế (§0.8).
- Guard quét cả `.md`, `.yml`, `.json` để tìm chuỗi giống API key Gemini: không dán key vào bất kỳ file nào,
  kể cả key giả có dạng giống thật.

### 12.2 Swift thuần trên Linux (`scripts/swift-local/run.sh`)
- Script biên dịch **mọi** `OpenVision/Services/Speech/*.swift` thành module `OpenVision`, và chạy các file
  `OpenVisionTests/<Tiền tố>*Tests.swift` với tiền tố trong mảng `PREFIXES`: `VietMath`, `AnswerFormat`,
  `ReplyAssembler`, `PromptV2`, `ReadingEngine`, `ReadingCommand`, `ReadingModel`, `MathPretty`. Suite thuần mới
  phải có tên bắt đầu bằng một tiền tố đó, hoặc thêm tiền tố vào `PREFIXES` trong cùng commit.
- Package SwiftPM nằm ngoài repo (`../.swift-local/<tên thư mục repo>`) và giữ `.build` để chạy lại nhanh.
- Quy tắc để code chạy cả Linux lẫn iOS: chỉ `import Foundation`; không `as NSString`; dùng
  `NSRange(s.startIndex..., in: s)` và `Range(nsRange, in: s)`; không Combine (`ObservableObject`), SwiftUI,
  AVFoundation, `os.Logger` trong `Services/Speech/`.
- Xem đầu ra thật khi phát triển: tạo package nháp ngoài repo (ví dụ `/projects/sandbox/.swift-local/probe/`),
  symlink `Services/Speech/*.swift` vào `Sources/OpenVision/`, viết một test chỉ `print`, chạy `swift test`
  (chép `Package.swift` từ `scripts/swift-local/run.sh`). `/tmp` không giữ file giữa các lệnh.
- Các test này cũng chạy trên simulator (lớp 4), vì file test đã được đăng ký vào target test iOS.

### 12.3 Viết test
- So **chuỗi chính xác** (đầu vào → câu đọc), không chỉ "không rỗng". Bộ đọc toán: dùng helper `check()` của
  `VietMathSpeechTests` (chạy cả hai kiểu đọc × hai `letterStyle`). Chuỗi mong đợi lấy từ bảng 4.3, H13 hoặc
  từ cách đọc của người Việt (§2.5); không chép đầu ra hiện tại của code rồi coi là đúng.
- Stream: mỗi kết quả trung gian là **tiền tố** của kết quả cuối (mẫu: `AnswerFormatTests`, `ReplyAssemblerTests`).
- Mạng: `GeminiStub` (cuối `BlueprintGeminiE2ETests.swift`, một `URLProtocol`). `GeminiStub.enqueue(.stream("…"))`
  hoặc `.status(429, body: "…")`; đọc request đã gửi qua `GeminiStub.captured` (`systemPrompt`, `contents`,
  `generationConfig`, `apiKey`); gọi `GeminiStub.reset()` trong `setUp`. Test E2E cất và trả lại các callback của
  `GeminiLiveService.shared` trong `setUp` / `tearDown`, làm theo các test có sẵn.
- Cài đặt: mỗi khoá mới trong `AppSettings` → mở rộng `testOlderSettingsFilesStillDecode` (`SettingsSecretsTests`).
- File test mới: `python3 scripts/pbxproj_files.py add OpenVisionTests/<Tên>Tests.swift`. Chưa đăng ký thì CI không
  chạy nó và guard báo lỗi. Không tạo thư mục test riêng.

### 12.4 Các suite hiện có (ở `8402cec`)
| Suite | Test | Chạy local | Nội dung |
|---|---|---|---|
| `VietMathSpeechTests` | 52 | có | bảng 4.3, 15 mẫu H13, luật sau review, từ điển, kiểu đọc, ràng buộc đầu ra, thời gian |
| `VietMathParserTests` | 32 | có | cây `MathNode`; đầu vào hỏng không crash |
| `VietMathFuzzTests` | 3 | có | 1000 chuỗi seed cố định, lồng sâu |
| `AnswerFormatTests` | 26 | có | thẻ, bí danh, stream, loại bài, MAX_TOKENS, CAPTURE/END |
| `ReplyAssemblerTests` | 17 | có | chữ hiển thị và câu đọc từng loại, Việt và Anh, stream, Codable |
| `ReplyAssemblerSpeechTests` | 5 | có | cả câu trả lời qua `AnswerFormat` → `ReplyAssembler` → `VietMathSpeech` |
| `PromptV2Tests` | 8 | có | prompt v2.1 |
| `BlueprintSolverTests` | 30 | không | parser cũ, `cleanSpokenAudio`, giọng, ảnh, prompt cũ (đợt 2 đổi nhiều test ở đây) |
| `BlueprintGeminiE2ETests` | 19 | không | `GeminiLiveService` thật với `GeminiStub`: stream, retry, lịch sử, CAPTURE, TTS |
| `BlueprintPhotoLibraryE2ETests` | 3 | không | thư viện Ảnh thật của simulator (skip trên CI là job đỏ) |
| `SettingsSecretsTests` | 8 | không | Keychain, decode file cài đặt cũ |
| `TextChunkingTests` | 12 | không | tách câu cho TTS |
| `GeminiLiveSmokeTests` | 3 | không | Gemini thật; skip nếu không bật `live_gemini` |

### 12.5 Những gì agent không tự kiểm được
- Giao diện (sandbox không có Xcode): giữ view nhỏ, logic hiển thị thành hàm thuần có test, thêm `#Preview`,
  ghi trong PR "Cần chủ dự án xem giao diện (H18)".
- Âm thanh thật, kính, Bluetooth, mic, đèn: §7. Không bao giờ ghi trong PR là đã chạy trên kính.

---

## 13. Prompt mẫu cho agent

Dán nguyên văn, thay phần `<…>`. Gợi ý model: agent làm việc dùng model nhanh; reviewer dùng model mạnh
nhất đang có. Nếu công cụ không cho chọn model thì ghi rõ trong báo cáo là đã dùng model mặc định.

### 13.1 Đợt 2 (một agent, tuần tự)
```
Bạn là coding agent của repo darwnlinz1/Visor-iOS-Solver (app iOS: kính Ray-Ban Meta + Gemini, đọc lời giải
bài tập và đề thi bằng giọng nói). Nhiệm vụ: ĐỢT 2 của PLAN.md.
1. Đọc AGENTS.md, rồi PLAN.md: §0, §3.1, §4.2–4.4, §5 (T2.4, T3.3, T4.1, T4.2, T4.3, T4.4, đặc biệt các mục
   "Phần còn lại (đợt 2)" và "Chi tiết"), §9, §11 (thứ tự đợt 2 và lý do), §12.
2. Tạo branch feature/voice-v2-wave2 từ origin/feature/voice-v2. Sau commit đầu tiên, mở PR vào
   feature/voice-v2 bằng gh api (§9). Không commit vào main, không force push, không amend commit đã push.
3. Thứ tự bắt buộc: T2.4 → T3.3 (nối) → T4.2 (nối) → T4.3 (nối) → T4.1 (nối prompt) → T4.4.
   Mỗi task một commit "Type: …" (≤ 72 ký tự) + dòng "Task: Tx.y". Sau mỗi task: guard 0 failed;
   scripts/swift-local/run.sh xanh nếu đụng Services/Speech/; push; chờ CI và E2E xanh (§9); đọc log E2E,
   kiểm mọi suite có dòng "Executed". Chỉ khi đó mới làm task sau.
4. Giữ bất biến âm thanh (§0.7) và các ký hiệu guard/IPA (§0.8). Khi guard hoặc test cũ khẳng định hành vi cũ,
   sửa check/test trong cùng commit (các chỗ đã liệt kê ở §5). Không thêm dependency.
5. Sau mỗi task, app phải chạy được đầu–cuối với Gemini thật.
6. Bị chặn 2 lần ở cùng một task: dừng và báo cáo theo §10.
7. Khi xong: cập nhật PLAN.md §3.1 và trạng thái task ở §5 (commit "Docs: …"), báo cáo theo §10, ghi trong
   PR "Cần chủ dự án chạy H1, H2, H6, H7, H14, H22". Không merge PR; review đợt 2 làm sau (§13.3).
```

### 13.2 Agent song song (đợt 3–5)
```
Bạn là agent <A|B|C> của đợt <N>, repo darwnlinz1/Visor-iOS-Solver. Đọc AGENTS.md, PLAN.md §0, §11 (bảng chia
việc đợt <N> và quy tắc đợt song song), §12, và các task <Tx.y, …> ở §5.
- Worktree: <đường dẫn>, branch feature/voice-v2-<tên> (tạo từ origin/feature/voice-v2). Mọi lệnh chạy với cwd
  là worktree này. Không đụng worktree khác hay thư mục repo chính.
- Chỉ được sửa/tạo: <danh sách file>. Không sửa PLAN.md, file của agent khác, project.pbxproj
  <trừ: agent có PR được đăng ký file của chính mình bằng scripts/pbxproj_files.py>.
- <Agent không có PR>: chỉ push branch, không mở PR. Kiểm chứng bằng scripts/swift-local/run.sh (0 lỗi, không
  warning mới) và guard (lỗi được phép duy nhất: check "project" cho đúng các file mới của bạn).
- <Agent có PR>: mở PR vào feature/voice-v2; push một lần cho mỗi nhóm commit (workflow có cancel-in-progress);
  chờ CI và E2E xanh (§9).
- Mỗi task một commit "Type: …" + "Task: Tx.y". Stage file theo tên (không git add -A), không amend, không force push.
- Báo cáo: commit (hash + dòng đầu), số test, thay đổi API mà người tích hợp cần biết, việc chưa xong và lý do.
```

### 13.3 Reviewer
```
Bạn là reviewer của đợt <N>, repo darwnlinz1/Visor-iOS-Solver. Tạo worktree tạm từ origin/feature/voice-v2,
git merge --no-ff các branch <…> vào đó, rồi review git diff origin/feature/voice-v2...HEAD theo PLAN.md
(task <…>, §0, §4, §11, §12). Không sửa file nào trong các worktree làm việc hay repo chính; probe đặt dưới
/projects/sandbox/.swift-local/.
Ưu tiên hành vi, và chạy thử chứ không chỉ đọc: câu trả lời Gemini mẫu đi qua cả chuỗi, bảng 4.3 và H13,
streaming (tiền tố, ID ổn định), build iOS có thể vỡ (trùng tên với phần còn lại của app, API mới hơn iOS 18),
guard/CI có che lỗi không (|| true, pipe không pipefail, mã thoát của grep), quy tắc branch, commit, file.
Ghi review ra /projects/sandbox/reviews/wave<N>-review.md: kết luận (APPROVE | APPROVE WITH FIXES |
REQUEST CHANGES); lỗi theo branch; mỗi lỗi có mã, mức (blocker | should-fix | nit), file:dòng, bằng chứng
(đầu vào → kết quả → mong đợi), cách sửa, test cần thêm; mục "Đã kiểm tra, không có lỗi". Tối đa 5 nit.
Trả lời bằng kết luận và số lỗi theo mức cho từng branch.
```

### 13.4 Vòng sửa theo review
```
Bạn là agent <A|B|C> của đợt <N>, vòng sửa. Worktree <…>, branch <…>, chỉ sửa các file của bạn như lần làm.
Đọc /projects/sandbox/reviews/wave<N>-review.md: mục của branch bạn, các lỗi X có owner là bạn, và mục
"Đã kiểm tra, không có lỗi" (không làm hỏng những thứ đó). Sửa mọi blocker và should-fix (nit nếu rẻ).
Mỗi mã lỗi một commit "Fix: …" + "Task: Tx.y (review <mã>)", mỗi lỗi có test so chuỗi chính xác.
Chạy lại kiểm chứng như lần làm, push (agent có PR: chờ CI và E2E xanh).
Báo cáo: commit, số test, mỗi lỗi một dòng "đầu vào → kết quả sau sửa", lỗi chưa sửa và lý do.
```

### 13.5 Người tích hợp
```
Bạn tích hợp đợt <N> vào feature/voice-v2, repo darwnlinz1/Visor-iOS-Solver. Làm đúng 6 bước "Tích hợp" ở
PLAN.md §11. Trước khi gộp, tự kiểm lại mọi lỗi blocker của review bằng probe. Push một lần, chờ CI và E2E
xanh, kiểm từng suite mới có dòng "Executed" trong log E2E. Cập nhật PLAN.md §3.1 và §5 (commit "Docs: …").
Báo cáo theo §10, kèm link PR và các bước H cần chủ dự án chạy (bảng ở §7).
```

### 13.6 Kiểm tra toàn bộ và test đầu–cuối trên Mac
Dùng sau mỗi đợt, trên máy Mac có Xcode của chủ dự án. Thời gian: bước 1–5 khoảng 30–45 phút, bước 6 khoảng
20–30 phút, bước 9 tuỳ số bước H.
```
Bạn là agent kiểm thử chạy trên máy Mac (có Xcode) của chủ dự án. Repo: darwnlinz1/Visor-iOS-Solver, app iOS
OpenVision (kính Ray-Ban Meta + Gemini, đọc lời giải bài tập và đề thi bằng giọng nói). Sandbox Linux trước đây
không có Xcode, nên việc của bạn là chạy mọi kiểm tra cần Mac, ghi số liệu thật và báo lỗi có bằng chứng.

QUY TẮC
- Lượt này chỉ kiểm tra: không sửa code app, không commit, không push, không mở PR, không chạy `xcodegen generate`.
- Mọi file bạn tạo (probe, log, build, audio, báo cáo) nằm trong ~/openvision-check/. Cuối lượt
  `git status --porcelain` trong repo phải rỗng.
- Bí mật: API key Gemini chỉ đi qua biến môi trường, nhập bằng `read -rs` (không gõ thẳng trong lệnh, không echo,
  không ghi ra file, không đưa vào báo cáo). Không in nội dung Config.xcconfig và OpenVision/Config/Config.swift.
- Một bước bị chặn: ghi lỗi nguyên văn, thử tối đa 2 cách, rồi làm bước sau.
- Lưu log từng bước: `<lệnh> 2>&1 | tee ~/openvision-check/logs/<bước>.log`.

0. CHUẨN BỊ
- Trong repo: `git fetch origin && git switch feature/voice-v2 && git pull --ff-only`; ghi `git rev-parse --short HEAD`.
- Đọc AGENTS.md, rồi PLAN.md §0, §3.1, §4.2–4.4, §7, §12.
- Ghi môi trường: `sw_vers`, `xcodebuild -version` (CI dùng Xcode 26.6), `xcrun simctl list runtimes` (cần iOS 18+),
  `swift --version`, `python3 --version`. Tuỳ chọn: `brew install xcbeautify`.
- `mkdir -p ~/openvision-check/logs`. Lần build đầu tải Swift package (Meta DAT), mất vài phút.

1. GUARD VÀ SCRIPT (số mong đợi lấy từ CI ở 159bb7a)
- `python3 scripts/blueprint/verify_blueprint.py` → "44 passed/warned, 0 failed" (một WARN về build-ipa.yml là bình thường).
- `python3 scripts/pbxproj_files.py --self-test` → pass.

2. MODULE THUẦN (OpenVision/Services/Speech) TRÊN macOS
- `scripts/swift-local/run.sh` → "Executed 143 tests, with 0 failures". Ghi mọi warning của các file Speech.

3. BUILD iOS
a) Như CI (thiết bị, Debug, không ký):
     xcodebuild build-for-testing -project OpenVision.xcodeproj -scheme OpenVision \
       -destination 'generic/platform=iOS' -clonedSourcePackagesDirPath .spm \
       -derivedDataPath ~/openvision-check/DD-device-ci -skipPackagePluginValidation -skipMacroValidation \
       CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
   CI ghi 0 warning. Liệt kê mọi warning trong code của app (file:dòng, nội dung), bỏ qua package bên thứ ba.
b) Release + IPA như .github/workflows/build-ipa.yml: lệnh trên đổi thành `xcodebuild build … -configuration Release`
   với `-derivedDataPath ~/openvision-check/DD-release`; rồi trong ~/openvision-check/ipa/ tạo Payload/, chép
   OpenVision.app vào, `zip -qry OpenVision.ipa Payload`. Ghi kích thước IPA. Chạy
   `make verify-ipa IPA=$HOME/openvision-check/ipa/OpenVision.ipa`: phải thấy đủ RecentPhotoScanner, cleanSpokenAudio,
   conversationHistory, PhotoPayload, streamGenerateContent, SolverIntent.

4. E2E TRÊN SIMULATOR, MỌI SUITE
- `make e2e` (script tự chọn iPhone iOS 18+ mới nhất; muốn chọn máy khác thì đặt SIMULATOR_UDID).
- Mong đợi như CI: "Test suites: all"; 13 suite; "Executed 218 tests, with 3 tests skipped and 0 failures" (3 skip là
  GeminiLiveSmokeTests, chạy ở bước 5); 3 test BlueprintPhotoLibraryE2ETests chạy thật; lần khởi động không SDK in
  "SDK kính chưa khởi tạo được".
- Lập bảng từng suite (số test, lỗi, skip, thời gian) từ
  `grep -E "Test Suite '|Executed [0-9]+ tests" build/test-output.log`.
- Test lỗi: ghi tên, thông báo, file:dòng; chạy lại riêng suite đó một lần (`xcodebuild test-without-building` với các
  tham số COMMON trong scripts/e2e/run-simulator-tests.sh và `-only-testing:OpenVisionTests/<Suite>`) để biết lỗi ổn
  định hay chập chờn.

5. GEMINI THẬT: SMOKE TEST CÓ SẴN
     read -rs OV_KEYS        # dán key; nhiều key cách nhau bằng dấu phẩy
     export OV_KEYS
     TEST_RUNNER_OPENVISION_GEMINI_API_KEYS="$OV_KEYS" make e2e-live
- Mong đợi: GeminiLiveSmokeTests chạy 3 test, không skip, pass. Trước đợt 2, các test này kiểm hợp đồng CŨ
  (SPOKEN/DISPLAY) vì app chưa nối prompt v2.1; như vậy là đúng.

6. PROMPT v2.1 VÀ MODULE MỚI VỚI GEMINI THẬT (bước quan trọng nhất)
Trước đợt 2, app chưa gọi PromptV2, AnswerFormat, ReplyAssembler, VietMathSpeech. Bước này kiểm với model thật rằng
chuỗi "prompt v2.1 → Gemini → AnswerFormat → ReplyAssembler → VietMathSpeech" cho câu đọc đúng.
Dựng probe ngoài repo:
- ~/openvision-check/prompt-probe/Package.swift: swift-tools-version 5.9, platforms [.macOS(.v13)], một executableTarget
  "PromptProbe".
- Sources/PromptProbe/: symlink mọi file <repo>/OpenVision/Services/Speech/*.swift (để dùng được kiểu internal) và
  main.swift của bạn. Chạy bằng `swift run -c release PromptProbe`.
- Gửi request giống app (GeminiLiveService.makeRequestBody và userTurn):
  POST https://generativelanguage.googleapis.com/v1beta/models/<model>:streamGenerateContent?alt=sse, header
  x-goog-api-key = key đầu tiên trong OV_KEYS. Body:
    systemInstruction.parts[0].text = PromptV2.systemPrompt(now: Date(), timeZone: .current, userPrompt: "", memories: [:])
    contents = các lượt trước (nếu có) + {"role":"user","parts":[ảnh nếu có, {"text": câu hỏi}]}
      ảnh: {"inlineData":{"mimeType":"image/jpeg","data":"<base64>"},"mediaResolution":{"level":"MEDIA_RESOLUTION_ULTRA_HIGH"}}
      lượt model trong lịch sử: {"role":"model","parts":[{"text": câu trả lời}, {"text":"","thoughtSignature": chữ ký nếu có}]}
    generationConfig = {"temperature":0.2,"maxOutputTokens":8192,"thinkingConfig":{"thinkingLevel":"LOW"}}
  Model gemini-3.5-flash-lite; nếu 404 hoặc hết quota thì gemini-3.1-flash-lite. Nếu HTTP 400 nhắc tới mediaResolution,
  gửi lại không có trường đó. Ảnh thu nhỏ như app: `sips -Z 3072 -s format jpeg -s formatOptions 85 in.jpg --out out.jpg`.
- Đọc SSE: dòng "data: {…}" → candidates[0].content.parts[*].text (bỏ part có "thought": true), thoughtSignature,
  candidates[0].finishReason.
- Mỗi lần nhận thêm chữ: AnswerFormat.partialAnswer(in: accumulated). Cuối: AnswerFormat.parse(raw, finishReason:) →
  ReplyAssembler(languageCode:).plan(turnID: UUID(), parsed:) → mỗi đoạn qua
  VietMathSpeech.render(segment.speechText, vietnamese:, style: .default) và VietMathSpeech.spokenText(_:).
  languageCode = "vi" nếu câu hỏi có chữ tiếng Việt có dấu, ngược lại "en".
- Mỗi ca chạy 2 lần. Lưu cho mỗi lần: câu trả lời thô, loại bài, các đoạn (kind, displayText, speechText), câu đọc từng
  đoạn, kết quả từng kiểm tra.
Kiểm tra cho mỗi câu trả lời:
  K1 Dòng không rỗng đầu tiên là "TYPE: MCQ|ESSAY|MIXED|OTHER", và loại parse ra đúng loại mong đợi.
  K2 MCQ: chỉ có dòng Q (không P, L hay lời giải thích); mỗi đáp án là chữ cái, danh sách Đ/S, một số, hoặc "?".
  K3 ESSAY: mỗi dòng L ≤ 25 từ và ≤ 2 công thức $…$; có FINAL; không "$$", không markdown (**, #, gạch đầu dòng, bảng).
  K4 Không nhắc màn hình hay điện thoại (không khớp /màn hình|điện thoại|screen|phone/i).
  K5 Đúng ngôn ngữ: hỏi tiếng Việt thì nội dung tiếng Việt có dấu; hỏi tiếng Anh thì tiếng Anh.
  K6 Câu đọc: không có \ $ { } ^ _; mỗi mẩu ≤ 200 ký tự; câu tiếng Việt không có "equals", "squared", "over", "plus", "minus".
  K7 Stream: sections của mỗi partialAnswer là tiền tố của sections cuối; loại bài đã biết thì không đổi.
  K8 Đáp số đúng như cột "Đáp án".
  K9 Ca CAPTURE: parsed.requestsCapture == true và không có đoạn nào để đọc. Ca END: parsed.endsConversation == true và
     "[[END]]" không có trong câu đọc nào.
Các ca (gửi nguyên văn):
  #   | Câu hỏi | Loại mong đợi | Đáp án
  1   | Giải giúp mình: Câu 1. Nghiệm của phương trình 2x − 4 = 0 là A. x = 1  B. x = 2  C. x = −2  D. x = 4. Câu 2. Giá trị của log₂ 8 là A. 2  B. 3  C. 4  D. 8. | MCQ | Q1: B; Q2: B
  2   | Câu 1 (đúng/sai). Cho hàm số f(x) = x² − 4x + 3. a) f(1) = 0. b) Hàm số đồng biến trên khoảng (−∞; 2). c) Đồ thị cắt trục Oy tại điểm (0; 3). d) Giá trị nhỏ nhất của f(x) là −2. | MCQ | a Đ, b S, c Đ, d S
  3   | Câu 1 (trả lời ngắn). Tính tích phân từ 0 đến 2 của (2x + 1) dx. | MCQ | 6
  4   | Giải phương trình x² − 5x + 6 = 0, trình bày tự luận. | ESSAY | x = 2; x = 3
  5   | Giải phương trình x² − 4x + 3 = 0 bằng công thức nghiệm thu gọn. | ESSAY | Δ' = 1; x = 1; x = 3
  6   | Tìm giá trị lớn nhất và nhỏ nhất của hàm số y = x³ − 3x + 1 trên đoạn [0; 2]. | ESSAY | lớn nhất 3 tại x = 2; nhỏ nhất −1 tại x = 1
  7   | Trong mặt phẳng Oxy cho A(1; 2), B(3; −2). Tìm toạ độ véc-tơ AB và độ dài đoạn AB. | ESSAY | (2; −4); 2√5
  8   | Giải chi tiết từng bước: tính đạo hàm của y = sin x · cos x. | ESSAY, có đáp số (không giấu đáp án) | y' = cos 2x
  9   | Câu 1. 3 + 4 × 2 bằng A. 14  B. 11  C. 10  D. 9. Bài 2. Giải hệ phương trình x + y = 3 và x − y = 1. | MIXED | Q1: B; x = 2, y = 1
  10  | Question 1. What is the derivative of x^3? A. 3x  B. x^2  C. 3x^2  D. 3x^3 | MCQ (tiếng Anh) | C
  11  | Solve 2x + 3 = 11 step by step. | ESSAY (tiếng Anh) | x = 4
  12  | Thủ đô của Pháp là gì? | OTHER | Paris
  13  | Giải câu này giúp mình. (không gửi ảnh) | CAPTURE (K9) | -
  14  | Cảm ơn nhé, tạm biệt. | END (K9) | -
  15  | Hai lượt: gửi ca 1, rồi gửi kèm lịch sử câu "Tại sao câu 2 chọn B?" | lượt 2: ESSAY | log₂ 8 = 3
  16+ | Ảnh đề thật nếu chủ dự án đặt trong ~/openvision-check/photos/, câu hỏi "Giải hết các câu trong ảnh." | MCQ hoặc MIXED | chủ dự án đối chiếu
Tổng kết bước 6: bảng ca × K1–K9 (✅/❌), tỉ lệ đúng đáp số, và mọi ❌ kèm câu trả lời thô.

7. NGHE THỬ CÁCH ĐỌC (tuỳ chọn; giọng macOS gần với iOS)
- `say -v '?' | grep -i vi_VN` (thường là Linh). Dùng probe lấy VietMathSpeech.spokenText cho 15 mẫu H13 (PLAN.md §7) và
  câu đọc của ca 1, 4, 5; tạo file `say -v Linh -o ~/openvision-check/audio/<tên>.aiff "<câu>"`.
- Chủ dự án nghe và ghi chỗ đọc sai hoặc khó nghe. Đây là dữ liệu cho spike S7.

8. ĐỘ PHỦ, SANITIZER, ẢNH MÀN HÌNH (tuỳ chọn, trên simulator)
- Độ phủ: `xcodebuild test` với tham số COMMON của scripts/e2e/run-simulator-tests.sh (UDID lấy từ dòng "Simulator:"
  trong log bước 4), thêm `-enableCodeCoverage YES -resultBundlePath ~/openvision-check/Coverage.xcresult`; rồi
  `xcrun xccov view --report ~/openvision-check/Coverage.xcresult`. Liệt kê độ phủ theo file của app, đánh dấu file dưới
  20%. Test Ảnh có thể skip ở lượt này (không có bước cấp quyền): chấp nhận.
- Thread Sanitizer: như trên nhưng `-enableThreadSanitizer YES` (không bật chung với độ phủ). Ghi mọi cảnh báo data race.
- Ảnh màn hình: chủ dự án mở app trong Simulator, đi qua onboarding, Cài đặt, Lịch sử; bạn chụp bằng
  `xcrun simctl io <UDID> screenshot ~/openvision-check/screens/<tên>.png`. Đây là mốc trước khi làm lại giao diện.

9. iPHONE THẬT VÀ KÍNH (cùng chủ dự án)
- Chủ dự án điền Config.xcconfig và OpenVision/Config/Config.swift thật (PLAN.md §8). Không in các giá trị này.
- Build và cài: dễ nhất là Xcode (chọn iPhone, bấm Run); debug console của Xcode thấy cả print lẫn NSLog. Dòng lệnh:
  `xcrun devicectl list devices`; `xcodebuild -project OpenVision.xcodeproj -scheme OpenVision -configuration Debug
  -destination 'platform=iOS,id=<UDID>' -allowProvisioningUpdates -derivedDataPath ~/openvision-check/DD-device
  -clonedSourcePackagesDirPath .spm -skipPackagePluginValidation -skipMacroValidation build`; rồi
  `xcrun devicectl device install app --device <UDID> ~/openvision-check/DD-device/Build/Products/Debug-iphoneos/OpenVision.app`.
- Bắt buộc: các bước H trong bảng "Chạy bước nào sau đợt nào" (PLAN.md §7) cho đợt vừa xong; sau đợt 1 là H1 và H9.
  Thêm cho đợt 1: lần khởi động bình thường không có dòng "SDK kính chưa khởi tạo được", và Cài đặt → Kính →
  Đăng ký app vẫn chạy (T2.5 đã đổi cách GlassesManager lấy SDK).
- Tuỳ chọn, làm mốc trước đợt 2: H2–H12 trên bản hiện tại (app vẫn đọc theo định dạng cũ).
- Mỗi bước H: hướng dẫn chủ dự án từng thao tác, ghi kết quả theo mẫu báo cáo phần cứng ở PLAN.md §7, lưu log (Xcode
  debug console hoặc Console.app lọc process OpenVision) vào ~/openvision-check/logs/.

10. BÁO CÁO: ~/openvision-check/REPORT.md
  1. Môi trường: macOS, Xcode, runtime simulator, commit, iPhone và iOS, firmware kính (nếu có).
  2. Bảng tổng: bước 1–9 → ✅, ❌ hoặc bỏ qua (lý do); số liệu chính (số test, warning, kích thước IPA, thời gian).
  3. Lỗi, mỗi lỗi một mục: mã M1, M2…; mức (blocker = đọc sai đáp án, crash, hỏng build, test đỏ; should-fix; nit);
     module; bằng chứng (lệnh; đầu vào → kết quả → mong đợi; trích log); cách tái hiện; file:dòng nếu biết; gợi ý sửa.
  4. Bảng bước 6 và đánh giá: model có theo định dạng v2.1 đủ tốt để làm đợt 2 không; prompt cần sửa gì (trích nguyên
     văn câu trả lời sai).
  5. Kết quả phần cứng theo mẫu PLAN.md §7.
  6. Danh sách file trong ~/openvision-check/ để chủ dự án gửi lại.
Cuối lượt: `git status --porcelain` trong repo phải rỗng; trả lời bằng bảng tổng và danh sách lỗi.
```
Sau đợt 2, các con số mong đợi ở bước 1, 2, 4, 5 đổi theo PR của đợt đó; cập nhật chúng ở đây khi tích hợp.
