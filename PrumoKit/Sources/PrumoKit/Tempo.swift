import Foundation

/// Data civil local (ano, mês, dia), sem hora nem fuso.
/// `ordinal` conta dias desde 1970-01-01 no calendário gregoriano proléptico.
public struct DataCivil: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let ordinal: Int

    public init(ordinal: Int) { self.ordinal = ordinal }

    /// Algoritmo `days_from_civil` de Howard Hinnant.
    public init(ano: Int, mes: Int, dia: Int) {
        let y = mes <= 2 ? ano - 1 : ano
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (mes + 9) % 12
        let doy = (153 * mp + 2) / 5 + dia - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146_097 + doe - 719_468
    }

    public init(_ data: Date, calendario: Calendar) {
        let c = calendario.dateComponents([.year, .month, .day], from: data)
        self.init(ano: c.year!, mes: c.month!, dia: c.day!)
    }

    /// Algoritmo `civil_from_days` de Howard Hinnant.
    public var componentes: (ano: Int, mes: Int, dia: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    public func somando(dias: Int) -> DataCivil { DataCivil(ordinal: ordinal + dias) }

    public var description: String {
        let c = componentes
        return String(format: "%04d-%02d-%02d", c.ano, c.mes, c.dia)
    }

    public init?(texto: String) {
        let partes = texto.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3, (1...12).contains(partes[1]), (1...31).contains(partes[2]) else { return nil }
        self.init(ano: partes[0], mes: partes[1], dia: partes[2])
    }

    public static func < (lhs: DataCivil, rhs: DataCivil) -> Bool { lhs.ordinal < rhs.ordinal }
}

/// Hora local de início de um período, em minutos desde a meia-noite.
public struct HoraDoDia: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let minutos: Int

    public init(minutos: Int) {
        precondition((0..<1440).contains(minutos), "Hora fora do dia: \(minutos)")
        self.minutos = minutos
    }

    public init(hora: Int, minuto: Int = 0) { self.init(minutos: hora * 60 + minuto) }

    /// Aceita "HH:MM".
    public init?(texto: String) {
        let partes = texto.split(separator: ":")
        guard partes.count == 2, let h = Int(partes[0]), let m = Int(partes[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        self.init(hora: h, minuto: m)
    }

    public var hora: Int { minutos / 60 }
    public var minuto: Int { minutos % 60 }

    /// "06:00"
    public var description: String { String(format: "%02d:%02d", hora, minuto) }

    /// Rótulo curto como no protótipo: "06h" ou "06h30".
    public var rotulo: String {
        minuto == 0 ? String(format: "%02dh", hora) : String(format: "%02dh%02d", hora, minuto)
    }

    public static func < (lhs: HoraDoDia, rhs: HoraDoDia) -> Bool { lhs.minutos < rhs.minutos }

    // Codifica como "HH:MM" para manter as preferências legíveis.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        guard let valor = HoraDoDia(texto: try c.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Hora inválida")
        }
        self = valor
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// Os quatro inícios configuráveis. Devem estar em ordem estrita: madrugada < manhã < tarde < noite.
public struct Horarios: Codable, Hashable, Sendable {
    public var madrugada: HoraDoDia
    public var manha: HoraDoDia
    public var tarde: HoraDoDia
    public var noite: HoraDoDia

    public init(madrugada: HoraDoDia, manha: HoraDoDia, tarde: HoraDoDia, noite: HoraDoDia) {
        self.madrugada = madrugada
        self.manha = manha
        self.tarde = tarde
        self.noite = noite
    }

    public static let padrao = Horarios(
        madrugada: HoraDoDia(hora: 0), manha: HoraDoDia(hora: 6),
        tarde: HoraDoDia(hora: 12), noite: HoraDoDia(hora: 18)
    )

    public subscript(periodo: Periodo) -> HoraDoDia {
        get {
            switch periodo {
            case .madrugada: madrugada
            case .manha: manha
            case .tarde: tarde
            case .noite: noite
            }
        }
        set {
            switch periodo {
            case .madrugada: madrugada = newValue
            case .manha: manha = newValue
            case .tarde: tarde = newValue
            case .noite: noite = newValue
            }
        }
    }

    /// Primeiro período (em ordem cronológica) cujo início não respeita a ordem; `nil` se todos são válidos.
    public var primeiroInvalido: Periodo? {
        var anterior: HoraDoDia?
        for periodo in Periodo.allCases {
            let atual = self[periodo]
            if let anterior, atual <= anterior { return periodo }
            anterior = atual
        }
        return nil
    }

    public var saoValidos: Bool { primeiroInvalido == nil }
}
