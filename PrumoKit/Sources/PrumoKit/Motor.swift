import Foundation

/// Frase associada a um slot.
public struct Leitura: Hashable, Sendable, Identifiable {
    public let slot: Slot
    public let frase: Frase
    /// `true` quando veio da leitura de reserva do bundle (armazenamento indisponível).
    /// Uma leitura de reserva não é gravada como vista.
    public let reserva: Bool

    public var id: ChaveSlot { slot.chave }
}

/// Slot vigente e os seguintes dentro do horizonte, com a mesma seleção para telas, widget e avisos.
public struct Plano: Sendable {
    public let leituras: [Leitura]
    public let preferencias: Preferencias
    public let geradoEm: Date

    public var atual: Leitura { leituras[0] }
    public var reserva: Bool { leituras.contains { $0.reserva } }

    public func leitura(de chave: ChaveSlot) -> Leitura? { leituras.first { $0.slot.chave == chave } }
}

public struct ResumoLocal: Hashable, Sendable {
    public let salvas: Int
    public let aberturasPeloWidget: Int
    public let aberturasPeloAviso: Int

    /// Texto que a pessoa pode compartilhar voluntariamente com o piloto.
    public var textoParaCompartilhar: String {
        """
        Prumo · resumo local
        Frases salvas: \(salvas)
        Aberturas pelo widget: \(aberturasPeloWidget)
        Aberturas pelo aviso: \(aberturasPeloAviso)
        """
    }
}

public enum ErroMotor: Error, Equatable, Sendable {
    case armazenamentoIndisponivel
    case fraseDesconhecida(String)
}

/// Motor compartilhado por app, widget e lembretes.
/// Resolve períodos, reserva IDs por slot em transação e devolve sempre o mesmo ID para o mesmo slot.
public final class Motor: @unchecked Sendable {
    public static let horizonteEmDias = 7

    public let catalogo: Catalogo
    public let armazenamento: Armazenamento?
    public let espelho: EspelhoDePreferencias?
    private let calendario: @Sendable () -> Calendar
    private let relogio: @Sendable () -> Date

    /// - Parameters:
    ///   - armazenamento: `nil` quando o contêiner compartilhado não pôde ser aberto; o motor usa leituras de reserva.
    ///   - espelho: cópia legível das preferências, usada pela leitura de reserva.
    ///   - calendario: avaliado a cada chamada, para acompanhar mudanças de fuso.
    ///   - relogio: injetável nos testes.
    public init(
        catalogo: Catalogo,
        armazenamento: Armazenamento?,
        espelho: EspelhoDePreferencias? = nil,
        calendario: @escaping @Sendable () -> Calendar = { Calendar.current },
        relogio: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.catalogo = catalogo
        self.armazenamento = armazenamento
        self.espelho = espelho
        self.calendario = calendario
        self.relogio = relogio
    }

    public var agora: Date { relogio() }
    public var calendarioAtual: Calendar { calendario() }

    // MARK: Preferências

    public func preferencias() -> Preferencias {
        if let armazenamento, let (prefs, _) = try? armazenamento.preferencias() { return prefs }
        return espelho?.ler() ?? .padrao
    }

    public func resolvedor(_ prefs: Preferencias? = nil) -> ResolvedorDePeriodos {
        ResolvedorDePeriodos(calendario: calendario(), horarios: (prefs ?? preferencias()).horarios)
    }

    /// Valida e grava. Se temas ou horários mudarem: mantém favoritos e slots decorridos,
    /// recicla reservas futuras e substitui a atual se o tema dela deixou de valer.
    @discardableResult
    public func atualizarPreferencias(_ nova: Preferencias) throws -> Plano {
        if let erro = nova.validar() { throw erro }
        guard let armazenamento else { throw ErroMotor.armazenamentoIndisponivel }
        let agora = relogio()
        let cal = calendario()
        try armazenamento.transacao {
            let (antiga, versao) = try armazenamento.preferencias()
            let mudouSelecao = antiga.temas != nova.temas || antiga.horarios != nova.horarios
            guard mudouSelecao else {
                try armazenamento.gravarPreferencias(nova, versao: versao)
                return
            }
            try armazenamento.gravarPreferencias(nova, versao: versao + 1)
            let atualAntigo = ResolvedorDePeriodos(calendario: cal, horarios: antiga.horarios).slot(contendo: agora).chave
            let atualNovo = ResolvedorDePeriodos(calendario: cal, horarios: nova.horarios).slot(contendo: agora).chave
            // O que já esteve na tela (até o slot vigente, pelos horários antigos ou novos) fica no histórico.
            let limiar = max(atualAntigo, atualNovo)
            for registro in try armazenamento.reservasAtivas(desde: limiar.dia) where registro.chave > limiar {
                try armazenamento.apagarReserva(rowId: registro.rowId)
            }
        }
        espelho?.gravar(nova)
        return planejar()
    }

