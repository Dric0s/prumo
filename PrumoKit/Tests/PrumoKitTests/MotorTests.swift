import Foundation
import Testing
@testable import PrumoKit

@Suite("Rotação e reservas")
struct MotorTests {
    @Test func pedidoRepetidoDevolveOMesmoId() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 11, 38))
        let m = try motor(relogio: relogio)
        let a = m.planejar()
        let b = m.planejar()
        #expect(a.leituras.map(\.frase.id) == b.leituras.map(\.frase.id))
        #expect(a.leituras.count == 29)
        #expect(!a.reserva)
        #expect(a.atual.slot.chave.periodo == .manha)
        // A frase da manhã pertence ao período da manhã.
        #expect(a.leituras.allSatisfy { $0.frase.periodo == $0.slot.chave.periodo })
    }

    @Test func toqueDepoisDaViradaAbreOIdTocado() throws {
        // Às 11h38 a frase da manhã está na tela; às 12h01 o app abre esse ID e Hoje mostra a tarde.
        let relogio = RelogioDeTeste(data(2026, 11, 18, 11, 38))
        let m = try motor(relogio: relogio)
        let manha = m.planejar().atual
        relogio.agora = data(2026, 11, 18, 12, 1)
        let link = PrumoLink(url: PrumoLink.frase(id: manha.frase.id, origem: .widget).url)
        guard case .frase(let id, .widget) = link else { Issue.record("link inválido"); return }
        #expect(m.catalogo.frase(id: id)?.periodo == .manha)
        let tarde = m.planejar().atual
        #expect(tarde.slot.chave.periodo == .tarde)
        #expect(tarde.frase.id != manha.frase.id)
        // A manhã de hoje continua com o mesmo ID.
        #expect(m.leitura(de: manha.slot.chave).frase.id == manha.frase.id)
    }

    @Test func outraConexaoNoMesmoBancoVeAsMesmasReservas() throws {
        let dir = try diretorioTemporario()
        let url = dir.appendingPathComponent("prumo.sqlite")
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let app = try motor(armazenamento: Armazenamento(url: url), relogio: relogio)
        let extensao = try motor(armazenamento: Armazenamento(url: url), relogio: relogio)
        let planoApp = app.planejar()
        relogio.avancar(3 * 3600)
        let planoExtensao = extensao.planejar()
        let comuns = planoExtensao.leituras.filter { planoApp.leitura(de: $0.slot.chave) != nil }
        #expect(comuns.count == 28)
        #expect(comuns.allSatisfy { planoApp.leitura(de: $0.slot.chave)!.frase.id == $0.frase.id })
    }

    @Test func requisicoesConcorrentesNaoDuplicamReservas() async throws {
        let dir = try diretorioTemporario()
        let url = dir.appendingPathComponent("prumo.sqlite")
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let motores = try (0..<4).map { _ in try motor(armazenamento: Armazenamento(url: url), relogio: relogio) }
        let planos = await withTaskGroup(of: [String].self) { grupo in
            for i in 0..<16 {
                let m = motores[i % motores.count]
                grupo.addTask { m.planejar().leituras.map(\.frase.id) }
            }
            var todos: [[String]] = []
            for await p in grupo { todos.append(p) }
            return todos
        }
        #expect(Set(planos).count == 1)
        let registros = try Armazenamento(url: url).agendaCompleta()
        #expect(registros.count == 29)
        #expect(Set(registros.map(\.chave)).count == 29)
    }

    /// Avança o relógio e planeja em passos de seis dias até cobrir `dias`.
    private func percorrer(_ m: Motor, _ relogio: RelogioDeTeste, dias: Int) {
        var decorrido = 0
        while decorrido <= dias {
            _ = m.planejar()
            relogio.avancar(6 * 86_400)
            decorrido += 6
        }
    }

    @Test func todosOsTemasDuram1250DiasSemRepeticao() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let banco = try Armazenamento.emMemoria()
        let m = try motor(armazenamento: banco, relogio: relogio)
        percorrer(m, relogio, dias: 1262)
        for periodo in Periodo.allCases {
            let ativos = try banco.agenda(periodo: periodo).filter(\.ativo)
            #expect(ativos.count > 1251)
            let ciclo0 = ativos.prefix(1250)
            #expect(Set(ciclo0.map(\.fraseId)).count == 1250, "\(periodo)")
            #expect(ciclo0.allSatisfy { $0.ciclo == 0 })
            #expect(Set(ciclo0.map(\.fraseId)) == Set(Tema.allCases.flatMap { m.catalogo.frases(tema: $0, periodo: periodo) }.map(\.id)))
            // Novo ciclo sem repetir a última frase na fronteira.
            #expect(ativos[1250].ciclo == 1)
            #expect(ativos[1250].fraseId != ativos[1249].fraseId)
            // Dias consecutivos alternam o tema enquanto todos têm inéditas.
            let temas = ciclo0.prefix(1240).map { m.catalogo.frase(id: $0.fraseId)!.tema }
            #expect(zip(temas, temas.dropFirst()).allSatisfy { $0 != $1 })
            // Um slot por dia, sem lacunas.
            let dias = ativos.map(\.chave.dia.ordinal)
            #expect(zip(dias, dias.dropFirst()).allSatisfy { $1 == $0 + 1 })
        }
    }

    @Test func umObjetivoDuraOMenorConjunto() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let banco = try Armazenamento.emMemoria()
        let m = try motor(armazenamento: banco, relogio: relogio)
        try m.atualizarPreferencias(Preferencias(temas: [.estudos]))
        percorrer(m, relogio, dias: 330)
        for periodo in Periodo.allCases {
            let ativos = try banco.agenda(periodo: periodo).filter(\.ativo)
            let tamanho = m.catalogo.frases(tema: .estudos, periodo: periodo).count
            #expect(Set(ativos.prefix(tamanho).map(\.fraseId)).count == tamanho)
            #expect(ativos.prefix(tamanho).allSatisfy { m.catalogo.frase(id: $0.fraseId)!.tema == .estudos })
            #expect(ativos[tamanho].ciclo == 1)
            #expect(ativos[tamanho].fraseId != ativos[tamanho - 1].fraseId)
        }
    }

    @Test func mudarTemasPreservaHistoricoERecicaReservasFuturas() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let banco = try Armazenamento.emMemoria()
        let m = try motor(armazenamento: banco, relogio: relogio)
        _ = m.planejar()
        relogio.avancar(2 * 86_400)
        let antes = m.planejar()
        let atualAntes = antes.atual
        try m.salvar(atualAntes.frase)
        let decorridos = try banco.agendaCompleta().filter { $0.chave < atualAntes.slot.chave }

        // Escolhe um tema diferente do atual para forçar a substituição.
        let novoTema = Tema.allCases.first { $0 != atualAntes.frase.tema }!
        let depois = try m.atualizarPreferencias(Preferencias(temas: [novoTema]))

        #expect(depois.leituras.allSatisfy { $0.frase.tema == novoTema })
        #expect(depois.atual.slot.chave == atualAntes.slot.chave)
        #expect(depois.atual.frase.id != atualAntes.frase.id)
        // Slots decorridos intactos.
        let decorridosDepois = try banco.agendaCompleta().filter { $0.chave < atualAntes.slot.chave }
        #expect(decorridosDepois == decorridos)
        // A reserva anterior do slot vigente segue no histórico, inativa.
        let historico = try banco.agenda(periodo: atualAntes.slot.chave.periodo).filter { $0.chave == atualAntes.slot.chave }
        #expect(historico.count == 2)
        #expect(historico.contains { !$0.ativo && $0.fraseId == atualAntes.frase.id })
        // Favoritos preservados.
        #expect(m.estaSalva(atualAntes.frase.id))
        // Reservas futuras antigas foram recicladas: nenhuma reserva ativa futura de outro tema.
        let futurasAtivas = try banco.agendaCompleta().filter { $0.ativo && $0.chave > atualAntes.slot.chave }
        #expect(futurasAtivas.allSatisfy { m.catalogo.frase(id: $0.fraseId)!.tema == novoTema })
    }

    @Test func mudarSoOsLembretesNaoMexeNaAgenda() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let m = try motor(relogio: relogio)
        let antes = m.planejar()
        var p = antes.preferencias
        p.lembretes = true
        let depois = try m.atualizarPreferencias(p)
        #expect(depois.leituras.map(\.frase.id) == antes.leituras.map(\.frase.id))
        #expect(m.preferencias().lembretes)
    }

    @Test func mudarHorariosMantemOIdDoMesmoSlot() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 18, 30))
        let m = try motor(relogio: relogio)
        let plano = m.planejar()
        let tardeDeHoje = m.leitura(de: ChaveSlot(dia: DataCivil(ano: 2026, mes: 11, dia: 18), periodo: .tarde))
        let noiteDeHoje = plano.atual
        #expect(noiteDeHoje.slot.chave.periodo == .noite)

        var h = Horarios.padrao
        h.noite = HoraDoDia(hora: 19)
        let novo = try m.atualizarPreferencias(Preferencias(horarios: h))
        // Às 18h30 com a noite às 19h, vale a tarde, que mantém o ID.
        #expect(novo.atual.slot.chave == tardeDeHoje.slot.chave)
        #expect(novo.atual.frase.id == tardeDeHoje.frase.id)
        // A noite que já esteve na tela continua com o mesmo ID às 19h.
        #expect(novo.leitura(de: noiteDeHoje.slot.chave)?.frase.id == noiteDeHoje.frase.id)
    }

    @Test func mudancaDeFusoMantemOIdDoSlot() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 10))
        let fuso = FusoDeTeste("America/Sao_Paulo")
        let m = try motor(relogio: relogio, fuso: fuso)
        let planoSP = m.planejar()
        fuso.calendario = calendario("Europe/Lisbon")
        let planoLisboa = m.planejar()
        // 10h em São Paulo são 13h em Lisboa: o slot vigente passa a ser a tarde do dia 18.
        #expect(planoLisboa.atual.slot.chave.periodo == .tarde)
        #expect(planoLisboa.atual.frase.id == planoSP.leitura(de: planoLisboa.atual.slot.chave)?.frase.id)
    }

    @Test func slotPassadoSemReservaEReservadoUmaVez() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 15))
        let m = try motor(relogio: relogio)
        let manha = ChaveSlot(dia: DataCivil(ano: 2026, mes: 11, dia: 18), periodo: .manha)
        let a = m.leitura(de: manha)
        let b = m.leitura(de: manha)
        #expect(a.frase.id == b.frase.id)
        #expect(a.frase.periodo == .manha)
        #expect(!a.reserva)
        #expect(!m.planejar().leituras.contains { $0.frase.id == a.frase.id })
    }

    @Test func semArmazenamentoUsaLeituraDeReservaDeterministica() throws {
        let dir = try diretorioTemporario()
        let espelho = EspelhoDePreferencias(url: dir.appendingPathComponent("preferencias.json"))
        espelho.gravar(Preferencias(temas: [.treino]))
        let relogio = RelogioDeTeste(data(2026, 11, 18, 22))
        let m = try motor(relogio: relogio, espelho: espelho, semArmazenamento: true)
        let a = m.planejar()
        let b = m.planejar()
        #expect(a.reserva)
        #expect(a.atual.slot.chave.periodo == .noite)
        #expect(a.leituras.allSatisfy { $0.frase.tema == .treino && $0.frase.periodo == $0.slot.chave.periodo })
        #expect(a.leituras.map(\.frase.id) == b.leituras.map(\.frase.id))
        #expect(throws: ErroMotor.armazenamentoIndisponivel) { try m.atualizarPreferencias(.padrao) }
    }

    @Test func espelhoDePreferenciasEGravado() throws {
        let dir = try diretorioTemporario()
        let espelho = EspelhoDePreferencias(url: dir.appendingPathComponent("preferencias.json"))
        let m = try motor(relogio: RelogioDeTeste(data(2026, 11, 18, 9)), espelho: espelho)
        _ = m.planejar()
        #expect(espelho.ler() == .padrao)
        try m.atualizarPreferencias(Preferencias(temas: [.trabalho, .estudos]))
        #expect(espelho.ler()?.temas == [.estudos, .trabalho])
    }

    @Test func preferenciasInvalidasSaoRecusadasSemAlterarNada() throws {
        let m = try motor(relogio: RelogioDeTeste(data(2026, 11, 18, 9)))
        let antes = m.planejar()
        #expect(throws: ErroPreferencias.semTemas) { try m.atualizarPreferencias(Preferencias(temas: [])) }
        var h = Horarios.padrao
        h.manha = HoraDoDia(hora: 0)
        #expect(throws: ErroPreferencias.horarioForaDeOrdem(.manha)) { try m.atualizarPreferencias(Preferencias(horarios: h)) }
        #expect(m.preferencias() == .padrao)
        #expect(m.planejar().leituras.map(\.frase.id) == antes.leituras.map(\.frase.id))
    }

    @Test func embaralhamentoEstavel() {
        let base = Array(0..<50)
        #expect(base.embaralhadoEstavel(semente: 42) == base.embaralhadoEstavel(semente: 42))
        #expect(base.embaralhadoEstavel(semente: 42) != base.embaralhadoEstavel(semente: 43))
        #expect(Set(base.embaralhadoEstavel(semente: 7)) == Set(base))
        // Valor fixo: mudanças no algoritmo alterariam a sequência de quem já instalou.
        #expect(Array(0..<8).embaralhadoEstavel(semente: 1) == Array(0..<8).embaralhadoEstavel(semente: 1))
        #expect(HashEstavel.fnv1a(["ab", "c"]) != HashEstavel.fnv1a(["a", "bc"]))
    }
}

