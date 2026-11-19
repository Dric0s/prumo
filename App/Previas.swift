import SwiftUI
import PrumoKit

/// Moldura de iPhone para as prévias. O conteúdo recebe a largura da tela para escalar como no protótipo.
struct Aparelho<Conteudo: View>: View {
    let largura: CGFloat
    @ViewBuilder var conteudo: Conteudo

    var body: some View {
        let altura = largura * 462 / 226
        ZStack {
            RoundedRectangle(cornerRadius: largura * 0.165, style: .continuous)
                .fill(Color(hex: 0x1B201D))
                .overlay(RoundedRectangle(cornerRadius: largura * 0.165, style: .continuous).stroke(Color(hex: 0xB4B8AC), lineWidth: 2))
                .shadow(color: Color(hex: 0x3C4438).opacity(0.18), radius: 10, x: 8, y: 10)
            conteudo
                .frame(width: largura - 8, height: altura - 8)
                .background(PapelDeParede())
                .clipShape(RoundedRectangle(cornerRadius: largura * 0.15, style: .continuous))
                .overlay(alignment: .top) {
                    Capsule().fill(Color(hex: 0x101513))
                        .frame(width: largura * 0.26, height: altura * 0.038)
                        .padding(.top, altura * 0.025)
                }
        }
        .frame(width: largura, height: altura)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
    }
}

/// Paisagem em camadas, inspirada no papel de parede do protótipo.
struct PapelDeParede: View {
    var body: some View {
        Canvas { ctx, tamanho in
            let w = tamanho.width, h = tamanho.height
            ctx.fill(Path(CGRect(origin: .zero, size: tamanho)), with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(hex: 0x203D3B), location: 0),
                    .init(color: Color(hex: 0x365752), location: 0.18),
                    .init(color: Color(hex: 0x63837A), location: 0.38),
                    .init(color: Color(hex: 0xA4AF94), location: 0.54),
                    .init(color: Color(hex: 0xBBB294), location: 0.69),
                    .init(color: Color(hex: 0x3A5349), location: 1),
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)
            ))
            let camadas: [([CGFloat], UInt32)] = [
                ([0.55, 0.53, 0.50, 0.515, 0.46, 0.48, 0.44, 0.43, 0.40], 0x9CAE99),
                ([0.53, 0.54, 0.56, 0.545, 0.565, 0.52, 0.48, 0.46, 0.465], 0x6C887C),
                ([0.555, 0.58, 0.60, 0.62, 0.625, 0.63, 0.60, 0.575, 0.555], 0x536F62),
                ([0.66, 0.69, 0.71, 0.69, 0.67, 0.68, 0.66, 0.645, 0.62], 0x476356),
                ([0.78, 0.80, 0.79, 0.81, 0.775, 0.74, 0.73, 0.695, 0.71], 0x2B443A),
                ([0.87, 0.86, 0.84, 0.82, 0.82, 0.83, 0.855, 0.86, 0.835], 0x243A31),
            ]
            for (indice, (pontos, cor)) in camadas.enumerated() {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h))
                let passos = 60
                for i in 0...passos {
                    let t = CGFloat(i) / CGFloat(passos)
                    let pos = t * CGFloat(pontos.count - 1)
                    let k = min(pontos.count - 2, Int(pos))
                    let mistura = pos - CGFloat(k)
                    let suave = mistura * mistura * (3 - 2 * mistura)
                    let ruido = 0.005 * sin(t * 27 + CGFloat(indice + 1)) + 0.003 * sin(t * 69 + CGFloat(indice * 7))
                    let y = pontos[k] + (pontos[k + 1] - pontos[k]) * suave + ruido
                    p.addLine(to: CGPoint(x: t * w, y: y * h))
                }
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: cor)))
            }
        }
    }
}

/// Fundo listrado claro do palco das prévias.
struct FundoDePalco: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0xE4E5D9), Color(hex: 0xD3D7C9)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(RadialGradient(colors: [Color(hex: 0xECECE1), .clear], center: UnitPoint(x: 0.2, y: 0.14), startRadius: 0, endRadius: 220))
    }
}

/// Tela Bloqueada: data, relógio e o acessório retangular abaixo da hora, à esquerda.
struct TelaBloqueadaPrevia: View {
    let leitura: Leitura
    let agora: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Text(Formatos.dataDoBloqueio(agora))
                    .font(.system(size: w * 0.053, weight: .medium))
                    .frame(width: w)
                    .position(x: w / 2, y: h * 0.12)
                Text(Formatos.hora(agora))
                    .font(.system(size: w * 0.26, weight: .semibold))
                    .monospacedDigit()
                    .tracking(-w * 0.01)
                    .frame(width: w)
                    .position(x: w / 2, y: h * 0.2)
                VStack(alignment: .leading, spacing: w * 0.004) {
                    Text("Prumo · \(leitura.slot.chave.periodo.nome)")
                        .font(.system(size: w * 0.037, weight: .bold))
                    Text(leitura.frase.curta)
                        .font(.system(size: w * 0.037, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: w * 0.46, alignment: .leading)
                .offset(x: w * 0.078, y: h * 0.277)
                HStack {
                    BotaoRedondo(simbolo: "flashlight.off.fill", w: w)
                    Spacer()
                    BotaoRedondo(simbolo: "camera.fill", w: w)
                }
                .padding(.horizontal, w * 0.1)
                .frame(width: w)
                .offset(y: h * 0.875)
            }
            .foregroundStyle(Color(hex: 0xFBFCF2))
            .shadow(color: Color(hex: 0x182F30).opacity(0.3), radius: 1, y: 1)
        }
    }
}

