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
        Button(action: select) {
            HStack {
                Text(option.displayText)
                    .font(.interfaceSystem(size: 14, weight: .regular))
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, InterfaceScale.metric(8))
                    .padding(.vertical, InterfaceScale.metric(4))
                    .background(
                        Color.primary.opacity(isSelected ? 0.22 : 0.08),
                        in: RoundedRectangle(cornerRadius: InterfaceScale.metric(4), style: .continuous)
                    )
                Spacer()
            }
            .padding(.horizontal, InterfaceScale.metric(12))
            .frame(height: InterfaceScale.metric(34))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FlatTimeOption: Identifiable {
    let candidateIndex: Int
    let option: DiscordParsedTimeCandidate.Option
    let flatIndex: Int
    var id: String { option.id }
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
            for option in candidate.options {
                result.append(FlatTimeOption(candidateIndex: cIndex, option: option, flatIndex: flat))
                flat += 1
            }
        }
        return result
    }

    var body: some View {
        ComposerAutocompletePanel(heading: heading, cornerRadius: cornerRadius) {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(candidates.indices, id: \.self) { cIndex in
                            if cIndex > 0 {
                                Divider()
                                    .padding(.horizontal, InterfaceScale.metric(12))
                                    .padding(.vertical, InterfaceScale.metric(4))
                            }
                            ForEach(candidates[cIndex].options) { option in
                                if let flatIndex = allOptions.first(where: { $0.option.id == option.id })?.flatIndex {
                                    TimeFormatRow(
                                        option: option,
                                        isSelected: selectedIndex == flatIndex,
                                        select: { select(option) }
                                    )
                                    .id(option.id)
                                    .onHover { isHovered in
                                        if isHovered { highlight(flatIndex) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, InterfaceScale.metric(4))
                }
                .frame(maxHeight: InterfaceScale.metric(220))
                .onChange(of: keyboardSelectionRevision) { _, _ in
                    if allOptions.indices.contains(selectedIndex) {
                        proxy.scrollTo(allOptions[selectedIndex].option.id, anchor: .center)
                    }
                }
            }
        }
    }
}
