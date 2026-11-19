import Foundation

/// Unidade de seleção: um período de uma data civil local.
/// A data é a do início daquele período (a noite que avança pela madrugada pertence à data anterior).
public struct ChaveSlot: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let dia: DataCivil
    public let periodo: Periodo

    public init(dia: DataCivil, periodo: Periodo) {
        self.dia = dia
        self.periodo = periodo
    }

    public var seguinte: ChaveSlot {
        periodo == .noite
            ? ChaveSlot(dia: dia.somando(dias: 1), periodo: .madrugada)
            : ChaveSlot(dia: dia, periodo: periodo.proximo)
    }

    public var anterior: ChaveSlot {
        periodo == .madrugada
            ? ChaveSlot(dia: dia.somando(dias: -1), periodo: .noite)
            : ChaveSlot(dia: dia, periodo: periodo.anterior)
    }

    /// "2026-11-18.manha". Usado em IDs de aviso.
    public var description: String { "\(dia).\(periodo.rawValue)" }

    public static func < (lhs: ChaveSlot, rhs: ChaveSlot) -> Bool {
        (lhs.dia, lhs.periodo.indice) < (rhs.dia, rhs.periodo.indice)
    }
}

public struct Slot: Hashable, Sendable {
    public let chave: ChaveSlot
    /// Início inclusivo.
    public let inicio: Date
    /// Fim exclusivo: início do slot seguinte.
    public let fim: Date

    public func contem(_ data: Date) -> Bool { inicio <= data && data < fim }
}

/// Resolve períodos com `Calendar` e fuso local, incluindo viradas de dia e horário de verão.
public struct ResolvedorDePeriodos: Sendable {
    public let calendario: Calendar
    public let horarios: Horarios

    public init(calendario: Calendar, horarios: Horarios) {
        precondition(horarios.saoValidos, "Horários fora de ordem")
        self.calendario = calendario
        self.horarios = horarios
    }

    /// Instante em que o slot começa. Num horário inexistente (início do horário de verão),
    /// o `Calendar` avança para o primeiro instante válido; num horário repetido, usa a primeira ocorrência.
    public func inicio(de chave: ChaveSlot) -> Date {
        let c = chave.dia.componentes
        let hora = horarios[chave.periodo]
        var componentes = DateComponents()
        componentes.year = c.ano
        componentes.month = c.mes
        componentes.day = c.dia
        componentes.hour = hora.hora
        componentes.minute = hora.minuto
        if let data = calendario.date(from: componentes) { return data }
        // Não deve ocorrer no calendário gregoriano; mantém uma resposta determinística.
        let meiaNoite = calendario.date(from: DateComponents(year: c.ano, month: c.mes, day: c.dia)) ?? Date(timeIntervalSince1970: 0)
        return meiaNoite.addingTimeInterval(TimeInterval(hora.minutos * 60))
    }

    public func slot(de chave: ChaveSlot) -> Slot {
        Slot(chave: chave, inicio: inicio(de: chave), fim: inicio(de: chave.seguinte))
    }

    /// Slot vigente no instante dado. Cada intervalo inclui seu início e exclui o próximo.
    /// Antes do primeiro início do dia vale o último período da data anterior.
    public func slot(contendo data: Date) -> Slot {
        let hoje = DataCivil(data, calendario: calendario)
        for dia in [hoje, hoje.somando(dias: -1)] {
            for periodo in Periodo.allCases.reversed() {
                let chave = ChaveSlot(dia: dia, periodo: periodo)
                let slot = slot(de: chave)
                // `fim > inicio` descarta um período que o horário de verão reduziu a zero.
                if slot.inicio <= data, data < slot.fim { return slot }
            }
        }
        // Salvaguarda para fusos com saltos de calendário inteiros.
        var chave = ChaveSlot(dia: hoje.somando(dias: -2), periodo: .noite)
        while inicio(de: chave.seguinte) <= data { chave = chave.seguinte }
        return slot(de: chave)
    }

    /// Slot vigente e os seguintes que começam antes de `limite`, em ordem cronológica.
    public func slots(apartirDe data: Date, ate limite: Date) -> [Slot] {
        var resultado = [slot(contendo: data)]
        var chave = resultado[0].chave.seguinte
        while true {
            let proximo = slot(de: chave)
            guard proximo.inicio < limite else { break }
            if proximo.fim > proximo.inicio { resultado.append(proximo) }
            chave = chave.seguinte
        }
        return resultado
    }
}
