import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite)
import CSQLite
#endif

public struct ErroSQLite: Error, CustomStringConvertible, Sendable {
    public let codigo: Int32
    public let mensagem: String

    public var description: String { "SQLite \(codigo): \(mensagem)" }

    /// `SQLITE_CONSTRAINT` e variações estendidas.
    var violouRestricao: Bool { codigo & 0xff == SQLITE_CONSTRAINT }
}

enum ValorSQL: Sendable {
    case inteiro(Int64)
    case real(Double)
    case texto(String)
    case nulo
}

/// Leitura de uma linha do resultado.
struct LinhaSQL {
    fileprivate let statement: OpaquePointer

    func inteiro(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
    func real(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
    func texto(_ i: Int32) -> String? {
        guard let ptr = sqlite3_column_text(statement, i) else { return nil }
        return String(cString: ptr)
    }
    func ehNulo(_ i: Int32) -> Bool { sqlite3_column_type(statement, i) == SQLITE_NULL }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Conexão SQLite mínima. Uma trava serializa o acesso dentro do processo;
/// `BEGIN IMMEDIATE` e o `busy_timeout` coordenam app e extensão no App Group.
final class BancoSQLite: @unchecked Sendable {
    private var handle: OpaquePointer?
    private let trava = NSRecursiveLock()
    private var emTransacao = false

    init(caminho: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(caminho, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "falha ao abrir"
            if let db { sqlite3_close_v2(db) }
            throw ErroSQLite(codigo: rc, mensagem: msg)
        }
        handle = db
        sqlite3_busy_timeout(db, 5_000)
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    private func erro(_ rc: Int32) -> ErroSQLite {
        ErroSQLite(codigo: sqlite3_extended_errcode(handle), mensagem: String(cString: sqlite3_errmsg(handle)))
    }

    func executar(_ sql: String) throws {
        trava.lock(); defer { trava.unlock() }
        var mensagem: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &mensagem)
        if rc != SQLITE_OK {
            let texto = mensagem.map { String(cString: $0) } ?? "erro"
            sqlite3_free(mensagem)
            throw ErroSQLite(codigo: rc, mensagem: texto)
        }
    }

    private func preparar(_ sql: String, _ valores: [ValorSQL]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw erro(rc) }
        for (i, valor) in valores.enumerated() {
            let pos = Int32(i + 1)
            let r: Int32 = switch valor {
            case .inteiro(let v): sqlite3_bind_int64(stmt, pos, v)
            case .real(let v): sqlite3_bind_double(stmt, pos, v)
            case .texto(let v): sqlite3_bind_text(stmt, pos, v, -1, SQLITE_TRANSIENT)
            case .nulo: sqlite3_bind_null(stmt, pos)
            }
            if r != SQLITE_OK {
                sqlite3_finalize(stmt)
                throw erro(r)
            }
        }
        return stmt
    }

    func rodar(_ sql: String, _ valores: [ValorSQL] = []) throws {
        trava.lock(); defer { trava.unlock() }
        let stmt = try preparar(sql, valores)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw erro(rc) }
    }

    func consultar<T>(_ sql: String, _ valores: [ValorSQL] = [], linha: (LinhaSQL) throws -> T) throws -> [T] {
        trava.lock(); defer { trava.unlock() }
        let stmt = try preparar(sql, valores)
        defer { sqlite3_finalize(stmt) }
        var resultado: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw erro(rc) }
            resultado.append(try linha(LinhaSQL(statement: stmt)))
        }
        return resultado
    }

    var ultimoRowId: Int64 { sqlite3_last_insert_rowid(handle) }
    var alteracoes: Int { Int(sqlite3_changes(handle)) }

    /// Transação curta com trava de escrita desde o início (`BEGIN IMMEDIATE`).
    /// Chamadas aninhadas reaproveitam a transação externa.
    func transacao<T>(_ corpo: () throws -> T) throws -> T {
        trava.lock(); defer { trava.unlock() }
        if emTransacao { return try corpo() }
        try executar("BEGIN IMMEDIATE")
        emTransacao = true
        do {
            let valor = try corpo()
            emTransacao = false
            try executar("COMMIT")
            return valor
        } catch {
            emTransacao = false
            try? executar("ROLLBACK")
            throw error
        }
    }
}
