import SwiftUI
import UIKit
import Observation
import WidgetKit
import PrumoKit

enum Aba: Hashable {
    case hoje, salvas, widgets, ajustes
}

enum FormatoDeWidget: String, CaseIterable, Identifiable {
    case bloqueio, pequeno, medio

    var id: String { rawValue }

    var aba: String {
        switch self {
        case .bloqueio: "Bloqueio"
        case .pequeno: "Pequeno"
        case .medio: "Médio"
        }
    }

    var nome: String {
        switch self {
        case .bloqueio: "Tela Bloqueada"
        case .pequeno: "Widget pequeno"
        case .medio: "Widget médio"
        }
    }

    var simbolo: String {
        switch self {
        case .bloqueio: "lock"
        case .pequeno: "square"
        case .medio: "rectangle"
        }
    }
}

/// Frase aberta por toque no widget, no aviso, numa salva ou no botão de contexto.
struct FraseAberta: Identifiable {
    let frase: Frase
    let origem: OrigemInteracao
    var id: String { frase.id }
}

/// Mensagem breve na base da tela, com desfazer opcional.
struct Aviso: Identifiable {
    let id = UUID()
    let mensagem: String
    let desfazer: (() -> Void)?
}

enum StatusDosLembretes: Equatable {
    case desconhecido, permitido, negado, naoPerguntado
}

@MainActor
@Observable
final class ModeloDoApp {
    let motor: Motor

    private(set) var plano: Plano
    private(set) var agora: Date
    private(set) var salvas: [Salva] = []
    private(set) var resumo: ResumoLocal
    private(set) var statusDosLembretes: StatusDosLembretes = .desconhecido

    var aba: Aba = .hoje
    var formatoDeWidget: FormatoDeWidget = .bloqueio
    var fraseAberta: FraseAberta? = nil
    private(set) var aviso: Aviso? = nil

    /// Período escolhido para prévia em Hoje. `nil` mostra o período atual.
    private(set) var periodoSelecionado: Periodo? = nil
    private(set) var leituraExibida: Leitura

    @ObservationIgnored private var tarefaDoAviso: Task<Void, Never>? = nil
    @ObservationIgnored private var idsPublicados: [String] = []

    init(motor: Motor) {
        self.motor = motor
        let plano = motor.planejar()
        self.plano = plano
        self.agora = motor.agora
        self.leituraExibida = plano.atual
        self.resumo = motor.resumoLocal()
        self.salvas = motor.salvas()
    }

    var preferencias: Preferencias { plano.preferencias }
    var periodoAtual: Periodo { plano.atual.slot.chave.periodo }
    var calendario: Calendar { motor.calendarioAtual }

    // MARK: Ciclo de vida

    /// Chamado ao abrir, ao voltar ao primeiro plano e a cada virada.
    func atualizar() {
        agora = motor.agora
        let anterior = plano.atual.slot.chave
        plano = motor.planejar()
        if plano.atual.slot.chave != anterior, periodoSelecionado == periodoAtual {
            periodoSelecionado = nil
        }
        if plano.atual.slot.chave.dia != anterior.dia { periodoSelecionado = nil }
        recalcularLeituraExibida()
        salvas = motor.salvas()
        resumo = motor.resumoLocal()
        publicarNoWidgetSeMudou()
        Task { await sincronizarLembretes() }
    }

    /// Relógio da tela. Replaneja só quando o período vigente termina.
    func tique() {
        agora = motor.agora
        if agora >= plano.atual.slot.fim { atualizar() }
    }

    private func recalcularLeituraExibida() {
        guard let periodo = periodoSelecionado, periodo != periodoAtual else {
            leituraExibida = plano.atual
            return
        }
        let chave = ChaveSlot(dia: plano.atual.slot.chave.dia, periodo: periodo)
        leituraExibida = plano.leitura(de: chave) ?? motor.leitura(de: chave)
    }

    private func publicarNoWidgetSeMudou() {
        let ids = plano.leituras.map { "\($0.slot.chave)=\($0.frase.id)" }
        guard ids != idsPublicados else { return }
        idsPublicados = ids
        WidgetCenter.shared.reloadTimelines(ofKind: Motor.kindDoWidget)
    }

    // MARK: Hoje

    func selecionar(_ periodo: Periodo) {
        periodoSelecionado = periodo == periodoAtual ? nil : periodo
        recalcularLeituraExibida()
        let f = leituraExibida.frase
        anunciar("\(periodo.nome). \(f.tema.nome). \(f.texto)")
    }

    var exibindoPeriodoAtual: Bool { leituraExibida.slot.chave == plano.atual.slot.chave }

    /// "Período atual", "Desde ontem" ou "Prévia do período".
    var descricaoDoTempo: String {
        if exibindoPeriodoAtual {
            return leituraExibida.slot.chave.dia < DataCivil(agora, calendario: calendario) ? "Desde ontem" : "Período atual"
        }
        return "Prévia do período"
    }

