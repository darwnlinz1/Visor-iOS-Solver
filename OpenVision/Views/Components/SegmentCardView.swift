// OpenVision - SegmentCardView.swift
// Structured v2.1 answer card rendered natively with MathPrettyText (no KaTeX/WebView, PLAN.md §4.5, T6.1).
// Supports MCQ compact grids, numbered essay solution lines, active-segment highlight, live spoken
// phrase highlighting, tap-to-jump playback, and offline "Đọc lại".

import SwiftUI

struct SegmentCardView: View {
    let record: ReadingRecord
    /// Optional card identifier to scope `ScrollViewReader` segment IDs across multi-turn feeds.
    var cardID: String = ""
    /// Index of the currently reading segment (nil if this card is not the active playback target).
    var activeSegmentIndex: Int? = nil
    /// Current spoken piece text and highlighted word range (from ReadingEngine).
    var activeSpokenPiece: String? = nil
    var activeWordRange: NSRange? = nil
    var isReadingActive: Bool = false
    /// Tap any segment to jump reading directly to it.
    var onSelectSegment: ((Int) -> Void)? = nil
    /// Optional button to replay the entire card offline.
    var onReplay: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            cardHeader

            let mcqItems = indexedSegments.filter {
                if case .mcq = $0.segment.kind { return true }
                return false
            }
            let nonMcqItems = indexedSegments.filter {
                if case .mcq = $0.segment.kind { return false }
                return true
            }

            if !mcqItems.isEmpty {
                mcqGrid(mcqItems)
            }

