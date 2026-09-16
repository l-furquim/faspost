import SwiftUI

protocol GlassSegmentOption: Hashable, Identifiable, CaseIterable {
    var title: LocalizedStringResource { get }
    var systemImage: String { get }
}

struct GlassSegmentedPicker<Option: GlassSegmentOption>: View {
    @Binding var selection: Option
    var accessibilityLabel: LocalizedStringResource
    @Namespace private var selectionNamespace

    var body: some View {
        if #available(macOS 27, *) {
            nativeTabsPicker
        } else if #available(macOS 26, *) {
            glassTabBar
        } else {
            fallbackPicker
        }
    }

    @available(macOS 27, *)
    private var nativeTabsPicker: some View {
        HStack(spacing: 0) {
            Picker(accessibilityLabel, selection: $selection) {
                ForEach(Array(Option.allCases)) { option in
                    Text(option.title)
                        .tag(option)
                }
            }
            .pickerStyle(.tabs)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            .controlSize(.small)
            Spacer(minLength: 0)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var glassTabBar: some View {
        HStack(spacing: 2) {
            ForEach(Array(Option.allCases)) { option in
                GlassTabButton(
                    option: option,
                    isSelected: option == selection,
                    namespace: selectionNamespace
                ) {
                    selection = option
                }
            }
        }
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .animation(.smooth, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var fallbackPicker: some View {
        Picker(accessibilityLabel, selection: $selection) {
            ForEach(Array(Option.allCases)) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct GlassTabButton<Option: GlassSegmentOption>: View {
    let option: Option
    var isSelected: Bool
    var namespace: Namespace.ID
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Label {
                Text(option.title)
            } icon: {
                Image(systemName: option.systemImage)
            }
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                Capsule()
                    .fill(.primary.opacity(0.12))
                    .matchedGeometryEffect(id: "tab-selection", in: namespace)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var pane = RequestPane.params
    GlassSegmentedPicker(selection: $pane, accessibilityLabel: "Section")
        .padding()
}
