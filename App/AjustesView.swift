import SwiftUI
import UIKit
import PrumoKit

struct AjustesView: View {
    @Environment(ModeloDoApp.self) private var modelo

    // Rascunho do formulário. Só vale depois de "Salvar ajustes".
    @State private var temas: Set<Tema> = Set(Tema.allCases)
    @State private var horarios: [Periodo: Date] = [:]
    @State private var erro: ErroPreferencias?
    @State private var carregado = false
    @FocusState private var campoComErro: Periodo?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(rubrica: "Preferências de leitura", titulo: "Ajustes")
                cartaoDeTemas
                cartaoDeHorarios
                acoes
                CartaoDeLembretes()
                CartaoDeDados()
                Text("Catálogo \(modelo.motor.catalogo.versao) · \(modelo.motor.catalogo.frases.count.formatted(.number.locale(Formatos.locale))) leituras no aparelho. Funciona sem conexão e sem conta.")
                    .font(.caption)
                    .foregroundStyle(Paleta.suave)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Paleta.papel)
        .onAppear {
            guard !carregado else { return }
            carregado = true
            restaurarRascunho()
        }
    }

    private var cartaoDeTemas: some View {
        Cartao {
            Subtitulo("Temas")
            Text("Escolha pelo menos um para suas leituras.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 4)
                .padding(.bottom, 10)
            ForEach(Tema.allCases) { tema in
                Toggle(isOn: Binding(
                    get: { temas.contains(tema) },
                    set: { ligado in
                        if ligado { temas.insert(tema) } else { temas.remove(tema) }
                        if erro == .semTemas { erro = nil }
                    }
                )) {
                    Label(tema.nome, systemImage: tema.simbolo)
                        .foregroundStyle(Paleta.tinta)
                }
                .tint(Paleta.acao)
                .frame(minHeight: 47)
                .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
            }
            if erro == .semTemas { mensagemDeErro }
        }
    }

    private var cartaoDeHorarios: some View {
        Cartao {
            Subtitulo("Horários")
            Text("Cada período começa na hora local escolhida. A ordem vai de madrugada a noite.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 4)
                .padding(.bottom, 10)
            ForEach(Periodo.ordemDeExibicao) { periodo in
                HStack {
                    Label(periodo.nome, systemImage: periodo.simbolo)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Paleta.tinta)
                    Spacer()
                    DatePicker(
                        periodo.nome,
                        selection: Binding(
                            get: { horarios[periodo] ?? data(de: modelo.preferencias.horarios[periodo]) },
                            set: { horarios[periodo] = $0; if case .horarioForaDeOrdem? = erro { erro = nil } }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .environment(\.locale, Formatos.locale)
                    .focused($campoComErro, equals: periodo)
                    .overlay {
                        if case .horarioForaDeOrdem(let p)? = erro, p == periodo {
                            RoundedRectangle(cornerRadius: 8).stroke(Paleta.erro, lineWidth: 1.5)
                        }
                    }
                }
                .frame(minHeight: 58)
                .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
                .accessibilityElement(children: .contain)
            }
            if case .horarioForaDeOrdem? = erro { mensagemDeErro }
        }
    }

    private var mensagemDeErro: some View {
        Label(erro?.mensagem ?? "", systemImage: "exclamationmark.circle")
            .font(.subheadline)
            .foregroundStyle(Paleta.erro)
            .padding(.top, 10)
    }

    private var acoes: some View {
        Button {
            salvar()
        } label: {
            Label("Salvar ajustes", systemImage: "arrow.right")
                .labelStyle(TituloEDepoisIcone())
        }
        .buttonStyle(EstiloBotaoCheio())
    }

    // MARK: Lógica do formulário

    private func data(de hora: HoraDoDia) -> Date {
        let cal = modelo.calendario
        return cal.date(bySettingHour: hora.hora, minute: hora.minuto, second: 0, of: Date()) ?? Date()
    }

    private func hora(de data: Date) -> HoraDoDia {
        let c = modelo.calendario.dateComponents([.hour, .minute], from: data)
        return HoraDoDia(hora: c.hour ?? 0, minuto: c.minute ?? 0)
    }

    private func restaurarRascunho() {
        let prefs = modelo.preferencias
        temas = Set(prefs.temas)
        horarios = Dictionary(uniqueKeysWithValues: Periodo.allCases.map { ($0, data(de: prefs.horarios[$0])) })
        erro = nil
    }

    /// Valida em ordem (temas, depois horários). Em erro mantém os valores anteriores gravados.
    private func salvar() {
        var novos = modelo.preferencias.horarios
        for periodo in Periodo.allCases {
            if let data = horarios[periodo] { novos[periodo] = hora(de: data) }
        }
        erro = modelo.salvarAjustes(temas: temas, horarios: novos)
        if case .horarioForaDeOrdem(let periodo)? = erro { campoComErro = periodo }
        if erro == nil { restaurarRascunho() }
    }
}

/// Lembretes começam desligados. Pausar fica no mesmo lugar em que se liga.
private struct CartaoDeLembretes: View {
    @Environment(ModeloDoApp.self) private var modelo
    @State private var processando = false

    var body: some View {
        Cartao {
            Toggle(isOn: Binding(
                get: { modelo.preferencias.lembretes },
                set: { ligado in
                    processando = true
                    Task {
                        await modelo.definirLembretes(ligado)
                        processando = false
                    }
                }
            )) {
                Subtitulo("Lembretes")
            }
            .tint(Paleta.acao)
            .disabled(processando)
            Text("Um aviso marca a virada da manhã, da tarde e da noite, com a mesma frase do widget. A madrugada fica sempre em silêncio. O Foco e o resumo do iOS podem adiar a exibição.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 6)
            if modelo.statusDosLembretes == .negado {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Os avisos estão desativados nos Ajustes do iPhone. O widget, as leituras e as salvas continuam funcionando.")
                        .font(.subheadline)
                        .foregroundStyle(Paleta.tinta)
                    Button("Abrir Ajustes do iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Paleta.acao)
                    .frame(minHeight: 44)
                }
                .padding(.top, 12)
            }
        }
        .task { await modelo.sincronizarLembretes() }
    }
}

/// Medição sem backend: contagens locais que a pessoa pode compartilhar se quiser.
private struct CartaoDeDados: View {
    @Environment(ModeloDoApp.self) private var modelo

    var body: some View {
        let resumo = modelo.resumo
        Cartao {
            Subtitulo("Dados no aparelho")
            Text("Nada sai do iPhone sem você compartilhar. Olhar a Tela Bloqueada não é registrado; só o toque que abre o app.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 4)
                .padding(.bottom, 10)
            linha("Frases salvas", resumo.salvas)
            linha("Aberturas pelo widget", resumo.aberturasPeloWidget)
            linha("Aberturas pelo aviso", resumo.aberturasPeloAviso)
            ShareLink(item: resumo.textoParaCompartilhar) {
                Label("Compartilhar resumo", systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Paleta.acao)
                    .frame(minHeight: 44)
            }
            .padding(.top, 6)
        }
    }

    private func linha(_ titulo: String, _ valor: Int) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text("\(valor)").monospacedDigit()
        }
        .font(.subheadline)
        .foregroundStyle(Paleta.tinta)
        .frame(minHeight: 40)
        .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}
