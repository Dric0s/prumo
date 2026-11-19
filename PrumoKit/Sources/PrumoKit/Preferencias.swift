import Foundation

public enum ErroPreferencias: Error, Equatable, Sendable {
    case semTemas
    case horarioForaDeOrdem(Periodo)

    /// Mensagem exibida em Ajustes.
    public var mensagem: String {
        switch self {
        case .semTemas: "Escolha pelo menos um tema antes de salvar."
        case .horarioForaDeOrdem: "Use horários diferentes, em ordem de madrugada, manhã, tarde e noite."
        }
    }
}

public struct Preferencias: Codable, Hashable, Sendable {
    /// Temas ativos. Guardados em ordem canônica e sem repetição.
    public private(set) var temas: [Tema]
    public var horarios: Horarios
    /// Avisos começam desligados.
    public var lembretes: Bool

    public init(temas: some Sequence<Tema> = Tema.allCases, horarios: Horarios = .padrao, lembretes: Bool = false) {
        self.temas = Set(temas).sorted()
        self.horarios = horarios
        self.lembretes = lembretes
    }

    public static let padrao = Preferencias()

    public mutating func definirTemas(_ novos: some Sequence<Tema>) {
        temas = Set(novos).sorted()
    }

    public func validar() -> ErroPreferencias? {
        if temas.isEmpty { return .semTemas }
        if let periodo = horarios.primeiroInvalido { return .horarioForaDeOrdem(periodo) }
        return nil
    }

    enum CodingKeys: String, CodingKey { case temas, horarios, lembretes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Valores desconhecidos são ignorados para tolerar versões futuras.
        let brutos = (try? c.decode([String].self, forKey: .temas)) ?? []
        let temas = brutos.compactMap(Tema.init(rawValue:))
        let horarios = (try? c.decode(Horarios.self, forKey: .horarios)) ?? .padrao
        self.init(
            temas: temas.isEmpty ? Tema.allCases : temas,
            horarios: horarios.saoValidos ? horarios : .padrao,
            lembretes: (try? c.decode(Bool.self, forKey: .lembretes)) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(temas.map(\.rawValue), forKey: .temas)
        try c.encode(horarios, forKey: .horarios)
        try c.encode(lembretes, forKey: .lembretes)
    }
}
