// Reybain - ConnectMethodRow.swift
// Option row in a backend's "Connect With" list styled with Reybain obsidian typography tokens.

import SwiftUI

struct ConnectMethodRow: View {
    let title: String
    let summary: String
    let icon: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textPrimary)
                Text(summary)
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundColor(Theme.accent)
        }
        .padding(.vertical, 2)
    }
}
