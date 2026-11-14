import SwiftUI

/// Original pea-pod mark drawn entirely with SwiftUI shapes.
struct PeaLogo: View {
    private static let podFill = Color(red: 0.30, green: 0.66, blue: 0.29)
    private static let podStroke = Color(red: 0.17, green: 0.45, blue: 0.20)
    private static let peaFill = Color(red: 0.66, green: 0.93, blue: 0.45)
    private static let peaStroke = Color(red: 0.36, green: 0.70, blue: 0.28)

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let podWidth = side * 0.96
            let podHeight = side * 0.42
            let pea = side * 0.25
            let spacing = side * 0.025
            let outline = max(0.75, side * 0.05)

            ZStack {
                Capsule(style: .continuous)
                    .fill(Self.podFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Self.podStroke, lineWidth: outline)
                    )
                    .frame(width: podWidth, height: podHeight)

                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Self.peaFill)
                            .overlay(
                                Circle()
                                    .strokeBorder(Self.peaStroke.opacity(0.6), lineWidth: max(0.4, side * 0.02))
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: pea * 0.3, height: pea * 0.3)
                                    .offset(x: -pea * 0.17, y: -pea * 0.17)
                            )
                            .frame(width: pea, height: pea)
                    }
                }
            }
            .rotationEffect(.degrees(-25))
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
