import Foundation

/// Escolhe o próximo ID de um período.
///
/// - Um baralho por período. Cada combinação de tema e período tem uma fila em
///   embaralhamento estável (semente local + período + tema + ciclo).
/// - Alterna os temas ativos que ainda têm registros inéditos no ciclo do período.
/// - O ciclo recomeça só quando o conjunto elegível esgota, evitando repetir a última frase na fronteira.
/// - Reservas substituídas continuam contando como vistas no ciclo.
struct Selecionador {
    struct EstadoPeriodo {
        var ciclo: Int
        var vistos: Set<String>
        /// Reservas ativas (chave, ID) em ordem cronológica, para achar a anterior a um slot.
        var ativas: [(chave: ChaveSlot, fraseId: String)]
    }

    let catalogo: Catalogo
    let temas: [Tema]
    let semente: UInt64
    private let carregar: (Periodo) throws -> [RegistroAgenda]
    private var estados: [Periodo: EstadoPeriodo] = [:]
    private var filas: [String: [Frase]] = [:]

    init(catalogo: Catalogo, temas: [Tema], semente: UInt64, carregar: @escaping (Periodo) throws -> [RegistroAgenda]) {
        self.catalogo = catalogo
        self.temas = temas.isEmpty ? Tema.allCases : temas.sorted()
        self.semente = semente
        self.carregar = carregar
    }

    private mutating func estado(_ periodo: Periodo) throws -> EstadoPeriodo {
        if let estado = estados[periodo] { return estado }
        let registros = try carregar(periodo)
        let ciclo = registros.map(\.ciclo).max() ?? 0
        let estado = EstadoPeriodo(
            ciclo: ciclo,
            vistos: Set(registros.lazy.filter { $0.ciclo == ciclo }.map(\.fraseId)),
            ativas: registros.filter(\.ativo).map { ($0.chave, $0.fraseId) }.sorted { $0.chave < $1.chave }
        )
        estados[periodo] = estado
        return estado
    }

    private mutating func fila(_ tema: Tema, _ periodo: Periodo, _ ciclo: Int) -> [Frase] {
        let chave = "\(tema.rawValue).\(periodo.rawValue).\(ciclo)"
        if let fila = filas[chave] { return fila }
        let s = HashEstavel.fnv1a([String(semente), periodo.rawValue, tema.rawValue, String(ciclo)])
        let fila = catalogo.frases(tema: tema, periodo: periodo).embaralhadoEstavel(semente: s)
        filas[chave] = fila
        return fila
    }

    /// Temas ativos na ordem de alternância: começa no tema seguinte ao da reserva anterior.
    private func ordemDosTemas(depoisDe ultimo: Tema?) -> [Tema] {
        guard let ultimo else { return temas }
        let depois = temas.filter { $0 > ultimo }
        let antes = temas.filter { $0 <= ultimo }
        return depois + antes
    }

    /// Escolhe o ID para `chave` e o marca como visto no estado em memória.
    mutating func escolher(para chave: ChaveSlot) throws -> (frase: Frase, ciclo: Int) {
        let periodo = chave.periodo
        var estado = try estado(periodo)
        let anterior = estado.ativas.last { $0.chave < chave }?.fraseId
        let ultimoTema = anterior.flatMap { catalogo.frase(id: $0)?.tema }
        let ordem = ordemDosTemas(depoisDe: ultimoTema)

        var escolhida: Frase?
        for tema in ordem {
            if let frase = fila(tema, periodo, estado.ciclo).first(where: { !estado.vistos.contains($0.id) }) {
                escolhida = frase
                break
            }
        }
        if escolhida == nil {
            // Conjunto elegível esgotado: novo ciclo, sem repetir a anterior logo na fronteira.
            estado.ciclo += 1
            estado.vistos = []
            for tema in ordem {
                if let frase = fila(tema, periodo, estado.ciclo).first(where: { $0.id != anterior }) {
                    escolhida = frase
                    break
                }
            }
        }
        // Só acontece se o único registro elegível for o anterior.
        let frase = escolhida ?? fila(ordem[0], periodo, estado.ciclo)[0]

        estado.vistos.insert(frase.id)
        let posicao = estado.ativas.firstIndex { $0.chave > chave } ?? estado.ativas.endIndex
        estado.ativas.insert((chave, frase.id), at: posicao)
        estados[periodo] = estado
        return (frase, estado.ciclo)
    }
}

/// Leitura de reserva do bundle, usada quando o armazenamento compartilhado está indisponível.
/// Determinística por slot e nunca gravada como vista.
public enum LeituraDeReserva {
    public static func frase(para chave: ChaveSlot, temas: [Tema], catalogo: Catalogo) -> Frase {
        let ativos = temas.isEmpty ? Tema.allCases : temas.sorted()
        let h = HashEstavel.fnv1a(["reserva", String(chave.dia.ordinal), chave.periodo.rawValue])
        let tema = ativos[Int(h % UInt64(ativos.count))]
        let lista = catalogo.frases(tema: tema, periodo: chave.periodo)
        return lista[Int((h / UInt64(ativos.count)) % UInt64(lista.count))]
    }
}