    // MARK: Plano

    /// Garante reservas do slot vigente até o horizonte, numa transação, e devolve o plano.
    /// Um pedido repetido devolve os mesmos IDs.
    public func planejar(dias: Int = Motor.horizonteEmDias) -> Plano {
        let agora = relogio()
        let cal = calendario()
        guard let armazenamento else { return planoDeReserva(agora: agora, calendario: cal, dias: dias) }
        do {
            let plano = try armazenamento.transacao { () throws -> Plano in
                let (prefs, versao) = try armazenamento.preferencias()
                let resolvedor = ResolvedorDePeriodos(calendario: cal, horarios: prefs.horarios)
                let slots = resolvedor.slots(apartirDe: agora, ate: limite(resolvedor, agora, dias))
                let atual = slots[0].chave

                // 1. Revisa reservas existentes.
                var vigentes: [ChaveSlot: Frase] = [:]
                for slot in slots {
                    guard let registro = try armazenamento.reservaAtiva(slot.chave) else { continue }
                    let frase = catalogo.frase(id: registro.fraseId)
                    let futuro = slot.chave > atual
                    if futuro && registro.versaoPreferencias != versao {
                        // Reservada sob outras preferências e ainda não exibida: recicla.
                        try armazenamento.apagarReserva(rowId: registro.rowId)
                    } else if let frase, prefs.temas.contains(frase.tema) {
                        vigentes[slot.chave] = frase
                    } else {
                        // Tema desativado ou ID fora do catálogo: preserva no histórico e reserva outro.
                        try armazenamento.substituir(rowId: registro.rowId, em: agora)
                    }
                }

                // 2. Reserva o que falta, em ordem cronológica.
                var selecionador = Selecionador(
                    catalogo: catalogo, temas: prefs.temas, semente: try armazenamento.semente(),
                    carregar: { try armazenamento.agenda(periodo: $0) }
                )
                var leituras: [Leitura] = []
                leituras.reserveCapacity(slots.count)
                for slot in slots {
                    let frase: Frase
                    if let vigente = vigentes[slot.chave] {
                        frase = vigente
                    } else {
                        let escolha = try selecionador.escolher(para: slot.chave)
                        try armazenamento.reservar(slot.chave, fraseId: escolha.frase.id, ciclo: escolha.ciclo,
                                                   versaoPreferencias: versao, em: agora)
                        frase = escolha.frase
                    }
                    leituras.append(Leitura(slot: slot, frase: frase, reserva: false))
                }
                return Plano(leituras: leituras, preferencias: prefs, geradoEm: agora)
            }
            if let espelho, !espelho.existe { espelho.gravar(plano.preferencias) }
            return plano
        } catch {
            return planoDeReserva(agora: agora, calendario: cal, dias: dias)
        }
    }

    /// Leitura de um slot qualquer: do plano, se estiver no horizonte; senão, a reserva gravada.
    /// Um slot passado sem reserva (por exemplo, a manhã de hoje na primeira abertura à tarde) é reservado agora,
    /// para que a mesma prévia mostre sempre o mesmo ID.
    public func leitura(de chave: ChaveSlot) -> Leitura {
        let plano = planejar()
        if let leitura = plano.leitura(de: chave) { return leitura }
        let resolvedor = ResolvedorDePeriodos(calendario: calendario(), horarios: plano.preferencias.horarios)
        let slot = resolvedor.slot(de: chave)
        guard let armazenamento else {
            return Leitura(slot: slot, frase: LeituraDeReserva.frase(para: chave, temas: plano.preferencias.temas, catalogo: catalogo), reserva: true)
        }
        do {
            return try armazenamento.transacao {
                let (prefs, versao) = try armazenamento.preferencias()
                if let registro = try armazenamento.reservaAtiva(chave), let frase = catalogo.frase(id: registro.fraseId) {
                    return Leitura(slot: slot, frase: frase, reserva: false)
                }
                var selecionador = Selecionador(
                    catalogo: catalogo, temas: prefs.temas, semente: try armazenamento.semente(),
                    carregar: { try armazenamento.agenda(periodo: $0) }
                )
                let escolha = try selecionador.escolher(para: chave)
                try armazenamento.reservar(chave, fraseId: escolha.frase.id, ciclo: escolha.ciclo,
                                           versaoPreferencias: versao, em: relogio())
                return Leitura(slot: slot, frase: escolha.frase, reserva: false)
            }
        } catch {
            return Leitura(slot: slot, frase: LeituraDeReserva.frase(para: chave, temas: plano.preferencias.temas, catalogo: catalogo), reserva: true)
        }
    }

