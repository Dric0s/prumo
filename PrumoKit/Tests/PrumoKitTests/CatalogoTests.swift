import Foundation
import Testing
@testable import PrumoKit

@Suite("Catálogo embarcado")
struct CatalogoTests {
    @Test func carregaCincoMilRegistrosComIdsUnicos() throws {
        let c = try catalogoReal()
        #expect(c.frases.count == 5000)
        #expect(Set(c.frases.map(\.id)).count == 5000)
        #expect(c.versao == "1.0.0")
        #expect(c.locale == "pt-BR")
    }

    @Test func matrizDeDezesseisCombinacoes() throws {
        let c = try catalogoReal()
        for tema in Tema.allCases {
            #expect(Periodo.allCases.map { c.frases(tema: tema, periodo: $0).count }.reduce(0, +) == 1250)
            for periodo in Periodo.allCases {
                #expect([312, 313].contains(c.frases(tema: tema, periodo: periodo).count))
            }
        }
        for periodo in Periodo.allCases {
            #expect(Tema.allCases.map { c.frases(tema: $0, periodo: periodo).count }.reduce(0, +) == 1250)
        }
    }

    @Test func limitesDeTamanho() throws {
        let c = try catalogoReal()
        #expect(c.frases.map(\.curta.count).max() == 64)
        #expect(c.frases.map(\.texto.count).max()! <= 162)
    }

    @Test func trechosHistoricosTemAtribuicaoCompleta() throws {
        let c = try catalogoReal()
        let historicos = c.frases.filter(\.isHistorica)
        #expect(historicos.count == 32)
        #expect(historicos.filter { $0.tipo == .citacaoEmPortugues }.count == 2)
        for f in historicos {
            #expect(f.autor != nil && f.obra != nil && f.localizador != nil && f.contexto != nil, "\(f.id)")
            #expect(c.fonte(de: f) != nil, "\(f.id)")
        }
        // Texto editorial nunca aparece como se tivesse autor.
        #expect(c.frases.filter { $0.tipo == .editorial && $0.autor != nil }.isEmpty)
    }

    @Test func todasAsReferenciasExistem() throws {
        let c = try catalogoReal()
        #expect(c.fontes.count == 45)
        for f in c.frases where f.fonteId != nil {
            #expect(c.fontes[f.fonteId!] != nil, "\(f.id) → \(f.fonteId!)")
        }
    }

    @Test func semDuplicatasNormalizadasEntreRegistros() throws {
        let c = try catalogoReal()
        func normalizar(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init).joined()
        }
        var dono: [String: String] = [:]
        for f in c.frases {
            for texto in Set([normalizar(f.curta), normalizar(f.texto)]) {
                if let outro = dono[texto] {
                    Issue.record("\(f.id) repete \(outro)")
                }
                dono[texto] = f.id
            }
        }
    }

    @Test func rejeitaIdDuplicado() {
        let f = Frase(id: "pr-00001", tema: .estudos, periodo: .manha, curta: "a", texto: "a")
        #expect(throws: ErroCatalogo.idDuplicado("pr-00001")) { try Catalogo(frases: [f, f]) }
    }

    @Test func rejeitaEsquemaDesconhecido() {
        let json = #"{"schema_version": 2, "catalog_version": "9", "locale": "pt-BR", "frases": []}"#
        #expect(throws: ErroCatalogo.esquemaNaoSuportado(2)) {
            try Catalogo.carregar(catalogo: Data(json.utf8), fontes: nil)
        }
    }

    @Test func rejeitaCombinacaoVazia() {
        let f = Frase(id: "pr-00001", tema: .estudos, periodo: .manha, curta: "a", texto: "a")
        #expect(throws: ErroCatalogo.self) { try Catalogo(frases: [f]) }
    }
}
