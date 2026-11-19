import Foundation

/// Reserva de um slot. `ativo == false` marca uma reserva substituída que continua no histórico.
public struct RegistroAgenda: Hashable, Sendable {
    public let rowId: Int64
    public let chave: ChaveSlot
    public let fraseId: String
    public let ciclo: Int
    public let versaoPreferencias: Int
    public let ativo: Bool
    public let criadoEm: Date
    public let substituidoEm: Date?
}

public struct Salva: Hashable, Sendable, Identifiable {
    public let fraseId: String
    public let salvaEm: Date
    /// Copiados no momento de salvar, para exibir a salva mesmo se o ID sumir do catálogo.
    public let temaReserva: Tema
    public let periodoReserva: Periodo
    public let textoReserva: String

    public var id: String { fraseId }

    public init(fraseId: String, salvaEm: Date, temaReserva: Tema, periodoReserva: Periodo, textoReserva: String) {
        self.fraseId = fraseId
        self.salvaEm = salvaEm
        self.temaReserva = temaReserva
        self.periodoReserva = periodoReserva
        self.textoReserva = textoReserva
    }
}

public enum TipoInteracao: String, Sendable, CaseIterable {
    case abertura
    case salva
    case removida
}

public enum OrigemInteracao: String, Sendable, CaseIterable {
    case widget
    case aviso
    case app
}

/// Persistência local em SQLite: preferências, agenda (slots programados), salvas e interações observadas.
/// App e extensão abrem o mesmo arquivo no contêiner do App Group.
public final class Armazenamento: @unchecked Sendable {
    static let versaoDoEsquema = 1
    let banco: BancoSQLite
    public let url: URL?

