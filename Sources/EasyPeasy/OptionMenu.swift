import SwiftUI

/// A labelled dropdown row, e.g. "Language   English ⌄". Clicking the value
/// opens a menu listing every case of the option.
struct OptionMenu<Option>: View
where Option: CaseIterable & Identifiable & Hashable, Option.AllCases: RandomAccessCollection {
    let label: String
    @Binding var selection: Option
    let title: (Option) -> String

    init(label: String, selection: Binding<Option>, title: @escaping (Option) -> String) {
        self.label = label
        self._selection = selection
        self.title = title
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))

            Spacer(minLength: 4)

            Menu {
                Picker(label, selection: $selection) {
                    ForEach(Option.allCases) { option in
                        Text(title(option)).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text(title(selection))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel(label)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}