    private func limite(_ resolvedor: ResolvedorDePeriodos, _ agora: Date, _ dias: Int) -> Date {
        resolvedor.calendario.date(byAdding: .day, value: dias, to: agora) ?? agora.addingTimeInterval(Double(dias) * 86_400)
    }

    private func planoDeReserva(agora: Date, calendario: Calendar, dias: Int) -> Plano {
        let prefs = espelho?.ler() ?? .padrao
        let resolvedor = ResolvedorDePeriodos(calendario: calendario, horarios: prefs.horarios)
        let slots = resolvedor.slots(apartirDe: agora, ate: limite(resolvedor, agora, dias))
        let leituras = slots.map {
            Leitura(slot: $0, frase: LeituraDeReserva.frase(para: $0.chave, temas: prefs.temas, catalogo: catalogo), reserva: true)
        }
        return Plano(leituras: leituras, preferencias: prefs, geradoEm: agora)
    }

    // MARK: Salvas

    public func salvas() -> [Salva] { (try? armazenamento?.salvas()) ?? [] }

    public func estaSalva(_ fraseId: String) -> Bool { ((try? armazenamento?.salva(id: fraseId)) ?? nil) != nil }

    @discardableResult
    public func salvar(_ frase: Frase) throws -> Salva {
        guard let armazenamento else { throw ErroMotor.armazenamentoIndisponivel }
        let agora = relogio()
        let salva = Salva(fraseId: frase.id, salvaEm: agora, temaReserva: frase.tema,
                          periodoReserva: frase.periodo, textoReserva: frase.texto)
        try armazenamento.transacao {
            try armazenamento.gravarSalva(salva)
            try armazenamento.registrarInteracao(fraseId: frase.id, tipo: .salva, origem: .app, em: agora)
        }
        return try armazenamento.salva(id: frase.id) ?? salva
    }

    /// Remove e devolve a salva, para permitir desfazer.
    @discardableResult
    public func removerSalva(_ fraseId: String) throws -> Salva? {
        guard let armazenamento else { throw ErroMotor.armazenamentoIndisponivel }
        return try armazenamento.transacao {
            guard let salva = try armazenamento.salva(id: fraseId) else { return nil }
            try armazenamento.apagarSalva(id: fraseId)
            try armazenamento.registrarInteracao(fraseId: fraseId, tipo: .removida, origem: .app, em: relogio())
            return salva
        }
    }

    /// Desfaz uma remoção, mantendo a data original de salvamento.
    public func restaurar(_ salva: Salva) throws {
        guard let armazenamento else { throw ErroMotor.armazenamentoIndisponivel }
        try armazenamento.transacao {
            try armazenamento.gravarSalva(salva)
            try armazenamento.registrarInteracao(fraseId: salva.fraseId, tipo: .salva, origem: .app, em: relogio())
        }
    }

    /// Frase de uma salva: o registro atual do catálogo, ou o texto de reserva se o ID tiver saído.
    public func frase(de salva: Salva) -> Frase {
        catalogo.frase(id: salva.fraseId) ?? Frase(
            id: salva.fraseId, tema: salva.temaReserva, periodo: salva.periodoReserva,
            curta: salva.textoReserva, texto: salva.textoReserva
        )
    }

    // MARK: Interações observadas

    /// Registra a abertura por toque. Olhar para a Tela Bloqueada não gera evento.
    public func registrarAbertura(fraseId: String, origem: OrigemInteracao) {
        try? armazenamento?.registrarInteracao(fraseId: fraseId, tipo: .abertura, origem: origem, em: relogio())
    }

    public func resumoLocal() -> ResumoLocal {
        let a = armazenamento
        return ResumoLocal(
            salvas: salvas().count,
            aberturasPeloWidget: (try? a?.contagemInteracoes(tipo: .abertura, origem: .widget)) ?? 0,
            aberturasPeloAviso: (try? a?.contagemInteracoes(tipo: .abertura, origem: .aviso)) ?? 0
        )
    }
}

/// Cópia das preferências fora do banco, legível antes do primeiro desbloqueio
/// (sem proteção de arquivo). Só contém temas, horários e o estado dos lembretes.
public struct EspelhoDePreferencias: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public var existe: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func ler() -> Preferencias? {
        guard let dados = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Preferencias.self, from: dados)
    }

    public func gravar(_ prefs: Preferencias) {
        guard let dados = try? JSONEncoder().encode(prefs) else { return }
        #if os(iOS)
        try? dados.write(to: url, options: [.atomic, .noFileProtection])
        #else
        try? dados.write(to: url, options: [.atomic])
        #endif
    }
}
