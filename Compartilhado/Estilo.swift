import SwiftUI
import UIKit
import PrumoKit

/// Marfim no fundo, grafite para leitura e verde-petróleo para as ações.
/// Compilado no app e na extensão.
enum Paleta {
    static let papel = Color.dinamica(claro: 0xF6F4ED, escuro: 0x111916)
    static let superficie = Color.dinamica(claro: 0xFBFAF6, escuro: 0x18221E)
    static let tinta = Color.dinamica(claro: 0x202D27, escuro: 0xE8EBE2)
    static let suave = Color.dinamica(claro: 0x58665C, escuro: 0xA3B0A6)
    static let linha = Color.dinamica(claro: 0xD8D9CE, escuro: 0x2D3B35)
    static let linhaForte = Color.dinamica(claro: 0xBFC5B9, escuro: 0x3E4E47)
    static let acao = Color.dinamica(claro: 0x20544A, escuro: 0x8FC3B3)
    static let realce = Color.dinamica(claro: 0xE5EAE0, escuro: 0x22312B)
    static let erro = Color.dinamica(claro: 0x8A332D, escuro: 0xF0A49B)

    // Cartão de leitura: verde-petróleo nos dois modos.
    static let floresta = Color(hex: 0x183F38)
    static let florestaClara = Color(hex: 0x285247)
    static let claro = Color(hex: 0xFBF8ED)
    static let claroSuave = Color(hex: 0xCBD9CD)
    static let ouro = Color(hex: 0xD9D3A8)
    static let filete = Color(hex: 0x527064)

    static var gradienteDeLeitura: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0x183C35), Color(hex: 0x163B34), Color(hex: 0x1B4139)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    static func dinamica(claro: UInt32, escuro: UInt32) -> Color {
        Color(UIColor { tracos in
            UIColor(hex: tracos.userInterfaceStyle == .dark ? escuro : claro)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    /// Serifada para a frase; escala com o texto dinâmico a partir do estilo de referência.
    static func frase(_ estilo: Font.TextStyle = .largeTitle) -> Font {
        .system(estilo, design: .serif)
    }
}

extension Frase {
    /// "Epicteto · Manual • Epicteto" para trechos históricos.
    var atribuicao: String? {
        guard isHistorica, let autor else { return nil }
        guard let obra, !obra.isEmpty else { return autor }
        return obra.localizedCaseInsensitiveContains(autor) ? obra : "\(autor) · \(obra)"
    }
}
