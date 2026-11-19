import Foundation

public enum ErroCatalogo: Error, Equatable, CustomStringConvertible {
    case esquemaNaoSuportado(Int)
    case idDuplicado(String)
    case idInvalido(String)
    case textoVazio(String)
    case fonteDesconhecida(frase: String, fonte: String)
    case atribuicaoIncompleta(String)
    case combinacaoVazia(Tema, Periodo)
    case recursoAusente(String)

    public var description: String {
        switch self {
        case .esquemaNaoSuportado(let v): "schema_version \(v) não suportado"
        case .idDuplicado(let id): "ID duplicado: \(id)"
        case .idInvalido(let id): "ID inválido: \(id)"
        case .textoVazio(let id): "Texto vazio em \(id)"
        case .fonteDesconhecida(let f, let fonte): "\(f) aponta para fonte inexistente \(fonte)"
        case .atribuicaoIncompleta(let id): "Trecho histórico sem autor ou obra: \(id)"
        case .combinacaoVazia(let t, let p): "Sem frases para \(t.rawValue)/\(p.rawValue)"
        case .recursoAusente(let nome): "Recurso ausente no bundle: \(nome)"
        }
    }
}

struct ArquivoCatalogo: Decodable {
    let schemaVersion: Int
    let catalogVersion: String
    let locale: String
    let frases: [Frase]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case catalogVersion = "catalog_version"
        case locale, frases
    }
}

/// Catálogo imutável, indexado por ID e por combinação de tema e período.
/// App e extensão embarcam o mesmo recurso.
public final class Catalogo: Sendable {
    public static let versaoDeEsquemaSuportada = 1

    public let versao: String
    public let locale: String
    public let frases: [Frase]
    public let fontes: [String: Fonte]

    private let porId: [String: Frase]
    private let porCombinacao: [Combinacao: [Frase]]

    struct Combinacao: Hashable {
        let tema: Tema
        let periodo: Periodo
    }

    public init(frases: [Frase], fontes: [Fonte] = [], versao: String = "teste", locale: String = "pt-BR") throws {
        var porId: [String: Frase] = [:]
        porId.reserveCapacity(frases.count)
        let fontesPorId = Dictionary(fontes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let validarFontes = !fontes.isEmpty
        for frase in frases {
            guard PrumoLink.idValido(frase.id) else { throw ErroCatalogo.idInvalido(frase.id) }
            guard porId[frase.id] == nil else { throw ErroCatalogo.idDuplicado(frase.id) }
            guard !frase.curta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !frase.texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { throw ErroCatalogo.textoVazio(frase.id) }
            if validarFontes, let fonte = frase.fonteId, fontesPorId[fonte] == nil {
                throw ErroCatalogo.fonteDesconhecida(frase: frase.id, fonte: fonte)
            }
            if frase.isHistorica, frase.autor == nil || frase.obra == nil {
                throw ErroCatalogo.atribuicaoIncompleta(frase.id)
            }
            porId[frase.id] = frase
        }
        var grupos: [Combinacao: [Frase]] = [:]
        for frase in frases {
            grupos[Combinacao(tema: frase.tema, periodo: frase.periodo), default: []].append(frase)
        }
        for tema in Tema.allCases {
            for periodo in Periodo.allCases {
                let chave = Combinacao(tema: tema, periodo: periodo)
                guard let lista = grupos[chave], !lista.isEmpty else {
                    throw ErroCatalogo.combinacaoVazia(tema, periodo)
                }
                // Ordem por ID: base estável para o embaralhamento com semente.
                grupos[chave] = lista.sorted { $0.id < $1.id }
            }
        }
        self.frases = frases
        self.fontes = fontesPorId
        self.porId = porId
        self.porCombinacao = grupos
        self.versao = versao
        self.locale = locale
    }

    public static func carregar(catalogo: Data, fontes: Data?) throws -> Catalogo {
        let decoder = JSONDecoder()
        let arquivo = try decoder.decode(ArquivoCatalogo.self, from: catalogo)
        guard arquivo.schemaVersion == versaoDeEsquemaSuportada else {
            throw ErroCatalogo.esquemaNaoSuportado(arquivo.schemaVersion)
        }
        let listaFontes = try fontes.map { try decoder.decode([Fonte].self, from: $0) } ?? []
        return try Catalogo(frases: arquivo.frases, fontes: listaFontes,
                            versao: arquivo.catalogVersion, locale: arquivo.locale)
    }

    private static let cacheEmbarcado: Result<Catalogo, any Error> = Result {
        guard let urlCatalogo = Bundle.module.url(forResource: "prumo-catalogo", withExtension: "json") else {
            throw ErroCatalogo.recursoAusente("prumo-catalogo.json")
        }
        let urlFontes = Bundle.module.url(forResource: "prumo-fontes", withExtension: "json")
        return try carregar(
            catalogo: Data(contentsOf: urlCatalogo),
            fontes: try urlFontes.map { try Data(contentsOf: $0) }
        )
    }

    /// Catálogo embarcado no pacote. Decodificado uma vez por processo.
    public static func embarcado() throws -> Catalogo { try cacheEmbarcado.get() }

    public func frase(id: String) -> Frase? { porId[id] }

    /// Registros da combinação, em ordem de ID.
    public func frases(tema: Tema, periodo: Periodo) -> [Frase] {
        porCombinacao[Combinacao(tema: tema, periodo: periodo)] ?? []
    }

    public func fonte(de frase: Frase) -> Fonte? {
        frase.fonteId.flatMap { fontes[$0] }
    }
}
