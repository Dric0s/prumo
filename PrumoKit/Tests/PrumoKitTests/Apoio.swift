import Foundation
@testable import PrumoKit

final class RelogioDeTeste: @unchecked Sendable {
    private let trava = NSLock()
    private var valor: Date

    init(_ data: Date) { valor = data }

    var agora: Date {
        get { trava.lock(); defer { trava.unlock() }; return valor }
        set { trava.lock(); valor = newValue; trava.unlock() }
    }

    func avancar(_ segundos: TimeInterval) { agora = agora.addingTimeInterval(segundos) }
}

final class FusoDeTeste: @unchecked Sendable {
    private let trava = NSLock()
    private var valor: Calendar

    init(_ identificador: String) { valor = PrumoKitTests.calendario(identificador) }

    var calendario: Calendar {
        get { trava.lock(); defer { trava.unlock() }; return valor }
        set { trava.lock(); valor = newValue; trava.unlock() }
    }
}

func calendario(_ fuso: String) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: fuso)!
    c.locale = Locale(identifier: "pt_BR")
    return c
}

let saoPaulo = calendario("America/Sao_Paulo")

/// Data local num calendário: `data(2026, 11, 18, 11, 38)`.
func data(_ ano: Int, _ mes: Int, _ dia: Int, _ hora: Int = 0, _ minuto: Int = 0, em cal: Calendar = saoPaulo) -> Date {
    cal.date(from: DateComponents(year: ano, month: mes, day: dia, hour: hora, minute: minuto))!
}

func catalogoReal() throws -> Catalogo { try Catalogo.embarcado() }

func diretorioTemporario() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("prumo-testes-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func motor(
    armazenamento: Armazenamento? = nil,
    relogio: RelogioDeTeste,
    fuso: FusoDeTeste = FusoDeTeste("America/Sao_Paulo"),
    espelho: EspelhoDePreferencias? = nil,
    semArmazenamento: Bool = false
) throws -> Motor {
    let banco: Armazenamento? = semArmazenamento ? nil : try (armazenamento ?? Armazenamento.emMemoria())
    return Motor(
        catalogo: try catalogoReal(), armazenamento: banco, espelho: espelho,
        calendario: { fuso.calendario }, relogio: { relogio.agora }
    )
}
