import WidgetKit
import SwiftUI
import PrumoKit

@main
struct PrumoWidgets: WidgetBundle {
    var body: some Widget {
        WidgetDaFrase()
    }
}

/// Uma extensão, três famílias. Todas usam o mesmo ID de frase do período.
struct WidgetDaFrase: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Motor.kindDoWidget, provider: ProvedorDaFrase()) { entrada in
            VistaDaFrase(entrada: entrada)
        }
        .configurationDisplayName("Frase do período")
        .description("A frase da manhã, da tarde, da noite ou da madrugada. O toque abre a mesma leitura no app.")
        .supportedFamilies([.accessoryRectangular, .systemSmall, .systemMedium])
    }
}

// MARK: Timeline

struct EntradaDaFrase: TimelineEntry {
    let date: Date
    let periodo: Periodo
    let intervalo: String
    let curta: String
    let texto: String
    let tema: Tema
    let atribuicao: String?
    /// `nil` no placeholder: sem destino de toque.
    let fraseId: String?

    init(date: Date, leitura: Leitura, horarios: Horarios) {
        self.date = date
        periodo = leitura.slot.chave.periodo
        intervalo = Rotulos.intervalo(periodo, horarios: horarios)
        curta = leitura.frase.curta
        texto = leitura.frase.texto
        tema = leitura.frase.tema
        atribuicao = leitura.frase.atribuicao
        fraseId = leitura.frase.id
    }

    private init(date: Date, periodo: Periodo, curta: String, texto: String, tema: Tema) {
        self.date = date
        self.periodo = periodo
        intervalo = Rotulos.intervalo(periodo, horarios: .padrao)
        self.curta = curta
        self.texto = texto
        self.tema = tema
        atribuicao = nil
        fraseId = nil
    }

    /// Exemplo da galeria e do placeholder (pr-00037).
    static func exemplo(_ data: Date = Date()) -> EntradaDaFrase {
        EntradaDaFrase(date: data, periodo: .manha, curta: "Feche o livro. O que ficou?",
                       texto: "Feche o livro e veja o que ficou.", tema: .estudos)
    }

    var link: URL? { fraseId.map { PrumoLink.frase(id: $0, origem: .widget).url } }
}

/// Lê o plano confirmado no App Group. A extensão também repõe reservas quando o sistema a chama,
/// então reabrir o app não é pré-requisito para cada troca. Sem acesso ao contêiner, usa a leitura de reserva.
struct ProvedorDaFrase: TimelineProvider {
    func placeholder(in context: Context) -> EntradaDaFrase { .exemplo() }

    func getSnapshot(in context: Context, completion: @escaping (EntradaDaFrase) -> Void) {
        let agora = Date()
        guard let motor = try? Motor.compartilhado() else {
            completion(.exemplo(agora))
            return
        }
        let plano = motor.planejar()
        completion(EntradaDaFrase(date: agora, leitura: plano.atual, horarios: plano.preferencias.horarios))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntradaDaFrase>) -> Void) {
        let agora = Date()
        guard let motor = try? Motor.compartilhado() else {
            completion(Timeline(entries: [.exemplo(agora)], policy: .after(agora.addingTimeInterval(15 * 60))))
            return
        }
        let plano = motor.planejar()
        let (entradas, renovarEm) = LinhaDoTempo.entradas(para: plano, agora: agora)
        let horarios = plano.preferencias.horarios
        completion(Timeline(
            entries: entradas.map { EntradaDaFrase(date: $0.data, leitura: $0.leitura, horarios: horarios) },
            policy: .after(renovarEm)
        ))
    }
}

// MARK: Vistas

struct VistaDaFrase: View {
    @Environment(\.widgetFamily) private var familia
    let entrada: EntradaDaFrase

    var body: some View {
        Group {
            switch familia {
            case .accessoryRectangular: Retangular(entrada: entrada)
            case .systemMedium: Medio(entrada: entrada)
            default: Pequeno(entrada: entrada)
            }
        }
        .widgetURL(entrada.link)
    }
}

/// Tela Bloqueada: texto curto em primeiro plano, rótulo do período só quando houver espaço.
/// Cor e aparência ficam com o sistema.
private struct Retangular: View {
    let entrada: EntradaDaFrase

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 1) {
                rotulo
                frase(.subheadline)
            }
            frase(.subheadline)
            frase(.footnote)
            frase(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prumo, \(entrada.periodo.nome). \(entrada.curta)")
    }

    private var rotulo: some View {
        Text("Prumo · \(entrada.periodo.nome)")
            .font(.caption2.weight(.bold))
            .widgetAccentable()
    }

    private func frase(_ estilo: Font.TextStyle) -> some View {
        Text(entrada.curta)
            .font(.system(estilo, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }
}

/// Tela de Início, pequeno: período e versão curta.
private struct Pequeno: View {
    @Environment(\.dynamicTypeSize) private var tamanho
    let entrada: EntradaDaFrase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(entrada.periodo.nome.uppercased(), systemImage: entrada.periodo.simbolo)
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .widgetAccentable()
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(entrada.curta)
                .font(.system(tamanho.isAccessibilitySize ? .body : .headline, design: .serif).weight(.regular))
                .minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !tamanho.isAccessibilitySize {
                Text("Prumo")
                    .font(.caption2.weight(.medium))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(Color(hex: 0x1E4036))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(hex: 0xF6F3E9) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prumo, \(entrada.periodo.nome). \(entrada.curta)")
    }
}

/// Tela de Início, médio: texto de leitura e tema ou autoria. Se o texto não couber, a versão curta completa.
private struct Medio: View {
    let entrada: EntradaDaFrase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(entrada.periodo.nome.uppercased(), systemImage: entrada.periodo.simbolo)
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .widgetAccentable()
                Spacer()
                Text(entrada.intervalo)
                    .font(.caption2)
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            ViewThatFits(in: .vertical) {
                texto(entrada.texto)
                texto(entrada.curta)
            }
            Spacer(minLength: 0)
            Text(entrada.atribuicao ?? entrada.tema.nome)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .opacity(0.85)
        }
        .foregroundStyle(Color(hex: 0xF6F2E5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color(hex: 0x1D463E) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prumo, \(entrada.periodo.nome). \(entrada.texto)")
    }

    private func texto(_ conteudo: String) -> some View {
        Text(conteudo)
            .font(.system(.title3, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Bloqueio", as: .accessoryRectangular) {
    WidgetDaFrase()
} timeline: {
    EntradaDaFrase.exemplo()
}

#Preview("Pequeno", as: .systemSmall) {
    WidgetDaFrase()
} timeline: {
    EntradaDaFrase.exemplo()
}

#Preview("Médio", as: .systemMedium) {
    WidgetDaFrase()
} timeline: {
    EntradaDaFrase.exemplo()
}
