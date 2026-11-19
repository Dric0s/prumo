import Foundation

/// Objetivo de leitura. O valor bruto é o usado no catálogo (`tema`).
public enum Tema: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case estudos
    case trabalho
    case empreender
    case treino

    public var id: String { rawValue }

    public var nome: String {
        switch self {
        case .estudos: "Estudos"
        case .trabalho: "Trabalho"
        case .empreender: "Empreendedorismo"
        case .treino: "Academia"
        }
    }

    /// Nome de SF Symbol usado no app e no widget.
    public var simbolo: String {
        switch self {
        case .estudos: "book"
        case .trabalho: "briefcase"
        case .empreender: "chart.line.uptrend.xyaxis"
        case .treino: "dumbbell"
        }
    }

    /// Posição na ordem canônica (a de `allCases`).
    public var indice: Int { Tema.allCases.firstIndex(of: self)! }

    public static func < (lhs: Tema, rhs: Tema) -> Bool { lhs.indice < rhs.indice }
}

/// Período do dia. `allCases` segue a ordem cronológica do ciclo: madrugada, manhã, tarde, noite.
public enum Periodo: String, Codable, CaseIterable, Sendable, Identifiable, Comparable {
    case madrugada
    case manha
    case tarde
    case noite

    public var id: String { rawValue }

    public var nome: String {
        switch self {
        case .madrugada: "Madrugada"
        case .manha: "Manhã"
        case .tarde: "Tarde"
        case .noite: "Noite"
        }
    }

    public var simbolo: String {
        switch self {
        case .madrugada: "moon.stars"
        case .manha: "sunrise"
        case .tarde: "sun.max"
        case .noite: "moon"
        }
    }

    /// Ordem usada nas telas (Hoje e Ajustes), como no protótipo.
    public static let ordemDeExibicao: [Periodo] = [.manha, .tarde, .noite, .madrugada]

    public var indice: Int { Periodo.allCases.firstIndex(of: self)! }

    /// Período seguinte no ciclo. Depois da noite vem a madrugada do dia seguinte.
    public var proximo: Periodo { Periodo.allCases[(indice + 1) % Periodo.allCases.count] }

    public var anterior: Periodo {
        Periodo.allCases[(indice + Periodo.allCases.count - 1) % Periodo.allCases.count]
    }

    public static func < (lhs: Periodo, rhs: Periodo) -> Bool { lhs.indice < rhs.indice }
}

public enum TipoFrase: String, Codable, Sendable {
    case editorial
    case citacaoTraduzida = "citacao_traduzida"
    case citacaoEmPortugues = "citacao_em_portugues"
}

/// Um registro do catálogo. A frase curta e o texto pertencem ao mesmo registro.
public struct Frase: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let tema: Tema
    public let periodo: Periodo
    /// Texto para a Tela Bloqueada e o widget pequeno.
    public let curta: String
    /// Texto para Hoje e para o widget médio.
    public let texto: String
    public let tipo: TipoFrase
    public let fonteId: String?
    public let autor: String?
    public let obra: String?
    public let localizador: String?
    public let contexto: String?

    public init(
        id: String, tema: Tema, periodo: Periodo, curta: String, texto: String,
        tipo: TipoFrase = .editorial, fonteId: String? = nil, autor: String? = nil,
        obra: String? = nil, localizador: String? = nil, contexto: String? = nil
    ) {
        self.id = id
        self.tema = tema
        self.periodo = periodo
        self.curta = curta
        self.texto = texto
        self.tipo = tipo
        self.fonteId = fonteId
        self.autor = autor
        self.obra = obra
        self.localizador = localizador
        self.contexto = contexto
    }

    enum CodingKeys: String, CodingKey {
        case id, tema, periodo, curta, texto, tipo
        case fonteId = "fonte_id"
        case autor, obra, localizador, contexto
    }

    /// Trecho histórico identificado: exibe autoria e obra e abre o contexto sob demanda.
    public var isHistorica: Bool { tipo != .editorial }
}

/// Referência editorial ou histórica de `prumo-fontes.json`.
public struct Fonte: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let titulo: String
    public let url: String
    public let ideia: String
    public let autor: String?
    public let idiomaEdicao: String?
    public let classe: String

    enum CodingKeys: String, CodingKey {
        case id, titulo, url, ideia, autor, classe
        case idiomaEdicao = "idioma_edicao"
    }

    public var link: URL? { URL(string: url) }
}
