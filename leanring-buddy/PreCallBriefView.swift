//
//  PreCallBriefView.swift
//  leanring-buddy
//
//  Floating post-it card shown before a scheduled call.
//  Designed to be visible but non-intrusive — sits top-right, stays on top.
//

import SwiftUI

struct PreCallBriefView: View {
    let brief: PreCallBrief
    let onDismiss: () -> Void

    private var timeLabel: String {
        if brief.minutesUntilCall <= 1 { return "Starting now" }
        return "In \(brief.minutesUntilCall)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pre-call brief")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .tracking(0.6)

                    HStack(spacing: 4) {
                        Text(brief.prospectName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if !brief.company.isEmpty {
                            Text("· \(brief.company)")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(brief.minutesUntilCall <= 2 ? Color.orange : .white.opacity(0.55))

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .background(.white.opacity(0.08))

            // Bullets
            VStack(alignment: .leading, spacing: 8) {
                BriefRow(label: "Rapport", icon: "hand.wave", color: .blue, text: brief.rapport)
                BriefRow(label: "Lead with", icon: "bolt.fill", color: .purple, text: brief.painPoint)
                BriefRow(label: "Expect", icon: "shield.lefthalf.filled", color: .orange, text: brief.likelyObjection)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct BriefRow: View {
    let label: String
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 16, height: 16)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
                    .textCase(.uppercase)
                    .tracking(0.5)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
