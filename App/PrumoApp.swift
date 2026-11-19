import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks
import WidgetKit
import PrumoKit

@main
struct PrumoApp: App {
    static let tarefaDeAtualizacao = "br.prumo.app.atualizar"

    @UIApplicationDelegateAdaptor(DelegadoDoApp.self) private var delegado
    @Environment(\.scenePhase) private var fase
    @State private var modelo: ModeloDoApp

    init() {
        let motor: Motor
        do {
            motor = try Motor.compartilhado()
        } catch {
            // O catálogo é um recurso embarcado e validado nos testes; sem ele não há o que exibir.
            fatalError("Catálogo do Prumo indisponível: \(error)")
        }
        _modelo = State(initialValue: ModeloDoApp(motor: motor))
    }

    var body: some Scene {
        WindowGroup {
            RaizView()
                .environment(modelo)
                .onOpenURL { modelo.abrir($0) }
                .onAppear {
                    delegado.aoAbrirLink = { url in modelo.abrir(url) }
                    modelo.atualizar()
                }
        }
        .onChange(of: fase) { _, nova in
            switch nova {
            case .active: modelo.atualizar()
            case .background: Self.agendarAtualizacao()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.tarefaDeAtualizacao)) {
            await Self.atualizarEmSegundoPlano()
        }
    }

    /// Pede ao sistema uma nova oportunidade para repor reservas e avisos com o app fechado.
    static func agendarAtualizacao() {
        let pedido = BGAppRefreshTaskRequest(identifier: tarefaDeAtualizacao)
        pedido.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(pedido)
    }

    static func atualizarEmSegundoPlano() async {
        agendarAtualizacao()
        guard let motor = try? Motor.compartilhado() else { return }
        let plano = motor.planejar()
        if plano.preferencias.lembretes, await ServicoDeLembretes.status() == .permitido {
            let pedidos = PlanejadorDeLembretes.lembretes(para: plano, agora: motor.agora, calendario: motor.calendarioAtual)
            await ServicoDeLembretes.reprogramar(pedidos)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: Motor.kindDoWidget)
    }
}

/// Recebe o toque nos avisos e entrega o link ao modelo.
final class DelegadoDoApp: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var aoAbrirLink: ((URL) -> Void)? {
        didSet {
            if let pendente = linkPendente, let aoAbrirLink {
                linkPendente = nil
                aoAbrirLink(pendente)
            }
        }
    }

    private var linkPendente: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let texto = info["link"] as? String, let url = URL(string: texto) {
            DispatchQueue.main.async {
                if let abrir = self.aoAbrirLink { abrir(url) } else { self.linkPendente = url }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}

struct RaizView: View {
    @Environment(ModeloDoApp.self) private var modelo
    private let relogio = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var modelo = modelo
        TabView(selection: $modelo.aba) {
            HojeView()
                .tabItem { Label("Hoje", systemImage: "sun.max") }
                .tag(Aba.hoje)
            SalvasView()
                .tabItem { Label("Salvas", systemImage: "bookmark") }
                .tag(Aba.salvas)
            WidgetsView()
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
                .tag(Aba.widgets)
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "slider.horizontal.3") }
                .tag(Aba.ajustes)
        }
        .tint(Paleta.acao)
        .overlay(alignment: .bottom) {
            if let aviso = modelo.aviso {
                AvisoView(aviso: aviso)
                    .padding(.bottom, 62)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: modelo.aviso?.id)
        .sheet(item: $modelo.fraseAberta) { aberta in
            FraseDetalheView(aberta: aberta)
        }
        .onReceive(relogio) { _ in modelo.tique() }
        // Mudança de fuso, de horário de verão ou do relógio: replaneja, repõe avisos e recarrega o widget.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            modelo.atualizar()
        }
        .onChange(of: modelo.aba) { _, _ in modelo.dispensarAviso() }
    }
}

struct AvisoView: View {
    @Environment(ModeloDoApp.self) private var modelo
    let aviso: Aviso

    var body: some View {
        HStack(spacing: 12) {
            Text(aviso.mensagem)
                .font(.subheadline)
                .foregroundStyle(Paleta.claro)
            if let desfazer = aviso.desfazer {
                Button("Desfazer") {
                    modelo.dispensarAviso()
                    desfazer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Paleta.ouro)
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, aviso.desfazer == nil ? 12 : 2)
        .background(Color(hex: 0x213C33), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(hex: 0x4D6657)))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