private struct BotaoRedondo: View {
    let simbolo: String
    let w: CGFloat

    var body: some View {
        Image(systemName: simbolo)
            .font(.system(size: w * 0.05))
            .frame(width: w * 0.123, height: w * 0.123)
            .background(Color(hex: 0xE1ECDB).opacity(0.16), in: Circle())
    }
}

/// Tela de Início com o widget pequeno ou médio no alto e ícones neutros.
struct TelaDeInicioPrevia: View {
    let leitura: Leitura
    let medio: Bool
    let agora: Date

    private struct AtalhoDeApp: Identifiable {
        let simbolo: String
        let titulo: String
        var id: String { simbolo }
    }

    private let apps: [AtalhoDeApp] = [
        AtalhoDeApp(simbolo: "calendar", titulo: "Calendário"), AtalhoDeApp(simbolo: "note.text", titulo: "Notas"),
        AtalhoDeApp(simbolo: "camera", titulo: "Câmera"), AtalhoDeApp(simbolo: "clock", titulo: "Relógio"),
        AtalhoDeApp(simbolo: "music.note", titulo: "Música"), AtalhoDeApp(simbolo: "map", titulo: "Mapas"),
        AtalhoDeApp(simbolo: "envelope", titulo: "Mail"), AtalhoDeApp(simbolo: "house", titulo: "Casa"),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let celula = w * 0.212
            VStack(alignment: .leading, spacing: w * 0.03) {
                Text(Formatos.hora(agora))
                    .font(.system(size: w * 0.037, weight: .semibold))
                    .padding(.leading, w * 0.01)
                    .padding(.bottom, h * 0.03)
                HStack(alignment: .top, spacing: w * 0.031) {
                    WidgetPrevia(leitura: leitura, medio: medio, w: w)
                        .frame(width: medio ? w * 0.86 : celula * 2 + w * 0.031, height: celula * 2 + w * 0.019)
                    if !medio {
                        grade(Array(apps.prefix(4)), w: w)
                    }
                }
                grade(medio ? apps : Array(apps.suffix(4)), w: w)
                Spacer()
                HStack(spacing: 0) {
                    ForEach(["phone", "message", "safari", "music.note"], id: \.self) { s in
                        IconeDeApp(simbolo: s, titulo: nil, w: w).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, h * 0.018)
                .background(Color(hex: 0xC9D4C0).opacity(0.28), in: RoundedRectangle(cornerRadius: w * 0.07, style: .continuous))
                .padding(.bottom, h * 0.03)
            }
            .padding(.horizontal, w * 0.07)
            .padding(.top, h * 0.03)
            .foregroundStyle(.white)
        }
    }

    private func grade(_ itens: [AtalhoDeApp], w: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: w * 0.031), count: itens.count > 4 ? 4 : 2),
                  spacing: w * 0.02) {
            ForEach(itens) { item in
                IconeDeApp(simbolo: item.simbolo, titulo: item.titulo, w: w)
            }
        }
    }
}

private struct IconeDeApp: View {
    let simbolo: String
    let titulo: String?
    let w: CGFloat

    var body: some View {
        VStack(spacing: w * 0.011) {
            Image(systemName: simbolo)
                .font(.system(size: w * 0.06))
                .foregroundStyle(Color(hex: 0x2A473D))
                .frame(width: w * 0.165, height: w * 0.165)
                .background(Color(hex: 0xDBDED0), in: RoundedRectangle(cornerRadius: w * 0.04, style: .continuous))
            if let titulo {
                Text(titulo)
                    .font(.system(size: w * 0.029))
                    .lineLimit(1)
            }
        }
    }
}

/// Imitação visual dos widgets da Tela de Início (o widget real está na extensão).
struct WidgetPrevia: View {
    let leitura: Leitura
    let medio: Bool
    let w: CGFloat

    var body: some View {
        let periodo = leitura.slot.chave.periodo
        VStack(alignment: .leading, spacing: 0) {
            Label(periodo.nome.uppercased(), systemImage: periodo.simbolo)
                .font(.system(size: w * 0.027, weight: .bold))
                .tracking(w * 0.002)
            Spacer(minLength: 0)
            Text(medio ? leitura.frase.texto : leitura.frase.curta)
                .font(.system(size: medio ? w * 0.05 : w * 0.048, design: .serif))
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(medio ? leitura.frase.tema.nome : "Prumo")
                .font(.system(size: w * 0.026, weight: .medium))
        }
        .padding(w * 0.045)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(medio ? Color(hex: 0xF6F2E5) : Color(hex: 0x1E4036))
        .background(medio ? Color(hex: 0x1D463E) : Color(hex: 0xF6F3E9), in: RoundedRectangle(cornerRadius: w * 0.07, style: .continuous))
    }
}