    // MARK: Salvas

    func estaSalva(_ frase: Frase) -> Bool { salvas.contains { $0.fraseId == frase.id } }

    func alternarSalva(_ frase: Frase) {
        if estaSalva(frase) {
            remover(frase.id)
        } else {
            do {
                try motor.salvar(frase)
                salvas = motor.salvas()
                resumo = motor.resumoLocal()
                mostrarAviso("Frase salva.")
            } catch {
                mostrarAviso("Não foi possível salvar agora. Tente de novo.")
            }
        }
    }

    func remover(_ fraseId: String) {
        do {
            guard let removida = try motor.removerSalva(fraseId) else { return }
            salvas = motor.salvas()
            resumo = motor.resumoLocal()
            mostrarAviso("Frase removida das salvas.") { [weak self] in
                guard let self else { return }
                try? self.motor.restaurar(removida)
                self.salvas = self.motor.salvas()
                self.resumo = self.motor.resumoLocal()
                self.mostrarAviso("Frase restaurada.")
            }
        } catch {
            mostrarAviso("Não foi possível remover agora. Tente de novo.")
        }
    }

    func frase(de salva: Salva) -> Frase { motor.frase(de: salva) }

    // MARK: Ajustes

    /// Valida, grava e devolve o erro para exibição. Em erro, nada muda.
    func salvarAjustes(temas: Set<Tema>, horarios: Horarios) -> ErroPreferencias? {
        var nova = preferencias
        nova.definirTemas(temas)
        nova.horarios = horarios
        if let erro = nova.validar() {
            anunciar(erro.mensagem)
            return erro
        }
        do {
            plano = try motor.atualizarPreferencias(nova)
            periodoSelecionado = nil
            recalcularLeituraExibida()
            publicarNoWidgetSeMudou()
            Task { await sincronizarLembretes() }
            mostrarAviso("Ajustes salvos.")
        } catch {
            mostrarAviso("Não foi possível gravar os ajustes. Os valores anteriores continuam valendo.")
        }
        return nil
    }

    /// Liga ou pausa os avisos. A permissão é pedida só ao ligar.
    func definirLembretes(_ ligado: Bool) async {
        if ligado {
            let permitido = await ServicoDeLembretes.pedirPermissao()
            statusDosLembretes = permitido ? .permitido : .negado
            guard permitido else {
                mostrarAviso("Avisos não autorizados. O widget continua funcionando.")
                return
            }
        }
        var nova = preferencias
        nova.lembretes = ligado
        do {
            plano = try motor.atualizarPreferencias(nova)
            await sincronizarLembretes()
            mostrarAviso(ligado ? "Lembretes ligados." : "Lembretes pausados.")
        } catch {
            mostrarAviso("Não foi possível gravar a escolha dos lembretes.")
        }
    }

    func sincronizarLembretes() async {
        statusDosLembretes = await ServicoDeLembretes.status()
        if preferencias.lembretes, statusDosLembretes == .permitido {
            let pedidos = PlanejadorDeLembretes.lembretes(para: plano, agora: motor.agora, calendario: calendario)
            await ServicoDeLembretes.reprogramar(pedidos)
        } else {
            await ServicoDeLembretes.cancelarTodos()
        }
    }

    // MARK: Links

    func abrir(_ url: URL) {
        guard let link = PrumoLink(url: url) else { return }
        switch link {
        case .frase(let id, let origem):
            guard let frase = motor.catalogo.frase(id: id) else { return }
            motor.registrarAbertura(fraseId: id, origem: origem)
            resumo = motor.resumoLocal()
            aba = .hoje
            fraseAberta = FraseAberta(frase: frase, origem: origem)
        case .hoje: aba = .hoje
        case .widgets: aba = .widgets
        case .ajustes: aba = .ajustes
        }
    }

    func abrirDetalhe(_ frase: Frase) {
        fraseAberta = FraseAberta(frase: frase, origem: .app)
    }

    // MARK: Avisos e acessibilidade

    func mostrarAviso(_ mensagem: String, desfazer: (() -> Void)? = nil) {
        tarefaDoAviso?.cancel()
        let aviso = Aviso(mensagem: mensagem, desfazer: desfazer)
        self.aviso = aviso
        anunciar(mensagem + (desfazer == nil ? "" : " É possível desfazer."))
        tarefaDoAviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(desfazer == nil ? 3.3 : 9))
            guard !Task.isCancelled, let self, self.aviso?.id == aviso.id else { return }
            self.aviso = nil
        }
    }

    func dispensarAviso() {
        tarefaDoAviso?.cancel()
        aviso = nil
    }

    func anunciar(_ mensagem: String) {
        UIAccessibility.post(notification: .announcement, argument: mensagem)
    }
}
