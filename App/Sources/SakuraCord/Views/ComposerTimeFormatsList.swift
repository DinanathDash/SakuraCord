import MessageRendering
import SwiftUI

struct TimeMentionHelpStrip: View {
    let cancel: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: InterfaceScale.metric(7)) {
            Text("@time")
                .font(.interface(.callout).weight(.semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Text("Refer to a time dynamically in the viewer's time zone")
                .font(.interface(.callout))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: InterfaceScale.metric(8))
            HoverActionButton(
                systemImage: "xmark",
                help: "Cancel time picker",
                diameter: InterfaceScale.metric(22),
                action: cancel
            )
            .foregroundStyle(.secondary)
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
        }
        .padding(.leading, InterfaceScale.metric(15))
        .padding(.trailing, InterfaceScale.metric(8))
        .padding(.top, InterfaceScale.metric(8))
        .padding(.bottom, InterfaceScale.metric(6))
        .accessibilityElement(children: .combine)
    }
}

struct TimeFormatRow: View {
    let option: DiscordParsedTimeCandidate.Option
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        HStack {
            Text(option.displayText)
                .font(.interfaceSystem(size: 13.5, weight: .regular))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, InterfaceScale.metric(8))
                .padding(.vertical, InterfaceScale.metric(4))
                .background(
                    Color.primary.opacity(isSelected ? 0.22 : 0.08),
                    in: RoundedRectangle(cornerRadius: InterfaceScale.metric(4), style: .continuous)
                )
            Spacer()
        }
        .padding(.horizontal, InterfaceScale.metric(8))
        .frame(height: InterfaceScale.metric(34))
        .background(
            isSelected ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: InterfaceScale.metric(4), style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

private struct FlatTimeOption: Identifiable {
    let id: String
    let candidateIndex: Int
    let option: DiscordParsedTimeCandidate.Option
    let flatIndex: Int
    let hasDividerBefore: Bool
}

struct TimeFormatsAutocompleteList: View {
    let heading: String
    let candidates: [DiscordParsedTimeCandidate]
    let selectedIndex: Int
    let highlight: (Int) -> Void
    let select: (DiscordParsedTimeCandidate.Option) -> Void

    var cornerRadius: CGFloat = ChatChromeMetrics.composerCornerRadius
    var keyboardSelectionRevision = 0

    private var allOptions: [FlatTimeOption] {
        var result: [FlatTimeOption] = []
        var flat = 0
        for (cIndex, candidate) in candidates.enumerated() {
            for (oIndex, option) in candidate.options.enumerated() {
                result.append(
                    FlatTimeOption(
                        id: option.id,
                        candidateIndex: cIndex,
                        option: option,
                        flatIndex: flat,
                        hasDividerBefore: cIndex > 0 && oIndex == 0
                    )
                )
                flat += 1
            }
        }
        return result
    }

    var body: some View {
        ComposerAutocompletePanel(heading: heading, cornerRadius: cornerRadius) {
            if candidates.isEmpty {
                HStack {
                    Text("No matching time formats")
                        .font(.interfaceSystem(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, InterfaceScale.metric(14))
                .padding(.vertical, InterfaceScale.metric(10))
            } else {
                ComposerSuggestionList(
                    rows: allOptions,
                    selectedID: allOptions.indices.contains(selectedIndex) ? allOptions[selectedIndex].id : nil,
                    keyboardSelectionRevision: keyboardSelectionRevision,
                    maximumHeight: InterfaceScale.metric(260),
                    rowHeight: { $0.hasDividerBefore ? InterfaceScale.metric(44) : InterfaceScale.metric(34) },
                    highlight: { highlight($0.flatIndex) },
                    activate: { select($0.option) },
                    content: { row in
                        VStack(spacing: 0) {
                            if row.hasDividerBefore {
                                Divider()
                                    .padding(.horizontal, InterfaceScale.metric(10))
                                    .padding(.vertical, InterfaceScale.metric(4))
                            }
                            TimeFormatRow(
                                option: row.option,
                                isSelected: selectedIndex == row.flatIndex,
                                select: { select(row.option) }
                            )
                        }
                    }
                )
            }
        }
    }
}
