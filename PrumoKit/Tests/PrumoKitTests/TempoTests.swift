import Foundation
import Testing
@testable import PrumoKit

@Suite("Datas civis e horários")
struct TempoTests {
    @Test func ordinalConhecido() {
        #expect(DataCivil(ano: 1970, mes: 1, dia: 1).ordinal == 0)
        #expect(DataCivil(ano: 2000, mes: 3, dia: 1).ordinal == 11017)
        #expect(DataCivil(ano: 1969, mes: 12, dia: 31).ordinal == -1)
        #expect(DataCivil(ano: 2026, mes: 11, dia: 18).description == "2026-11-18")
    }

    @Test func idaEVoltaConfereComCalendar() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var dia = cal.date(from: DateComponents(year: 1999, month: 12, day: 25))!
        for _ in 0..<12_000 {
            let civil = DataCivil(dia, calendario: cal)
            let c = cal.dateComponents([.year, .month, .day], from: dia)
            #expect(civil.componentes == (c.year!, c.month!, c.day!))
            #expect(DataCivil(ordinal: civil.ordinal).componentes == civil.componentes)
            dia = cal.date(byAdding: .day, value: 1, to: dia)!
        }
    }

    @Test func rotulosDeHora() {
        #expect(HoraDoDia(hora: 6).rotulo == "06h")
        #expect(HoraDoDia(hora: 6, minuto: 30).rotulo == "06h30")
        #expect(HoraDoDia(hora: 0).description == "00:00")
        #expect(HoraDoDia(texto: "23:59") == HoraDoDia(hora: 23, minuto: 59))
        #expect(HoraDoDia(texto: "24:00") == nil)
        #expect(Rotulos.intervalo(.noite, horarios: .padrao) == "18h – 00h")
    }

    @Test func horariosPrecisamDeOrdemEstrita() {
        #expect(Horarios.padrao.saoValidos)
        var h = Horarios.padrao
        h.tarde = HoraDoDia(hora: 6)
        #expect(h.primeiroInvalido == .tarde)
        h = Horarios.padrao
        h.madrugada = HoraDoDia(hora: 19)
        #expect(h.primeiroInvalido == .manha)
    }

    @Test func validacaoDePreferencias() {
        #expect(Preferencias.padrao.validar() == nil)
        #expect(Preferencias(temas: []).validar() == .semTemas)
        var h = Horarios.padrao
        h.noite = HoraDoDia(hora: 12)
        #expect(Preferencias(horarios: h).validar() == .horarioForaDeOrdem(.noite))
        #expect(Preferencias.padrao.lembretes == false)
    }

    @Test func preferenciasIgnoramValoresDesconhecidos() throws {
        let json = #"{"temas":["estudos","meditacao"],"horarios":{"madrugada":"00:00","manha":"07:00","tarde":"12:00","noite":"18:00"},"lembretes":true}"#
        let p = try JSONDecoder().decode(Preferencias.self, from: Data(json.utf8))
        #expect(p.temas == [.estudos])
        #expect(p.horarios.manha == HoraDoDia(hora: 7))
        #expect(p.lembretes)
    }
}

@Suite("Resolução de períodos")
struct SlotsTests {
    let r = ResolvedorDePeriodos(calendario: saoPaulo, horarios: .padrao)
    let dia18 = DataCivil(ano: 2026, mes: 11, dia: 18)

    @Test(arguments: [
        (23, 59, 18, Periodo.noite), (0, 0, 19, .madrugada), (5, 59, 19, .madrugada), (6, 0, 19, .manha),
        (11, 59, 19, .manha), (12, 0, 19, .tarde), (17, 59, 19, .tarde), (18, 0, 19, .noite),
    ])
    func viradas(hora: Int, minuto: Int, diaEsperado: Int, periodo: Periodo) {
        let instante = data(2026, 11, hora == 23 ? 18 : 19, hora, minuto)
        let slot = r.slot(contendo: instante)
        #expect(slot.chave == ChaveSlot(dia: DataCivil(ano: 2026, mes: 11, dia: diaEsperado), periodo: periodo))
        #expect(slot.contem(instante))
    }

