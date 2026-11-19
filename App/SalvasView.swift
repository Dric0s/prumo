import SwiftUI
import PrumoKit

struct SalvasView: View {
    @Environment(ModeloDoApp.self) private var modelo

    private var rubrica: String {
        switch modelo.salvas.count {
        case 0: "Sua coleção"
        case 1: "1 frase na coleção"
        case let n: "\(n) frases na coleção"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Cabecalho(rubrica: rubrica, titulo: "Salvas")
                if modelo.salvas.isEmpty {
                    vazio
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Rectangle().fill(Paleta.linhaForte).frame(height: 1)
                        ForEach(modelo.salvas) { salva in
                            ItemSalvo(salva: salva, frase: modelo.frase(de: salva))
                            Rectangle().fill(Paleta.linha).frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Paleta.papel)
    }

    /// O estado vazio explica como guardar a primeira frase e aponta para Hoje.
    private var vazio: some View {
        VStack(spacing: 0) {
            Image(systemName: "bookmark")
                .font(.title2)
                .foregroundStyle(Paleta.acao)
                .frame(width: 58, height: 58)
                .background(Paleta.realce, in: Circle())
                .overlay(Circle().stroke(Paleta.linhaForte))
                .accessibilityHidden(true)
                .padding(.bottom, 16)
            Text("Nenhuma frase salva")
                .font(.frase(.title))
                .foregroundStyle(Paleta.tinta)
                .multilineTextAlignment(.center)
            Text("Use o marcador em Hoje para guardar uma frase aqui.")
                .font(.subheadline)
                .foregroundStyle(Paleta.suave)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.bottom, 20)
            Button {
                modelo.aba = .hoje
            } label: {
                Label("Ver frase de hoje", systemImage: "arrow.right")
                    .labelStyle(TituloEDepoisIcone())
            }
            .buttonStyle(EstiloBotaoCheio())
        }
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(Paleta.superficie, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Paleta.linha))
    }
}

struct ItemSalvo: View {
    @Environment(ModeloDoApp.self) private var modelo
    let salva: Salva
    let frase: Frase

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                modelo.abrirDetalhe(frase)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(Formatos.dataCurta(salva.salvaEm)) · \(frase.periodo.nome) · \(frase.tema.nome)")
                        .font(.caption)
                        .foregroundStyle(Paleta.suave)
                    Text(frase.texto)
                        .font(.frase(.title2))
                        .foregroundStyle(Paleta.tinta)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let atribuicao = frase.atribuicao {
                        Text(atribuicao)
                            .font(.footnote)
                            .foregroundStyle(Paleta.suave)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre a leitura")

            Button {
                modelo.remover(salva.fraseId)
            } label: {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Paleta.acao)
                    .frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Paleta.linha))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remover das salvas: \(frase.texto)")
        }
        .padding(.vertical, 18)
    }
}

/// Rótulo com o ícone depois do texto, como "Ver frase de hoje →".
struct TituloEDepoisIcone: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}
