import AppKit
import SwiftUI

/// Tokens do Design System V2 (protótipo: design/prototipo/boards, cabeçalho `:root` / `[data-theme]`).
/// Cores são dinâmicas (claro/escuro) via NSColor com dynamicProvider.
enum DesignTokens {

    // MARK: Cores

    enum Colors {
        /// Cor dinâmica a partir de dois hex (0xRRGGBB): claro e escuro.
        static func dynamic(light: UInt32, dark: UInt32) -> Color {
            let ns = NSColor(name: nil, dynamicProvider: { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor.vdHex(isDark ? dark : light)
            })
            return Color(nsColor: ns)
        }

        // Superfícies
        static let bgWindow = dynamic(light: 0xF7F6F3, dark: 0x1B1A19)
        static let bgSidebar = dynamic(light: 0xEEECE7, dark: 0x222120)
        static let surface100 = dynamic(light: 0xFFFFFF, dark: 0x2A2927)
        static let surface200 = dynamic(light: 0xF2F0EB, dark: 0x33322F)
        static let surface300 = dynamic(light: 0xE7E4DD, dark: 0x3E3C39)
        static let line = dynamic(light: 0xE2DED6, dark: 0x393735)
        static let lineStrong = dynamic(light: 0x8F897F, dark: 0x7F7A72)

        // Texto
        static let ink = dynamic(light: 0x1B1A19, dark: 0xF4F1EC)
        static let inkMuted = dynamic(light: 0x625D55, dark: 0xB5AFA6)
        static let inkFaint = dynamic(light: 0x6E6960, dark: 0xA39C93)

        // Marca (humano)
        static let brand = dynamic(light: 0xF2701F, dark: 0xFF8A3D)
        static let brandHover = dynamic(light: 0xDC6114, dark: 0xFFA062)
        static let onBrand = dynamic(light: 0x1B1A19, dark: 0x1B1A19)
        static let brandSoft = dynamic(light: 0xFFE7D5, dark: 0x4A2A14)
        static let brandText = dynamic(light: 0xA84708, dark: 0xFFA468)

        // IA
        static let ai = dynamic(light: 0x12A39B, dark: 0x3CC8C0)
        static let aiSoft = dynamic(light: 0xD5F3F0, dark: 0x163B39)
        static let aiText = dynamic(light: 0x0A6A65, dark: 0x6ADBD3)

        // Semânticas
        static let fix = dynamic(light: 0xB42F29, dark: 0xFF7A72)
        static let fixSoft = dynamic(light: 0xFDE2DF, dark: 0x4A1F1D)
        static let change = dynamic(light: 0x2A5FC7, dark: 0x86AFFF)
        static let changeSoft = dynamic(light: 0xE1EAFD, dark: 0x1D2A47)
        static let remove = dynamic(light: 0x9C2F79, dark: 0xE88ACB)
        static let removeSoft = dynamic(light: 0xF8E1F0, dark: 0x43203A)
        static let done = dynamic(light: 0x1D7A4A, dark: 0x5CCB8F)
        static let doneSoft = dynamic(light: 0xDDF3E6, dark: 0x183A28)
        static let neutralSoft = dynamic(light: 0xEBE8E2, dark: 0x3A3835)

        static let focusRing = brand
    }

    // MARK: Espaçamento (--space-N)

    enum Space {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s8: CGFloat = 32
        static let s12: CGFloat = 48
    }

    // MARK: Raios (--radius-*)

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let card: CGFloat = 5
        static let pill: CGFloat = 999
    }

    // MARK: Tipografia (classes .title/.headline/.body/.callout/.caption/.mono)

    enum Typography {
        static let displayXL = Font.system(size: 34, weight: .bold, design: .rounded)
        static let displayLG = Font.system(size: 24, weight: .bold, design: .rounded)
        static let title = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13, weight: .regular)
        static let callout = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 11, weight: .semibold)
        static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: Animação

    enum Motion {
        static let fast: Double = 0.12
        static let base: Double = 0.2
    }
}

extension NSColor {
    /// Cor sRGB a partir de 0xRRGGBB.
    static func vdHex(_ hex: UInt32) -> NSColor {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

/// Tons semânticos (.vd-tone-*): cor do texto/ícone e fundo suave.
enum VDTone {
    case brand, ai, fix, change, remove, done, neutral

    var foreground: Color {
        switch self {
        case .brand: return DesignTokens.Colors.brandText
        case .ai: return DesignTokens.Colors.aiText
        case .fix: return DesignTokens.Colors.fix
        case .change: return DesignTokens.Colors.change
        case .remove: return DesignTokens.Colors.remove
        case .done: return DesignTokens.Colors.done
        case .neutral: return DesignTokens.Colors.inkMuted
        }
    }

    var soft: Color {
        switch self {
        case .brand: return DesignTokens.Colors.brandSoft
        case .ai: return DesignTokens.Colors.aiSoft
        case .fix: return DesignTokens.Colors.fixSoft
        case .change: return DesignTokens.Colors.changeSoft
        case .remove: return DesignTokens.Colors.removeSoft
        case .done: return DesignTokens.Colors.doneSoft
        case .neutral: return DesignTokens.Colors.neutralSoft
        }
    }
}
