import SwiftUI
import AppKit

struct WidgetView: View {
    @ObservedObject var model: WidgetModel

    init(model: WidgetModel) {
        self.model = model
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var isWorking: Bool { model.status.isWorking }
    private var showsUnpeasify: Bool { model.isPeasified && !isWorking }
    private var optionsLocked: Bool { model.isPeasified || isWorking }

    private var buttonTitle: String {
        if isWorking { return "Peasifying…" }
        return model.isPeasified ? "Unpeasify" : "Peasify"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                PeaLogo()
                    .frame(width: 26, height: 26)
                Text("Easy Peasy")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)

            Button(action: { model.buttonTapped() }) {
                Text(buttonTitle)
            }
            .buttonStyle(PeasifyButtonStyle(isDestructive: showsUnpeasify))
            .disabled(isWorking)
            .opacity(isWorking ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.25), value: model.isPeasified)

            // Locked while the page is changed or changing; Unpeasify unlocks them.
            Group {
                ModePicker(selection: $model.mode)

                // One row that swaps with the mode, so the widget keeps its size.
                switch model.mode {
                case .translate:
                    OptionMenu(label: "Language", selection: $model.language) { $0.title }
                case .simplify:
                    OptionMenu(label: "Level", selection: $model.level) { $0.title }
                }
            }
            .disabled(optionsLocked)
            .opacity(optionsLocked ? 0.5 : 1.0)

            // Fixed height so the widget does not resize as the message changes.
            Text(model.status.message)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(model.status.isActionable ? 0.9 : 0.6))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .contentShape(Rectangle())
                .onTapGesture { model.statusTapped() }
        }
        .padding(16)
        .frame(width: 240)
        .background(WidgetBackground())
        .clipShape(cardShape)
        .overlay(
            cardShape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contextMenu {
            Button("Quit Easy Peasy") { NSApp.terminate(nil) }
        }
        .fixedSize()
    }
}

private struct PeasifyButtonStyle: ButtonStyle {
    /// Red "Unpeasify" look instead of the green "Peasify" one.
    var isDestructive: Bool = false

    private var topColor: Color {
        isDestructive ? Color(red: 0.93, green: 0.36, blue: 0.34) : Color(red: 0.36, green: 0.80, blue: 0.38)
    }

    private var bottomColor: Color {
        isDestructive ? Color(red: 0.76, green: 0.20, blue: 0.22) : Color(red: 0.20, green: 0.62, blue: 0.30)
    }

    private var glowColor: Color {
        isDestructive ? Color(red: 0.55, green: 0.12, blue: 0.14) : Color(red: 0.10, green: 0.45, blue: 0.20)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: Color.black.opacity(0.25), radius: 1, x: 0, y: 1)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [topColor, bottomColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                // Inner highlight: bright at the top edge, fading out downward.
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.45),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: glowColor.opacity(0.45), radius: 8, x: 0, y: 4)
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
