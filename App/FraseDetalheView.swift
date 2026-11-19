import SwiftUI
import PrumoKit

/// Leitura aberta por ID: o registro tocado no widget ou no aviso, mesmo depois da virada,
/// uma salva, ou o contexto de um trecho histórico.
struct FraseDetalheView: View {
    @Environment(ModeloDoApp.self) private var modelo
    @Environment(\.dismiss) private var fechar
    let aberta: FraseAberta

    private var frase: Frase { aberta.frase }

    private var rubrica: String {
        switch aberta.origem {
        case .widget: "Aberta pelo widget"
        case .aviso: "Aberta pelo aviso"
        case .app: "Leitura"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            Label(frase.periodo.nome, systemImage: frase.periodo.simbolo)
                            Text("·").accessibilityHidden(true)
                            Label(frase.tema.nome, systemImage: frase.tema.simbolo)
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(hex: 0xE4E9DB))

                        Text(frase.texto)
                            .font(.frase(frase.texto.count > 80 ? .title : .largeTitle))
                            .foregroundStyle(Paleta.claro)
                            .fixedSize(horizontal: false, vertical: true)

                        if frase.curta != frase.texto {
                            Text("Na tela: \(frase.curta)")
                                .font(.footnote)
                                .foregroundStyle(Paleta.claroSuave)
                        }

                        HStack {
                            if let atribuicao = frase.atribuicao {
                                Text(atribuicao)
                                    .font(.footnote)
                                    .foregroundStyle(Paleta.claroSuave)
                            }
                            Spacer(minLength: 8)
                            BotaoSalvar(salva: modelo.estaSalva(frase)) { modelo.alternarSalva(frase) }
                        }
                    }
                    .padding(22)
                    .background(Paleta.gradienteDeLeitura, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    if frase.isHistorica {
                        contexto
                    } else if let fonte = modelo.motor.catalogo.fonte(de: frase) {
                        influencia(fonte)
                    }
                }
                .padding(18)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Paleta.papel)
            .navigationTitle(rubrica)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") { fechar() }
                }
            }
        }
        .tint(Paleta.acao)
    }

    /// Conteúdo histórico abre autor, obra, localizador e contexto.
    private var contexto: some View {
        Cartao {
            Subtitulo("Contexto")
            VStack(alignment: .leading, spacing: 10) {
                if let autor = frase.autor { campo("Autor", autor) }
                if let obra = frase.obra { campo("Obra", obra) }
                if let localizador = frase.localizador { campo("Trecho", localizador) }
                if let contexto = frase.contexto {
                    Text(contexto)
                        .font(.subheadline)
                        .foregroundStyle(Paleta.tinta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if frase.tipo == .citacaoTraduzida {
                    Text("Tradução própria do Prumo.")
                        .font(.caption)
                        .foregroundStyle(Paleta.suave)
                }
                if let fonte = modelo.motor.catalogo.fonte(de: frase) {
                    procedencia(fonte)
                }
            }
            .padding(.top, 10)
        }
    }

    /// Texto editorial com influência específica: a referência aparece como inspiração, nunca como autoria.
    private func influencia(_ fonte: Fonte) -> some View {
        Cartao {
            Subtitulo("Inspiração")
            Text("Texto editorial do Prumo, escrito a partir desta referência.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .padding(.top, 4)
            procedencia(fonte).padding(.top, 10)
        }
    }

    private func procedencia(_ fonte: Fonte) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fonte.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Paleta.tinta)
            Text(fonte.ideia)
                .font(.footnote)
                .foregroundStyle(Paleta.suave)
                .fixedSize(horizontal: false, vertical: true)
            if let link = fonte.link {
                Link(destination: link) {
                    Label("Abrir referência", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .foregroundStyle(Paleta.acao)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Paleta.linha).frame(height: 1) }
    }

    private func campo(_ rotulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Rubrica(rotulo)
            Text(valor).font(.subheadline).foregroundStyle(Paleta.tinta)
        }
        .accessibilityElement(children: .combine)
    }
}
