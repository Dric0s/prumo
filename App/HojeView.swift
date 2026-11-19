import SwiftUI
import PrumoKit

struct HojeView: View {
    @Environment(ModeloDoApp.self) private var modelo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Cabecalho(rubrica: Formatos.dataLonga(modelo.agora), titulo: "Hoje") {
                    Label {
                        Text("Hora local · \(Formatos.hora(modelo.agora))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Paleta.suave)
                    .labelStyle(.titleAndIcon)
                }
                CartaoDeLeitura(leitura: modelo.leituraExibida)
                SeletorDePeriodos()
                PreviaDoWidget()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Paleta.papel)
    }
}

struct CartaoDeLeitura: View {
    @Environment(ModeloDoApp.self) private var modelo
    let leitura: Leitura

    private var periodo: Periodo { leitura.slot.chave.periodo }
    private var frase: Frase { leitura.frase }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label(periodo.nome, systemImage: periodo.simbolo)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xE4E9DB))
                Text(Rotulos.intervalo(periodo, horarios: modelo.preferencias.horarios))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Paleta.claroSuave)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(Color(hex: 0x657E6F)).frame(width: 1) }
            }
            .padding(.trailing, 80)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(periodo.nome). \(modelo.descricaoDoTempo), \(Rotulos.intervaloFalado(periodo, horarios: modelo.preferencias.horarios)).")

            Text(frase.texto)
                .font(.frase(frase.texto.count > 80 ? .title : .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(Paleta.claro)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 34)
                .padding(.bottom, frase.atribuicao == nil ? 28 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let atribuicao = frase.atribuicao {
                Button {
                    modelo.abrirDetalhe(frase)
                } label: {
                    HStack(spacing: 6) {
                        Text(atribuicao)
                        Image(systemName: "info.circle")
                    }
                    .font(.footnote)
                    .foregroundStyle(Paleta.claroSuave)
                    .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(atribuicao). Ver contexto")
                .padding(.bottom, 12)
            }

            Rectangle().fill(Paleta.filete).frame(height: 1)

            HStack(spacing: 10) {
                Label(frase.tema.nome, systemImage: frase.tema.simbolo)
                    .font(.footnote)
                    .foregroundStyle(Color(hex: 0xE3E7DA))
                Spacer(minLength: 8)
                BotaoSalvar(salva: modelo.estaSalva(frase)) { modelo.alternarSalva(frase) }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background {
            ZStack {
                Paleta.gradienteDeLeitura
                RadialGradient(colors: [Paleta.florestaClara, .clear], center: UnitPoint(x: 0.89, y: 0.09), startRadius: 0, endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .overlay(alignment: .topTrailing) {
            EmblemaCeleste(periodo: periodo)
                .frame(width: 93, height: 67)
                .padding(.top, 6)
                .padding(.trailing, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Frase de \(periodo.nome)")
    }
}

struct SeletorDePeriodos: View {
    @Environment(ModeloDoApp.self) private var modelo
    @Environment(\.dynamicTypeSize) private var tamanhoDoTexto

    private var colunas: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: tamanhoDoTexto.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Subtitulo("Períodos do dia")
                Spacer()
                Text("Agora · \(modelo.periodoAtual.nome)")
                    .font(.caption)
                    .foregroundStyle(Paleta.suave)
            }
            LazyVGrid(columns: colunas, spacing: 6) {
                ForEach(Periodo.ordemDeExibicao) { periodo in
                    botao(periodo)
                }
            }
        }
    }

    private func botao(_ periodo: Periodo) -> some View {
        let selecionado = modelo.leituraExibida.slot.chave.periodo == periodo
        let inicio = modelo.preferencias.horarios[periodo].rotulo
        return Button {
            modelo.selecionar(periodo)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(periodo.nome)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(selecionado ? Paleta.acao : Paleta.tinta)
                Text(inicio)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(selecionado ? Paleta.acao : Paleta.suave)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .padding(.horizontal, 10)
            .background(selecionado ? Paleta.realce : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(selecionado ? Paleta.acao.opacity(0.6) : Paleta.linha))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(periodo.nome), a partir das \(inicio)\(periodo == modelo.periodoAtual ? ", período atual" : "")")
        .accessibilityAddTraits(selecionado ? .isSelected : [])
    }
}

/// Prévia da Tela Bloqueada com a frase do período atual e atalho para Widgets.
struct PreviaDoWidget: View {
    @Environment(ModeloDoApp.self) private var modelo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Rubrica("Prévia do widget")
                Subtitulo("Tela Bloqueada")
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ZStack(alignment: .top) {
                FundoDePalco()
                Aparelho(largura: 190) {
                    TelaBloqueadaPrevia(leitura: modelo.plano.atual, agora: modelo.agora)
                }
                .padding(.top, 14)
            }
            .frame(height: 200, alignment: .top)
            .clipped()
            .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Paleta.linha).frame(height: 1) }

            Button {
                modelo.formatoDeWidget = .bloqueio
                modelo.aba = .widgets
            } label: {
                HStack {
                    Text("Ver widgets")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Paleta.acao)
                .padding(.horizontal, 18)
                .frame(minHeight: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Paleta.linha))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
