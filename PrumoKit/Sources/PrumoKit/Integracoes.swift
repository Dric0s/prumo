import Foundation

/// Links internos. O widget e os avisos abrem exatamente o ID que estava na tela:
/// `prumo://frase/pr-00001?origem=widget`.
public enum PrumoLink: Equatable, Sendable {
    case frase(id: String, origem: OrigemInteracao)
    case hoje
    case widgets
    case ajustes

    public static let esquema = "prumo"

    public static func idValido(_ id: String) -> Bool {
        let partes = id.split(separator: "-", omittingEmptySubsequences: false)
        return partes.count == 2 && partes[0] == "pr" && partes[1].count == 5 && partes[1].allSatisfy(\.isASCII) && partes[1].allSatisfy(\.isNumber)
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.esquema,
              let componentes = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let caminho = componentes.path.split(separator: "/").map(String.init)
        switch url.host?.lowercased() {
        case "frase":
            guard caminho.count == 1, Self.idValido(caminho[0]) else { return nil }
            let origem = componentes.queryItems?.first { $0.name == "origem" }?.value
                .flatMap(OrigemInteracao.init(rawValue:)) ?? .widget
            self = .frase(id: caminho[0], origem: origem)
        case "hoje", nil: self = .hoje
        case "widgets": self = .widgets
        case "ajustes": self = .ajustes
        default: return nil
        }
    }

    public var url: URL {
        switch self {
        case .frase(let id, let origem): URL(string: "prumo://frase/\(id)?origem=\(origem.rawValue)")!
        case .hoje: URL(string: "prumo://hoje")!
        case .widgets: URL(string: "prumo://widgets")!
        case .ajustes: URL(string: "prumo://ajustes")!
        }
    }
}

/// Pedido de notificação local para um slot. Um ID por slot permite repor sem duplicar.
public struct LembretePlanejado: Hashable, Sendable {
    public static let prefixo = "prumo.slot."

    public let id: String
    public let data: Date
    /// Componentes locais (sem fuso) para `UNCalendarNotificationTrigger`.
    public let componentes: DateComponents
    public let titulo: String
    public let corpo: String
    public let fraseId: String
    public let link: URL
}

public enum PlanejadorDeLembretes {
    /// O iOS guarda até 64 pedidos por app. A fila curta cobre o horizonte com folga.
    public static let limite = 32

    /// Avisos para as viradas futuras do plano. A madrugada fica sempre em silêncio.
    /// Leituras de reserva não geram aviso, porque o ID ainda não foi confirmado.
    public static func lembretes(para plano: Plano, agora: Date, calendario: Calendar) -> [LembretePlanejado] {
        guard plano.preferencias.lembretes else { return [] }
        return plano.leituras
            .filter { !$0.reserva && $0.slot.inicio > agora && $0.slot.chave.periodo != .madrugada }
            .prefix(limite)
            .map { leitura in
                let c = calendario.dateComponents([.year, .month, .day, .hour, .minute], from: leitura.slot.inicio)
                return LembretePlanejado(
                    id: LembretePlanejado.prefixo + leitura.slot.chave.description,
                    data: leitura.slot.inicio,
                    componentes: c,
                    titulo: leitura.slot.chave.periodo.nome,
                    corpo: leitura.frase.curta,
                    fraseId: leitura.frase.id,
                    link: PrumoLink.frase(id: leitura.frase.id, origem: .aviso).url
                )
            }
    }
}

public struct EntradaDoWidget: Hashable, Sendable {
    public let data: Date
    public let leitura: Leitura
}

/// Converte o plano em entradas de timeline: a entrada vigente e uma por virada prevista.
public enum LinhaDoTempo {
    /// Quanto antes do fim do horizonte pedir renovação.
    public static let renovacaoMaxima: TimeInterval = 12 * 3600

    public static func entradas(para plano: Plano, agora: Date) -> (entradas: [EntradaDoWidget], renovarEm: Date) {
        // A entrada vigente vale desde agora; as demais, a partir de cada virada.
        let entradas = plano.leituras.enumerated().map { i, leitura in
            EntradaDoWidget(data: i == 0 ? agora : leitura.slot.inicio, leitura: leitura)
        }
        let ultimoInicio = plano.leituras.last?.slot.inicio ?? agora
        // Leitura de reserva: tentar de novo logo, para trocar pelo plano confirmado.
        let intervalo = plano.reserva ? 15 * 60 : renovacaoMaxima
        let renovarEm = min(agora.addingTimeInterval(intervalo), max(ultimoInicio, agora.addingTimeInterval(60)))
        return (entradas, renovarEm)
    }
}

/// Textos de período e intervalo usados nas telas e no widget.
public enum Rotulos {
    /// "06h – 12h"
    public static func intervalo(_ periodo: Periodo, horarios: Horarios) -> String {
        "\(horarios[periodo].rotulo) – \(horarios[periodo.proximo].rotulo)"
    }

    /// Texto falado: "das 06h às 12h".
    public static func intervaloFalado(_ periodo: Periodo, horarios: Horarios) -> String {
        "das \(horarios[periodo].rotulo) às \(horarios[periodo.proximo].rotulo)"
    }
}

#if canImport(Darwin)
extension Motor {
    public static let chaveDoAppGroup = "PrumoAppGroup"
    public static let kindDoWidget = "PrumoFrase"

    /// Diretório compartilhado entre app e extensão. Se o App Group não estiver configurado,
    /// usa o Application Support do processo (app e extensão deixam de compartilhar estado).
    public static func diretorioCompartilhado(appGroup: String? = nil) -> URL? {
        let grupo = appGroup ?? (Bundle.main.object(forInfoDictionaryKey: chaveDoAppGroup) as? String)
        if let grupo, !grupo.isEmpty,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo) {
            return url.appendingPathComponent("Prumo", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Prumo", isDirectory: true)
    }

    /// Motor com catálogo embarcado e banco no App Group. Se o banco não abrir
    /// (por exemplo, antes do primeiro desbloqueio), o motor responde com leituras de reserva.
    public static func compartilhado(appGroup: String? = nil) throws -> Motor {
        let catalogo = try Catalogo.embarcado()
        let diretorio = diretorioCompartilhado(appGroup: appGroup)
        if let diretorio {
            try? FileManager.default.createDirectory(at: diretorio, withIntermediateDirectories: true)
        }
        let armazenamento = diretorio.flatMap { try? Armazenamento(url: $0.appendingPathComponent("prumo.sqlite")) }
        let espelho = diretorio.map { EspelhoDePreferencias(url: $0.appendingPathComponent("preferencias.json")) }
        return Motor(catalogo: catalogo, armazenamento: armazenamento, espelho: espelho)
    }
}
#endif
