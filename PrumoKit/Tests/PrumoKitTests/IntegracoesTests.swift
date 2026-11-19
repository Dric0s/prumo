import Foundation
import Testing
@testable import PrumoKit

@Suite("Links, avisos e timeline")
struct IntegracoesTests {
    @Test func linkDeFrase() throws {
        let url = PrumoLink.frase(id: "pr-00001", origem: .widget).url
        #expect(url.absoluteString == "prumo://frase/pr-00001?origem=widget")
        #expect(PrumoLink(url: url) == .frase(id: "pr-00001", origem: .widget))
        #expect(PrumoLink(url: URL(string: "prumo://frase/pr-00001")!) == .frase(id: "pr-00001", origem: .widget))
        #expect(PrumoLink(url: URL(string: "prumo://frase/pr-00001?origem=aviso")!) == .frase(id: "pr-00001", origem: .aviso))
        #expect(PrumoLink(url: URL(string: "prumo://frase/../etc")!) == nil)
        #expect(PrumoLink(url: URL(string: "prumo://frase/pr-1")!) == nil)
        #expect(PrumoLink(url: URL(string: "https://frase/pr-00001")!) == nil)
        #expect(PrumoLink(url: URL(string: "prumo://widgets")!) == .widgets)
    }

    @Test func lembretesDesligadosNaoGeramPedidos() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let m = try motor(relogio: relogio)
        #expect(PlanejadorDeLembretes.lembretes(para: m.planejar(), agora: relogio.agora, calendario: saoPaulo).isEmpty)
    }

    @Test func lembretesUsamAMesmaSelecaoESilenciamAMadrugada() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let m = try motor(relogio: relogio)
        let plano = try m.atualizarPreferencias(Preferencias(lembretes: true))
        let lembretes = PlanejadorDeLembretes.lembretes(para: plano, agora: relogio.agora, calendario: saoPaulo)
        #expect(lembretes.count == 21)
        #expect(lembretes.allSatisfy { $0.data > relogio.agora })
        #expect(!lembretes.contains { $0.id.hasSuffix(".madrugada") })
        #expect(Set(lembretes.map(\.id)).count == lembretes.count)
        let primeiro = try #require(lembretes.first)
        #expect(primeiro.id == "prumo.slot.2026-11-18.tarde")
        #expect(primeiro.componentes.hour == 12 && primeiro.componentes.minute == 0 && primeiro.componentes.day == 18)
        let leitura = try #require(plano.leitura(de: ChaveSlot(dia: DataCivil(ano: 2026, mes: 11, dia: 18), periodo: .tarde)))
        #expect(primeiro.fraseId == leitura.frase.id)
        #expect(primeiro.corpo == leitura.frase.curta)
        #expect(PrumoLink(url: primeiro.link) == .frase(id: leitura.frase.id, origem: .aviso))
    }

    @Test func leituraDeReservaNaoGeraAviso() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let dir = try diretorioTemporario()
        let espelho = EspelhoDePreferencias(url: dir.appendingPathComponent("p.json"))
        espelho.gravar(Preferencias(lembretes: true))
        let m = try motor(relogio: relogio, espelho: espelho, semArmazenamento: true)
        #expect(PlanejadorDeLembretes.lembretes(para: m.planejar(), agora: relogio.agora, calendario: saoPaulo).isEmpty)
    }

    @Test func timelineTemEntradaVigenteEUmaPorVirada() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 11, 38))
        let m = try motor(relogio: relogio)
        let plano = m.planejar()
        let (entradas, renovarEm) = LinhaDoTempo.entradas(para: plano, agora: relogio.agora)
        #expect(entradas.count == plano.leituras.count)
        #expect(entradas[0].data == relogio.agora)
        #expect(entradas[1].data == data(2026, 11, 18, 12))
        #expect(zip(entradas, entradas.dropFirst()).allSatisfy { $0.data < $1.data })
        #expect(renovarEm > relogio.agora)
        #expect(renovarEm <= relogio.agora.addingTimeInterval(LinhaDoTempo.renovacaoMaxima))
    }

    @Test func timelineDeReservaRenovaLogo() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 11, 38))
        let m = try motor(relogio: relogio, semArmazenamento: true)
        let (_, renovarEm) = LinhaDoTempo.entradas(para: m.planejar(), agora: relogio.agora)
        #expect(renovarEm == relogio.agora.addingTimeInterval(15 * 60))
    }
}
