import SwiftUI

/// Marca do VibeDeck (componente Logo do DS, prancha 00): dois cartões em V, o da frente é o humano (tangerina)
/// e o de trás é a IA (lagoa). Mesmas polilinhas de `scripts/make-icon.swift`, em um espaço de 64 x 64.
struct VDLogoShape: Shape {
    let outline: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scale = min(rect.width, rect.height) / 64
        let tokens = outline.split(separator: " ")
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "Z" {
                path.closeSubpath()
                index += 1
                continue
            }
            guard index + 1 < tokens.count,
                  let x = Double(token.dropFirst()),
                  let y = Double(tokens[index + 1]) else { break }
            let point = CGPoint(x: rect.minX + CGFloat(x) * scale, y: rect.minY + CGFloat(y) * scale)
            if token.hasPrefix("M") { path.move(to: point) } else { path.addLine(to: point) }
            index += 2
        }
        return path
    }
}

struct VDLogo: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            VDLogoShape(outline: Self.back).fill(DesignTokens.Colors.ai)
            VDLogoShape(outline: Self.front).fill(DesignTokens.Colors.brand)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let back = "M44.20 12.79 L43.74 12.63 L43.26 12.51 L42.78 12.44 L42.29 12.42 L41.80 12.45 L41.31 12.53 L40.84 12.65 L40.38 12.82 L39.93 13.04 L39.52 13.29 L39.12 13.59 L38.76 13.92 L38.44 14.29 L38.15 14.68 L37.90 15.11 L37.69 15.55 L33.62 25.64 L40.33 42.24 L40.38 42.38 L40.54 42.84 L40.62 43.13 L40.74 43.60 L40.79 43.89 L40.86 44.38 L40.89 44.67 L40.91 45.16 L40.90 45.46 L40.87 45.95 L40.84 46.24 L40.77 46.72 L40.71 47.01 L40.58 47.49 L40.50 47.77 L40.33 48.23 L40.21 48.50 L40.00 48.94 L39.86 49.20 L39.60 49.62 L39.44 49.86 L39.14 50.25 L38.95 50.48 L38.62 50.84 L38.41 51.05 L38.04 51.37 L37.81 51.56 L37.42 51.85 L37.17 52.01 L36.75 52.26 L36.49 52.39 L36.32 52.47 L36.70 52.49 L37.19 52.46 L37.67 52.38 L38.15 52.26 L38.61 52.09 L39.05 51.88 L39.47 51.62 L39.86 51.33 L40.22 50.99 L40.55 50.63 L40.84 50.23 L41.08 49.81 L41.29 49.36 L52.53 21.55 L52.69 21.08 L52.81 20.61 L52.87 20.12 L52.89 19.63 L52.86 19.14 L52.79 18.65 L52.66 18.18 L52.50 17.72 L52.28 17.28 L52.03 16.86 L51.73 16.47 L51.40 16.11 L51.03 15.78 L50.63 15.49 L50.21 15.24 L49.77 15.04 Z"
    private static let front = "M19.80 12.79 L14.23 15.04 L13.79 15.24 L13.37 15.49 L12.97 15.78 L12.60 16.11 L12.27 16.47 L11.97 16.86 L11.72 17.28 L11.50 17.72 L11.34 18.18 L11.21 18.65 L11.14 19.14 L11.11 19.63 L11.13 20.12 L11.19 20.61 L11.31 21.08 L11.47 21.55 L22.71 49.36 L22.92 49.81 L23.16 50.23 L23.45 50.63 L23.78 50.99 L24.14 51.33 L24.53 51.62 L24.95 51.88 L25.39 52.09 L25.85 52.26 L26.33 52.38 L26.81 52.46 L27.30 52.49 L27.79 52.47 L28.28 52.40 L28.76 52.29 L29.22 52.12 L34.78 49.88 L35.23 49.67 L35.65 49.42 L36.05 49.13 L36.41 48.81 L36.75 48.45 L37.04 48.05 L37.30 47.64 L37.51 47.19 L37.68 46.73 L37.80 46.26 L37.88 45.77 L37.91 45.28 L37.89 44.79 L37.82 44.31 L37.71 43.83 L37.54 43.37 L26.31 15.55 L26.10 15.11 L25.85 14.68 L25.56 14.29 L25.24 13.92 L24.88 13.59 L24.48 13.29 L24.07 13.04 L23.62 12.82 L23.16 12.65 L22.69 12.53 L22.20 12.45 L21.71 12.42 L21.22 12.44 L20.74 12.51 L20.26 12.63 Z"
}
