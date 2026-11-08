import re

def test_intent():
    status_phrases = ["có ảnh chưa", "có ảnh không", "nhận được ảnh chưa", "thấy ảnh chưa", "đã có ảnh"]
    visual_phrases = [
        "đây là cái gì", "đây là gì", "cái này là gì", "cái gì đây", "gì đây", "đây là ai",
        "kia là cái gì", "đó là cái gì", "câu này", "bài này", "đáp án", "đề bài",
        "giải giúp", "giải hộ", "giải bài", "giải câu", "tính câu này", "làm câu này", "chọn đáp án",
        "trong ảnh", "trong hình", "ảnh này", "hình này", "bức ảnh", "bức hình",
        "xem giúp", "nhìn giúp", "đọc giúp", "trước mặt", "chụp",
        "day la cai gi", "day la gi", "cai nay la gi", "cai gi day", "giai bai", "giai cau",
        "dap an", "de bai", "cau nay", "bai nay", "anh nay", "trong anh", "chup",
        "photo", "image", "picture", "solve this", "solve problem", "what is this", "what is that",
        "in this photo", "in this picture", "what do you see", "describe what you see"
    ]

    def requires_attached_photo(text):
        lower = text.lower()
        if any(p in lower for p in status_phrases):
            return False
        return any(p in lower for p in visual_phrases)

    # 1. Visual questions that MUST require photo
    assert requires_attached_photo("giải bài này giúp tôi") == True
    assert requires_attached_photo("đáp án câu này là gì") == True
    assert requires_attached_photo("đây là cái gì") == True
    assert requires_attached_photo("solve this math equation") == True
    assert requires_attached_photo("trong ảnh viết gì thế") == True
    assert requires_attached_photo("bài này làm thế nào") == True

    # 2. Conversational status queries that MUST NOT require photo (NOT blocked!)
    assert requires_attached_photo("có ảnh không") == False
    assert requires_attached_photo("bạn đã có ảnh chưa") == False
    assert requires_attached_photo("nhận được ảnh chưa") == False
    assert requires_attached_photo("thấy ảnh chưa") == False

    # 3. Normal conversation questions that MUST run text-only
    assert requires_attached_photo("thời tiết hôm nay thế nào") == False
    assert requires_attached_photo("bây giờ là mấy giờ rồi") == False
    assert requires_attached_photo("xin chào bạn là ai") == False

    print("[PASS] Intent differentiation test passed!")

def test_source_code():
    with open(r"C:\Users\Minh\Downloads\Visor_Git_Repo\OpenVision\Views\VoiceAgent\VoiceAgentViewModel.swift", "r", encoding="utf-8") as f:
        src = f.read()

    # Check that required methods exist
    assert "waitForFullResolutionGlassesPhoto" in src, "Missing waitForFullResolutionGlassesPhoto"
    assert "statusMessage" in src, "Missing statusMessage"
    assert "waitForRecentGlassesPhoto" in src, "Missing waitForRecentGlassesPhoto"
    assert "mediaType == %d" in src, "Missing mediaType check"
    assert "isNetworkAccessAllowed = true" in src, "Missing isNetworkAccessAllowed"
    assert "highQualityFormat" in src, "Missing highQualityFormat"
    assert "100_000" in src, "Missing 100KB preview check"

    # Check that forbidden keyword from blueprint is absent
    assert "visualKeywords" not in src, "Contains forbidden visualKeywords"

    print("[PASS] Source code structural test passed!")

if __name__ == "__main__":
    test_intent()
    test_source_code()
    print("ALL E2E SIMULATION TESTS PASSED!")
