import SwiftUI
import PrumoKit

/// Cabeçalho das quatro telas: rubrica, título serifado e um acessório à direita.
struct Cabecalho<Acessorio: View>: View {
    let rubrica: String
    let titulo: String
    @ViewBuilder var acessorio: Acessorio

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Rubrica(rubrica)
                Text(titulo)
                    .font(.system(size: 50, weight: .regular, design: .serif))
                    .tracking(-2.4)
                    .foregroundStyle(Paleta.tinta)
                    .accessibilityAddTraits(.isHeader)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            acessorio
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

extension Cabecalho where Acessorio == EmptyView {
    init(rubrica: String, titulo: String) {
        self.init(rubrica: rubrica, titulo: titulo) { EmptyView() }
    }
}

/// Texto pequeno em caixa alta, como as rubricas do protótipo.
struct Rubrica: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(Paleta.suave)
    }
}

/// Título serifado de seção.
struct Subtitulo: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .font(.frase(.title2))
            .foregroundStyle(Paleta.tinta)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Cartão de superfície com borda fina.
struct Cartao<Conteudo: View>: View {
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { conteudo }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Paleta.linha))
    }
}

/// Botão principal: fundo verde-petróleo, alvo de pelo menos 44 pt.
struct EstiloBotaoCheio: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(Paleta.floresta.opacity(configuration.isPressed ? 0.85 : 1),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// Botão Salvar do cartão de leitura. Rótulo e ícone acompanham o estado salvo.
struct BotaoSalvar: View {
    let salva: Bool
    var sobreFundoEscuro = true
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Label(salva ? "Salva" : "Salvar frase", systemImage: salva ? "bookmark.fill" : "bookmark")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(corDoTexto)
                .background(salva ? corDoFundoSalvo : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(corDaBorda))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(salva ? "Remover frase das salvas" : "Salvar frase")
        .accessibilityAddTraits(salva ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: salva)
    }

    private var corDoTexto: Color {
        if sobreFundoEscuro { return salva ? Paleta.floresta : Paleta.claro }
        return salva ? .white : Paleta.acao
    }

    private var corDoFundoSalvo: Color { sobreFundoEscuro ? Color(hex: 0xF0F1DB) : Paleta.acao }
    private var corDaBorda: Color {
        if sobreFundoEscuro { return salva ? Color(hex: 0xF0F1DB) : Color(hex: 0x8BA293) }
        return salva ? Paleta.acao : Paleta.linhaForte
    }
}

/// Sol ou lua sobre um horizonte, desenhado à mão como no protótipo.
struct EmblemaCeleste: View {
    let periodo: Periodo

    var body: some View {
        Canvas { ctx, tamanho in
            let escala = min(tamanho.width / 124, tamanho.height / 85)
            ctx.scaleBy(x: escala, y: escala)
            let tinta = GraphicsContext.Shading.color(Color(hex: 0xD4CFA1))
            let fosco = GraphicsContext.Shading.color(Color(hex: 0x9AAB89))
            let fraco = GraphicsContext.Shading.color(Color(hex: 0x799781))
            let horizonte: CGFloat = 62

            func linha(_ pontos: [CGPoint], _ cor: GraphicsContext.Shading, _ largura: CGFloat) {
                var p = Path()
                p.addLines(pontos)
                ctx.stroke(p, with: cor, style: StrokeStyle(lineWidth: largura, lineCap: .round, lineJoin: .round))
            }

            for i in 0..<4 {
                let y = horizonte + CGFloat(i) * 3.3
                linha([CGPoint(x: 15 + CGFloat(i) * 9, y: y), CGPoint(x: 103 - CGFloat(i) * 5, y: y)],
                      i == 0 ? fosco : fraco, i == 0 ? 0.8 : 0.55)
            }

            switch periodo {
            case .manha, .tarde:
                let centro = CGPoint(x: 69, y: periodo == .manha ? 58 : 40)
                let raio: CGFloat = periodo == .manha ? 15 : 12
                var recorte = ctx
                recorte.clip(to: Path(CGRect(x: 0, y: 0, width: 124, height: horizonte - 0.4)))
                recorte.stroke(Path(ellipseIn: CGRect(x: centro.x - raio, y: centro.y - raio, width: raio * 2, height: raio * 2)),
                               with: tinta, lineWidth: 0.9)
                for k in 0..<17 {
                    let a = Double(-165 + k * 20) * .pi / 180
                    let r = raio + 4
                    let comprimento: CGFloat = k % 2 == 1 ? 4 : 7
                    var p = Path()
                    p.move(to: CGPoint(x: centro.x + r * cos(a), y: centro.y + r * sin(a)))
                    p.addLine(to: CGPoint(x: centro.x + (r + comprimento) * cos(a), y: centro.y + (r + comprimento) * sin(a)))
                    recorte.stroke(p, with: fosco, style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
                }
            case .noite, .madrugada:
                let cx: CGFloat = periodo == .noite ? 78 : 64
                let cy: CGFloat = periodo == .noite ? 36 : 32
                var lua = Path()
                lua.move(to: CGPoint(x: cx + 4, y: cy - 11))
                lua.addCurve(to: CGPoint(x: cx, y: cy + 12), control1: CGPoint(x: cx - 11, y: cy - 10), control2: CGPoint(x: cx - 14, y: cy + 8))
                lua.addCurve(to: CGPoint(x: cx + 11, y: cy + 7), control1: CGPoint(x: cx + 6, y: cy + 13), control2: CGPoint(x: cx + 9, y: cy + 11))
                lua.addCurve(to: CGPoint(x: cx + 4, y: cy - 11), control1: CGPoint(x: cx - 1, y: cy + 9), control2: CGPoint(x: cx - 5, y: cy - 4))
                ctx.stroke(lua, with: tinta, lineWidth: 1)
                for (sx, sy, r) in [(43.0, 33.0, 2.2), (95.0, 19.0, 1.9), (89.0, 49.0, 1.4), (54.0, 19.0, 0.9)] {
                    linha([CGPoint(x: sx - r, y: sy), CGPoint(x: sx + r, y: sy)], fosco, 0.65)
                    linha([CGPoint(x: sx, y: sy - r), CGPoint(x: sx, y: sy + r)], fosco, 0.65)
                }
            }
            linha([CGPoint(x: 25, y: 55), CGPoint(x: 37, y: 53), CGPoint(x: 49, y: 55), CGPoint(x: 61, y: 52)], fraco, 0.55)
        }
        .accessibilityHidden(true)
    }
}

enum Formatos {
    static let locale = Locale(identifier: "pt_BR")

    /// "Quarta-feira, 18 de novembro"
    static func dataLonga(_ data: Date) -> String {
        let texto = data.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    /// "18 de nov."
    static func dataCurta(_ data: Date) -> String {
        data.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "Qua., 18 de nov." para a Tela Bloqueada.
    static func dataDoBloqueio(_ data: Date) -> String {
        let texto = data.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
            .replacingOccurrences(of: ".", with: "")
        return texto.prefix(1).uppercased() + texto.dropFirst()
    }

    /// "11:38"
    static func hora(_ data: Date) -> String {
        data.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }
}