            if !nonMcqItems.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(nonMcqItems, id: \.index) { item in
                        SegmentRow(
                            segment: item.segment,
                            isActive: activeSegmentIndex == item.index,
                            spokenPiece: activeSegmentIndex == item.index ? activeSpokenPiece : nil,
                            wordRange: activeSegmentIndex == item.index ? activeWordRange : nil,
                            isReadingActive: isReadingActive && activeSegmentIndex == item.index
                        ) {
                            onSelectSegment?(item.index)
                        }
                        .id("\(cardID)seg-\(item.segment.id)")
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.bgCard.opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .stroke(
                            activeSegmentIndex != nil ? Theme.accent.opacity(0.45) : Theme.bgElevatedStroke,
                            lineWidth: 1
                        )
                )
        )
    }

    private var indexedSegments: [(index: Int, segment: ReadingSegment)] {
        record.segments.enumerated().map { (index: $0.offset, segment: $0.element) }
    }

    private var cardHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            answerTypeBadge

            Text("\(record.segments.count) mục")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.textSecondary)

            Spacer()

            if let onReplay {
                Button(action: onReplay) {
                    Label("Đọc lại", systemImage: "speaker.wave.2.fill")
                        .font(Theme.Typography.badge)
                        .foregroundColor(.black.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.buttonGradient))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đọc lại câu trả lời này")
            }
        }
    }

    private var answerTypeBadge: some View {
        let (title, icon, tint) = answerTypeMeta
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(Theme.Typography.badge)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(tint.opacity(0.16))
                .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
        )
    }

    private var answerTypeMeta: (String, String, Color) {
        switch record.answerType {
        case .mcq: return ("Trắc nghiệm", "checklist", Theme.accent)
        case .essay: return ("Tự luận", "function", Theme.info)
        case .mixed: return ("Hỗn hợp", "square.grid.2x2", Theme.warning)
        case .other: return ("Trả lời", "text.bubble", Theme.heading)
        }
    }

    private func mcqGrid(_ items: [(index: Int, segment: ReadingSegment)]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 130), spacing: Theme.Spacing.sm)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(items, id: \.index) { item in
                let isActive = activeSegmentIndex == item.index
                Button {
                    onSelectSegment?(item.index)
                } label: {
                    HStack(spacing: 6) {
                        if isActive {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.caption2)
                                .foregroundColor(Theme.accent)
                        }
                        Text(MathPrettyText.format(item.segment.displayText))
                            .font(.subheadline.weight(isActive ? .bold : .semibold))
                            .foregroundColor(isActive ? Theme.accentBright : Theme.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(isActive ? Theme.bgCardHighlight : Theme.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                    .stroke(isActive ? Theme.accent : Theme.bgElevatedStroke, lineWidth: isActive ? 1.5 : 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .id("\(cardID)seg-\(item.segment.id)")
                .accessibilityLabel(item.segment.displayText)
                .accessibilityHint("Chạm để đọc từ mục này")
            }
        }
    }
}

/// Single line / problem / final / notice row inside a `SegmentCardView` (T6.1).
struct SegmentRow: View {
    let segment: ReadingSegment
    let isActive: Bool
    var spokenPiece: String? = nil
    var wordRange: NSRange? = nil
    var isReadingActive: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    if let badge = shortBadge {
                        Text(badge)
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundColor(badgeColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(badgeColor.opacity(0.16))
                            )
                    }

                    Text(MathPrettyText.format(bodyText))
                        .font(textFont)
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if isActive {
                        Image(systemName: isReadingActive ? "speaker.wave.2.fill" : "pause.circle.fill")
                            .font(.caption)
                            .foregroundColor(Theme.accent)
                            .padding(.top, 2)
                    }
                }

                // Live spoken phrase with active word underline (PLAN.md §4.5)
                if isActive, let piece = spokenPiece, !piece.isEmpty {
                    highlightedSpokenLine(piece: piece, range: wordRange)
                        .font(.caption)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(rowBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.displayText)
        .accessibilityHint("Chạm để đọc từ mục này")
    }

    private var shortBadge: String? {
        switch segment.kind {
        case .line(let n): return "D\(n)"
        case .problem(let n): return "B\(n)"
        case .final: return "ĐS"
        case .notice: return "!"
        case .mcq(let n): return "C\(n)"
        case .answer: return nil
        }
    }

    private var badgeColor: Color {
        switch segment.kind {
        case .line: return isActive ? Theme.accentBright : Theme.info
        case .problem: return Theme.heading
        case .final: return Theme.accent
        case .notice: return Theme.warning
        case .mcq: return Theme.accent
        case .answer: return Theme.textSecondary
        }
    }

    private var bodyText: String {
        switch segment.kind {
        case .line(let n):
            for prefix in ["Dòng \(n): ", "Line \(n): "] {
                if segment.displayText.hasPrefix(prefix) {
                    return String(segment.displayText.dropFirst(prefix.count))
                }
            }
            return segment.displayText
        default:
            return segment.displayText
        }
    }

    private var textFont: Font {
        switch segment.kind {
        case .problem: return .subheadline.weight(.bold)
        case .final: return .callout.weight(.semibold)
        case .notice: return .footnote.weight(.medium)
        default: return Theme.Typography.math
        }
    }

    private var textColor: Color {
        switch segment.kind {
        case .final: return Theme.accentBright
        case .notice: return Theme.warning
        default: return Theme.textPrimary
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let fill: Color = {
            if isActive { return Theme.bgCardHighlight }
            if case .final = segment.kind { return Theme.accentMuted }
            if case .notice = segment.kind { return Theme.warning.opacity(0.12) }
            return Color.white.opacity(0.035)
        }()
        let stroke: Color = {
            if isActive { return Theme.accent }
            if case .final = segment.kind { return Theme.accent.opacity(0.45) }
            if case .notice = segment.kind { return Theme.warning.opacity(0.45) }
            return Theme.bgElevatedStroke
        }()
        RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .stroke(stroke, lineWidth: isActive ? 1.5 : 1)
            )
    }

    private func highlightedSpokenLine(piece: String, range: NSRange?) -> Text {
        var attributed = AttributedString(piece)
        attributed.foregroundColor = Theme.textSecondary
        if let range, let swiftRange = Range(range, in: piece),
           let attrRange = Range(swiftRange, in: attributed) {
            attributed[attrRange].foregroundColor = Theme.accentBright
            attributed[attrRange].underlineStyle = .single
        }
        return Text("Đang đọc: ").foregroundColor(Theme.accent) + Text(attributed)
    }
}

#Preview {
    let record = ReadingRecord(
        languageCode: "vi",
        answerType: .mixed,
        segments: [
            ReadingSegment(id: 0, kind: .mcq(1), title: "Câu 1", displayText: "Câu 1: B", speechText: "Câu 1: B."),
            ReadingSegment(id: 1, kind: .mcq(2), title: "Câu 2", displayText: "Câu 2: a Đ, b S", speechText: "Câu 2: a đúng, b sai."),
            ReadingSegment(id: 2, kind: .problem(1), title: "Bài 1", displayText: "Bài 1", speechText: "Bài 1."),
            ReadingSegment(id: 3, kind: .line(1), title: "Dòng 1", displayText: #"Dòng 1: Ta có $\Delta = (-5)^2 - 4 \cdot 6 = 1$."#, speechText: "Dòng 1."),
            ReadingSegment(id: 4, kind: .final, title: "Đáp số", displayText: #"Đáp số: $x_1 = 2$, $x_2 = 3$."#, speechText: "Đáp số.")
        ]
    )
    ZStack {
        Theme.bg.ignoresSafeArea()
        SegmentCardView(
            record: record,
            activeSegmentIndex: 3,
            activeSpokenPiece: "đen-ta bằng âm 5, tất cả bình phương trừ 4 nhân 6 bằng 1",
            activeWordRange: NSRange(location: 12, length: 4),
            isReadingActive: true,
            onReplay: {}
        )
        .padding()
    }
    .preferredColorScheme(.dark)
}
