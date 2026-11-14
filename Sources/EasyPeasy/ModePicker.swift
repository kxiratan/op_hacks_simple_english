import SwiftUI

/// Custom segmented pill for switching between `PeasyMode` cases.
struct ModePicker: View {
    @Binding var selection: PeasyMode
    @Namespace private var highlightNamespace

    init(selection: Binding<PeasyMode>) {
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeasyMode.allCases) { mode in
                segment(for: mode)
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    @ViewBuilder
    private func segment(for mode: PeasyMode) -> some View {
        let isSelected = mode == selection

        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selection = mode
            }
        } label: {
            Text(mode.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .matchedGeometryEffect(id: "highlight", in: highlightNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