    public convenience init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try self.init(caminho: url.path, url: url, emArquivo: true)
    }

    /// Banco em memória, para testes e prévias.
    public static func emMemoria() throws -> Armazenamento {
        try Armazenamento(caminho: ":memory:", url: nil, emArquivo: false)
    }

    private init(caminho: String, url: URL?, emArquivo: Bool) throws {
        banco = try BancoSQLite(caminho: caminho)
        self.url = url
        try configurar(emArquivo: emArquivo)
    }

    private func configurar(emArquivo: Bool) throws {
        // Journal de rollback, não WAL: em WAL cada conexão aberta mantém um lock no arquivo -shm,
        // e o iOS encerra (0xdead10cc) um processo suspenso que segura lock num contêiner de App Group.
        // Aqui nenhum lock sobrevive ao fim de uma transação curta.
        if emArquivo { try banco.executar("PRAGMA journal_mode=DELETE") }
        try banco.executar("PRAGMA synchronous=FULL")
        try migrar()
    }

    private func migrar() throws {
        let versao = try banco.consultar("PRAGMA user_version") { Int($0.inteiro(0)) }.first ?? 0
        guard versao < Self.versaoDoEsquema else { return }
        try banco.transacao {
            try banco.executar("""
            CREATE TABLE IF NOT EXISTS meta (
                chave TEXT PRIMARY KEY,
                valor TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS agenda (
                id INTEGER PRIMARY KEY,
                dia INTEGER NOT NULL,
                periodo TEXT NOT NULL,
                frase_id TEXT NOT NULL,
                ciclo INTEGER NOT NULL,
                versao_preferencias INTEGER NOT NULL,
                ativo INTEGER NOT NULL DEFAULT 1,
                criado_em REAL NOT NULL,
                substituido_em REAL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS agenda_slot_ativo ON agenda(dia, periodo) WHERE ativo = 1;
            CREATE INDEX IF NOT EXISTS agenda_periodo_ciclo ON agenda(periodo, ciclo);
            CREATE TABLE IF NOT EXISTS salvas (
                frase_id TEXT PRIMARY KEY,
                salva_em REAL NOT NULL,
                tema TEXT NOT NULL,
                periodo TEXT NOT NULL,
                texto TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS interacoes (
                id INTEGER PRIMARY KEY,
                frase_id TEXT NOT NULL,
                tipo TEXT NOT NULL,
                origem TEXT NOT NULL,
                em REAL NOT NULL
            );
            PRAGMA user_version = \(Self.versaoDoEsquema);
            """)
        }
    }

    func transacao<T>(_ corpo: () throws -> T) throws -> T { try banco.transacao(corpo) }

    // MARK: Meta

    func meta(_ chave: String) throws -> String? {
        try banco.consultar("SELECT valor FROM meta WHERE chave = ?", [.texto(chave)]) { $0.texto(0) }.first ?? nil
    }

    func gravarMeta(_ chave: String, _ valor: String) throws {
        try banco.rodar(
            "INSERT INTO meta(chave, valor) VALUES(?, ?) ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor",
            [.texto(chave), .texto(valor)]
        )
    }

    /// Semente local do embaralhamento, criada na primeira abertura.
    func semente() throws -> UInt64 {
        try transacao {
            if let texto = try meta("semente"), let valor = UInt64(texto) { return valor }
            let nova = UInt64.random(in: 1...UInt64.max)
            try gravarMeta("semente", String(nova))
            return nova
        }
    }

    func preferencias() throws -> (Preferencias, versao: Int) {
        let versao = try meta("versao_preferencias").flatMap(Int.init) ?? 0
        guard let json = try meta("preferencias"), let dados = json.data(using: .utf8),
              let prefs = try? JSONDecoder().decode(Preferencias.self, from: dados)
        else { return (.padrao, versao) }
        return (prefs, versao)
    }

    func gravarPreferencias(_ prefs: Preferencias, versao: Int) throws {
        let dados = try JSONEncoder().encode(prefs)
        try gravarMeta("preferencias", String(decoding: dados, as: UTF8.self))
        try gravarMeta("versao_preferencias", String(versao))
    }

    // MARK: Agenda

    private static let colunasAgenda = "id, dia, periodo, frase_id, ciclo, versao_preferencias, ativo, criado_em, substituido_em"

    private func registro(_ l: LinhaSQL) -> RegistroAgenda? {
        guard let periodo = l.texto(2).flatMap(Periodo.init(rawValue:)), let frase = l.texto(3) else { return nil }
        return RegistroAgenda(
            rowId: l.inteiro(0),
            chave: ChaveSlot(dia: DataCivil(ordinal: Int(l.inteiro(1))), periodo: periodo),
            fraseId: frase,
            ciclo: Int(l.inteiro(4)),
            versaoPreferencias: Int(l.inteiro(5)),
            ativo: l.inteiro(6) != 0,
            criadoEm: Date(timeIntervalSince1970: l.real(7)),
            substituidoEm: l.ehNulo(8) ? nil : Date(timeIntervalSince1970: l.real(8))
        )
    }

    /// Todos os registros de um período (ativos e substituídos), em ordem cronológica de slot.
    public func agenda(periodo: Periodo) throws -> [RegistroAgenda] {
        try banco.consultar(
            "SELECT \(Self.colunasAgenda) FROM agenda WHERE periodo = ? ORDER BY dia, id",
            [.texto(periodo.rawValue)], linha: registro
        ).compactMap { $0 }
    }

    public func agendaCompleta() throws -> [RegistroAgenda] {
        try banco.consultar("SELECT \(Self.colunasAgenda) FROM agenda ORDER BY dia, id", linha: registro).compactMap { $0 }
    }

    public func reservaAtiva(_ chave: ChaveSlot) throws -> RegistroAgenda? {
        try banco.consultar(
            "SELECT \(Self.colunasAgenda) FROM agenda WHERE dia = ? AND periodo = ? AND ativo = 1",
            [.inteiro(Int64(chave.dia.ordinal)), .texto(chave.periodo.rawValue)], linha: registro
        ).compactMap { $0 }.first
    }

    /// Reservas ativas a partir de uma data civil (inclusive).
    func reservasAtivas(desde dia: DataCivil) throws -> [RegistroAgenda] {
        try banco.consultar(
            "SELECT \(Self.colunasAgenda) FROM agenda WHERE ativo = 1 AND dia >= ? ORDER BY dia, id",
            [.inteiro(Int64(dia.ordinal))], linha: registro
        ).compactMap { $0 }
    }

    @discardableResult
    func reservar(_ chave: ChaveSlot, fraseId: String, ciclo: Int, versaoPreferencias: Int, em data: Date) throws -> RegistroAgenda {
        try banco.rodar(
            "INSERT INTO agenda(dia, periodo, frase_id, ciclo, versao_preferencias, ativo, criado_em) VALUES(?, ?, ?, ?, ?, 1, ?)",
            [.inteiro(Int64(chave.dia.ordinal)), .texto(chave.periodo.rawValue), .texto(fraseId),
             .inteiro(Int64(ciclo)), .inteiro(Int64(versaoPreferencias)), .real(data.timeIntervalSince1970)]
        )
        return RegistroAgenda(rowId: banco.ultimoRowId, chave: chave, fraseId: fraseId, ciclo: ciclo,
                              versaoPreferencias: versaoPreferencias, ativo: true, criadoEm: data, substituidoEm: nil)
    }

    /// Desativa a reserva, que segue no histórico (e conta como vista no ciclo).
    func substituir(rowId: Int64, em data: Date) throws {
        try banco.rodar("UPDATE agenda SET ativo = 0, substituido_em = ? WHERE id = ?",
                        [.real(data.timeIntervalSince1970), .inteiro(rowId)])
    }

    /// Recicla uma reserva futura que nunca foi exibida: o ID volta a ficar disponível.
    func apagarReserva(rowId: Int64) throws {
        try banco.rodar("DELETE FROM agenda WHERE id = ? AND ativo = 1", [.inteiro(rowId)])
    }

    // MARK: Salvas

    public func salvas() throws -> [Salva] {
        try banco.consultar("SELECT frase_id, salva_em, tema, periodo, texto FROM salvas ORDER BY salva_em DESC, frase_id") { l in
            guard let id = l.texto(0), let tema = l.texto(2).flatMap(Tema.init(rawValue:)),
                  let periodo = l.texto(3).flatMap(Periodo.init(rawValue:)), let texto = l.texto(4) else { return nil }
            return Salva(fraseId: id, salvaEm: Date(timeIntervalSince1970: l.real(1)),
                         temaReserva: tema, periodoReserva: periodo, textoReserva: texto)
        }.compactMap { $0 }
    }

    public func salva(id: String) throws -> Salva? {
        try salvas().first { $0.fraseId == id }
    }

    func gravarSalva(_ salva: Salva) throws {
        try banco.rodar(
            "INSERT INTO salvas(frase_id, salva_em, tema, periodo, texto) VALUES(?, ?, ?, ?, ?) ON CONFLICT(frase_id) DO NOTHING",
            [.texto(salva.fraseId), .real(salva.salvaEm.timeIntervalSince1970), .texto(salva.temaReserva.rawValue),
             .texto(salva.periodoReserva.rawValue), .texto(salva.textoReserva)]
        )
    }

    func apagarSalva(id: String) throws {
        try banco.rodar("DELETE FROM salvas WHERE frase_id = ?", [.texto(id)])
    }

    // MARK: Interações observadas

    func registrarInteracao(fraseId: String, tipo: TipoInteracao, origem: OrigemInteracao, em data: Date) throws {
        try banco.rodar(
            "INSERT INTO interacoes(frase_id, tipo, origem, em) VALUES(?, ?, ?, ?)",
            [.texto(fraseId), .texto(tipo.rawValue), .texto(origem.rawValue), .real(data.timeIntervalSince1970)]
        )
    }

    func contagemInteracoes(tipo: TipoInteracao, origem: OrigemInteracao) throws -> Int {
        try banco.consultar("SELECT COUNT(*) FROM interacoes WHERE tipo = ? AND origem = ?",
                            [.texto(tipo.rawValue), .texto(origem.rawValue)]) { Int($0.inteiro(0)) }.first ?? 0
    }
}