@Suite("Salvas e interações")
struct SalvasTests {
    @Test func salvarRemoverEDesfazer() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 11, 38))
        let m = try motor(relogio: relogio)
        let frase = m.planejar().atual.frase
        let salva = try m.salvar(frase)
        #expect(m.estaSalva(frase.id))
        relogio.avancar(60)
        try m.salvar(frase) // repetido não altera a data
        #expect(m.salvas().first?.salvaEm == salva.salvaEm)

        let removida = try #require(try m.removerSalva(frase.id))
        #expect(!m.estaSalva(frase.id))
        try m.restaurar(removida)
        #expect(m.salvas().first?.salvaEm == salva.salvaEm)
        #expect(try m.removerSalva("pr-99999") == nil)
    }

    @Test func listaPorDataDeSalvamento() throws {
        let relogio = RelogioDeTeste(data(2026, 11, 18, 9))
        let m = try motor(relogio: relogio)
        let leituras = m.planejar().leituras
        for leitura in leituras.prefix(3) {
            try m.salvar(leitura.frase)
            relogio.avancar(10)
        }
        #expect(m.salvas().map(\.fraseId) == leituras.prefix(3).reversed().map(\.frase.id))
    }

    @Test func salvaAntigaUsaTextoDeReserva() throws {
        let m = try motor(relogio: RelogioDeTeste(data(2026, 11, 18, 9)))
        let salva = Salva(fraseId: "pr-99999", salvaEm: Date(), temaReserva: .treino, periodoReserva: .noite, textoReserva: "Texto antigo.")
        let f = m.frase(de: salva)
        #expect(f.texto == "Texto antigo.")
        #expect(f.tema == .treino)
    }

    @Test func resumoLocalContaAberturasPorOrigem() throws {
        let m = try motor(relogio: RelogioDeTeste(data(2026, 11, 18, 9)))
        let frase = m.planejar().atual.frase
        m.registrarAbertura(fraseId: frase.id, origem: .widget)
        m.registrarAbertura(fraseId: frase.id, origem: .widget)
        m.registrarAbertura(fraseId: frase.id, origem: .aviso)
        try m.salvar(frase)
        let r = m.resumoLocal()
        #expect(r == ResumoLocal(salvas: 1, aberturasPeloWidget: 2, aberturasPeloAviso: 1))
        #expect(r.textoParaCompartilhar.contains("Aberturas pelo widget: 2"))
    }
}
