# AGENTS.md: hướng dẫn nhanh cho coding agent

Repo `darwnlinz1/Visor-iOS-Solver`, app iOS **OpenVision**. Người đeo kính Ray-Ban Meta bấm chụp đề bài, nói
"Ok Vision" và hỏi; Gemini giải; kính **đọc** lời giải. Trắc nghiệm đọc "Câu 1: A. Câu 2: C.", tự luận đọc từng
dòng có nghỉ, công thức đọc bằng tiếng Việt ("ích bình phương trừ 5 ích cộng 6 bằng 0").

File này chỉ là lối vào. Nguồn sự thật là [PLAN.md](PLAN.md) (tiếng Việt).

## Đọc theo thứ tự
1. `PLAN.md` §0: quy tắc bắt buộc.
2. §3.1: những gì đã xong và ở commit nào.
3. §11: đợt đang làm, thứ tự task, ai sửa file nào.
4. §5: từng task (Việc, Không làm, Xong khi, Chi tiết).
5. §12: cách test. §9: cách đọc CI từ sandbox. §10: mẫu báo cáo. §13: prompt mẫu cho từng vai
   (§13.6: kiểm tra toàn bộ và test đầu–cuối trên máy Mac có Xcode).

Comment trong code mâu thuẫn với `PLAN.md` thì tin `PLAN.md`. `PLAN.md` mô tả sai code hiện có thì tin code
và ghi lại trong PR.

## Trạng thái (22/11/2026)
- Đợt 1 xong: module đọc toán (`VietMathSpeech`), parser định dạng v2.1 (`AnswerFormat`), `ReplyAssembler`,
  prompt v2.1, script pbxproj, E2E chạy mọi suite. Đã tích hợp vào `feature/voice-v2`; PR #4 vào `main`.
- Các module mới **chưa được app gọi**. Việc tiếp theo: đợt 2 (`PLAN.md` §11, prompt ở §13.1).

## Môi trường
- Sandbox Linux, **không có Xcode**. Có Swift 6.3 cho code thuần. Build và test iOS chạy trên GitHub Actions.
- `gh pr create` và `gh run list` không chạy được ở đây: dùng `gh api` (`PLAN.md` §9).
- `/tmp` không giữ file giữa các lệnh: để file tạm dưới `/projects/sandbox/`.

## Lệnh
```bash
python3 scripts/blueprint/verify_blueprint.py            # guard tĩnh: luôn "0 failed"
scripts/swift-local/run.sh                               # build + test Services/Speech bằng SwiftPM trên Linux
scripts/swift-local/run.sh VietMathSpeech                # chỉ các file test có tên chứa chuỗi này
python3 scripts/pbxproj_files.py --dry-run add <file>    # xem trước thay đổi pbxproj
python3 scripts/pbxproj_files.py add <file.swift> ...    # đăng ký file Swift mới vào Xcode project
python3 scripts/pbxproj_files.py remove <file.swift>     # gỡ file
python3 scripts/pbxproj_files.py remove-folder-ref <dir> # gỡ folder reference (ví dụ SolutionRenderer)
make e2e | make e2e-blueprint | make e2e-live            # chỉ trên Mac có Xcode
```

## Quy tắc tóm tắt (đầy đủ ở `PLAN.md` §0)
- Mỗi đợt một branch tạo từ `feature/voice-v2`, PR vào `feature/voice-v2`. Không commit vào `main`, không
  force push, không viết lại lịch sử đã push.
- Một task một commit: `Add: | Fix: | Refactor: | Docs: | Chore: | Test: …` (≤ 72 ký tự), dòng sau
  `Task: Tx.y`. Stage file theo tên, không `git add -A`.
- File Swift mới chỉ đăng ký bằng `scripts/pbxproj_files.py`. Không sửa tay pbxproj, không chạy
  `xcodegen generate` (CI build project đã commit).
- `OpenVision/Services/Speech/` chỉ dùng Foundation, vì nó được biên dịch cả trên Linux.
- Bất biến âm thanh (guard lesson 1–4) không được đổi: một tap mic, cấu hình `AVAudioSession` cố định, chờ
  ≥ 350 ms sau TTS, đặt `.speaking` + `isBargeInPaused = true` trước khi xếp câu nói.
- Không thêm dependency, backend mới, hay danh sách từ khoá đoán ý câu hỏi.
- Không commit hay log API key, `CLIENT_TOKEN`, Team ID. Văn bản của người dùng chỉ được log khi bật
  `verboseLogging`.
- Task xong khi: guard 0 failed, test local xanh (nếu đụng `Services/Speech/`), CI và E2E của commit đó xanh.
- Không bao giờ ghi là đã chạy trên kính. Ghi "Cần chủ dự án chạy H…" theo bảng ở `PLAN.md` §7.
- Bị chặn 2 lần ở cùng một task: dừng và báo cáo theo `PLAN.md` §10.

## Bản đồ nhanh
| Đường dẫn | Nội dung |
|---|---|
| `OpenVision/Services/Speech/` | Code thuần: đọc toán, parser v2.1, mô hình đọc, prompt v2.1 (bảng API ở `PLAN.md` §3.4) |
| `OpenVision/Services/GeminiLive/GeminiLiveService.swift` | Gọi Gemini (REST SSE), retry, lịch sử 6 mục, prompt, `[[CAPTURE]]` / `[[END]]` |
| `OpenVision/Services/TTS/TTSService.swift` | Hàng đợi `AVSpeechSynthesizer`, `cleanSpokenAudio` |
| `OpenVision/Views/VoiceAgent/VoiceAgentViewModel.swift` | Điều phối phiên, ảnh, TTS, lịch sử |
| `OpenVision/Managers/GlassesManager.swift` | Meta DAT: đăng ký, session, camera, nút chụp |
| `OpenVisionTests/` | Mọi suite XCTest (bảng ở `PLAN.md` §12.4) |
| `scripts/` | guard, chạy E2E trên simulator, `pbxproj_files.py`, `swift-local/run.sh` |
| `.github/workflows/` | `ci.yml` (build), `e2e.yml` (guard + simulator), `build-ipa.yml` (IPA, chạy tay) |