    @Test func antesDoPrimeiroInicioValeANoiteAnterior() {
        var h = Horarios.padrao
        h.madrugada = HoraDoDia(hora: 1)
        let r = ResolvedorDePeriodos(calendario: saoPaulo, horarios: h)
        #expect(r.slot(contendo: data(2026, 11, 19, 0, 30)).chave == ChaveSlot(dia: dia18, periodo: .noite))
        #expect(r.slot(contendo: data(2026, 11, 19, 1, 0)).chave.periodo == .madrugada)
    }

    @Test func horaInexistenteNoInicioDoHorarioDeVerao() {
        // Em 4/11/2018, São Paulo pulou de 00:00 para 01:00.
        let dia = DataCivil(ano: 2018, mes: 11, dia: 4)
        let madrugada = r.slot(de: ChaveSlot(dia: dia, periodo: .madrugada))
        #expect(saoPaulo.component(.hour, from: madrugada.inicio) == 1)
        let noiteAnterior = r.slot(de: ChaveSlot(dia: dia.somando(dias: -1), periodo: .noite))
        #expect(noiteAnterior.fim == madrugada.inicio)
        #expect(r.slot(contendo: madrugada.inicio.addingTimeInterval(-1)).chave == noiteAnterior.chave)
        #expect(r.slot(contendo: madrugada.inicio).chave == madrugada.chave)
    }

    @Test func horaRepetidaNoFimDoHorarioDeVerao() {
        // Em 17/2/2019, 23:00–23:59 do dia 16 ocorreu duas vezes.
        let noite16 = ChaveSlot(dia: DataCivil(ano: 2019, mes: 2, dia: 16), periodo: .noite)
        let slot = r.slot(de: noite16)
        #expect(slot.fim.timeIntervalSince(slot.inicio) == 7 * 3600)
        let segundaOcorrencia = slot.fim.addingTimeInterval(-30 * 60)
        #expect(r.slot(contendo: segundaOcorrencia).chave == noite16)
    }

    @Test func periodoReduzidoAZeroEDescartado() {
        // Madrugada 00:00 (inexistente, vira 01:00) e manhã 01:00 coincidem no dia do salto.
        var h = Horarios.padrao
        h.manha = HoraDoDia(hora: 1)
        let r = ResolvedorDePeriodos(calendario: saoPaulo, horarios: h)
        let slots = r.slots(apartirDe: data(2018, 11, 3, 20), ate: data(2018, 11, 4, 13))
        #expect(!slots.contains { $0.chave == ChaveSlot(dia: DataCivil(ano: 2018, mes: 11, dia: 4), periodo: .madrugada) })
        #expect(slots.allSatisfy { $0.fim > $0.inicio })
        #expect(r.slot(contendo: data(2018, 11, 4, 1, 10)).chave.periodo == .manha)
    }

    @Test func horizonteContiguo() {
        let inicio = data(2026, 11, 18, 11, 38)
        let slots = r.slots(apartirDe: inicio, ate: inicio.addingTimeInterval(7 * 86_400))
        #expect(slots.count == 29)
        #expect(slots[0].chave == ChaveSlot(dia: dia18, periodo: .manha))
        for (a, b) in zip(slots, slots.dropFirst()) {
            #expect(a.fim == b.inicio)
            #expect(a.chave.seguinte == b.chave)
        }
    }

    @Test func outroFusoComHorarioDeVerao() {
        let ny = calendario("America/New_York")
        var h = Horarios.padrao
        h.madrugada = HoraDoDia(hora: 2, minuto: 30)
        let r = ResolvedorDePeriodos(calendario: ny, horarios: h)
        // 8/3/2026: 02:00 → 03:00 em Nova York.
        let slot = r.slot(de: ChaveSlot(dia: DataCivil(ano: 2026, mes: 3, dia: 8), periodo: .madrugada))
        #expect(ny.component(.hour, from: slot.inicio) == 3)
    }
}
