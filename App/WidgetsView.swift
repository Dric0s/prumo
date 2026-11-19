import SwiftUI
import PrumoKit

struct WidgetsView: View {
    @Environment(ModeloDoApp.self) private var modelo

    var body: some View {
        @Bindable var modelo = modelo
        let formato = modelo.formatoDeWidget
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Cabecalho(rubrica: "No iPhone", titulo: "Widgets")

                Picker("Formato de widget", selection: $modelo.formatoDeWidget) {
                    ForEach(FormatoDeWidget.allCases) { f in
                        Label(f.aba, systemImage: f.simbolo).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: modelo.formatoDeWidget) { _, novo in
                    modelo.anunciar("Prévia. \(novo.nome).")
                }

                ZStack {
                    FundoDePalco()
                    Aparelho(largura: 212) {
                        switch formato {
                        case .bloqueio:
                            TelaBloqueadaPrevia(leitura: modelo.plano.atual, agora: modelo.agora)
                        case .pequeno, .medio:
                            TelaDeInicioPrevia(leitura: modelo.plano.atual, medio: formato == .medio, agora: modelo.agora)
                        }
                    }
                    .accessibilityLabel(descricaoDaPrevia(formato))
                }
                .frame(height: 470)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Paleta.linha))

                Guia(formato: formato)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Paleta.papel)
    }

    private func descricaoDaPrevia(_ formato: FormatoDeWidget) -> String {
        let leitura = modelo.plano.atual
        let periodo = leitura.slot.chave.periodo.nome
        switch formato {
        case .bloqueio:
            return "Prévia da Tela Bloqueada. Às \(Formatos.hora(modelo.agora)), o widget abaixo do relógio, à esquerda, mostra \(periodo). \(leitura.frase.curta)"
        case .pequeno:
            return "Prévia da Tela de Início com widget pequeno de \(periodo). \(leitura.frase.curta)"
        case .medio:
            return "Prévia da Tela de Início com widget médio de \(periodo). \(leitura.frase.texto)"
        }
    }
}

/// Instalação guiada. Alternar o formato muda a ilustração e as instruções.
private struct Guia: View {
    let formato: FormatoDeWidget

    private var introducao: String {
        switch formato {
        case .bloqueio: "A versão curta aparece abaixo do relógio, à esquerda. A imagem de fundo é a que você escolhe no iPhone."
        case .pequeno: "Um quadrado na Tela de Início reúne o período e a versão curta da frase."
        case .medio: "O formato mais largo dá espaço à frase completa e ao tema, na Tela de Início."
        }
    }

    private var passos: [LocalizedStringKey] {
        switch formato {
        case .bloqueio:
            [
                "Mantenha a Tela Bloqueada pressionada e toque em **Personalizar**.",
                "Escolha **Tela Bloqueada** e toque na área de widgets abaixo da hora.",
                "Busque **Prumo**, selecione o widget retangular e conclua a edição.",
            ]
        case .pequeno, .medio:
            [
                "Mantenha uma área vazia da Tela de Início pressionada.",
                "Toque em **Editar** e depois em **Adicionar Widget**.",
                formato == .pequeno
                    ? "Busque **Prumo**, escolha o tamanho pequeno e toque em **Adicionar Widget**."
                    : "Busque **Prumo**, escolha o tamanho médio e toque em **Adicionar Widget**.",
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rubrica(formato == .bloqueio ? "Acessório retangular" : "Tela de Início")
                .padding(.bottom, 6)
            Text(formato.nome)
                .font(.frase(.largeTitle))
                .foregroundStyle(Paleta.tinta)
                .accessibilityAddTraits(.isHeader)
            Text(introducao)
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 8)
                .padding(.bottom, 18)

            Rectangle().fill(Paleta.linha).frame(height: 1)
            Text("Como adicionar no iPhone")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Paleta.tinta)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(Array(passos.enumerated()), id: \.offset) { indice, passo in
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(indice + 1)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Paleta.acao)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(Paleta.linhaForte))
                        .accessibilityHidden(true)
                    Text(passo)
                        .font(.subheadline)
                        .foregroundStyle(Paleta.tinta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
            }

            Text("Os nomes dos botões variam conforme a versão do iOS. Cada Tela Bloqueada personalizada pode ter uma composição própria. Papel de parede, relógio e aparência final pertencem ao iOS.")
                .font(.caption)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
                .padding(.top, 8)
        }
    }
}
