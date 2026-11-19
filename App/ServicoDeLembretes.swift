import Foundation
import UserNotifications
import PrumoKit

/// Notificações locais. Um pedido por slot (`prumo.slot.<data>.<período>`), com a mesma seleção do widget.
enum ServicoDeLembretes {
    private static var central: UNUserNotificationCenter { .current() }

    static func status() async -> StatusDosLembretes {
        let ajustes = await central.notificationSettings()
        switch ajustes.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .permitido
        case .denied: return .negado
        case .notDetermined: return .naoPerguntado
        @unknown default: return .desconhecido
        }
    }

    /// Pede autorização apenas quando a pessoa liga os lembretes.
    static func pedirPermissao() async -> Bool {
        switch await status() {
        case .permitido: return true
        case .negado: return false
        default:
            return (try? await central.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Substitui a fila pendente do app pelos pedidos do plano atual.
    static func reprogramar(_ lembretes: [LembretePlanejado]) async {
        await cancelarTodos()
        for lembrete in lembretes {
            let conteudo = UNMutableNotificationContent()
            conteudo.title = lembrete.titulo
            conteudo.body = lembrete.corpo
            conteudo.threadIdentifier = "prumo"
            conteudo.userInfo = ["link": lembrete.link.absoluteString, "fraseId": lembrete.fraseId]
            conteudo.interruptionLevel = .active
            let gatilho = UNCalendarNotificationTrigger(dateMatching: lembrete.componentes, repeats: false)
            let pedido = UNNotificationRequest(identifier: lembrete.id, content: conteudo, trigger: gatilho)
            try? await central.add(pedido)
        }
    }

    /// Ao desligar os avisos, cancela os pedidos pendentes do app. Leituras, salvas e widget continuam.
    static func cancelarTodos() async {
        let pendentes = await central.pendingNotificationRequests()
        let ids = pendentes.map(\.identifier).filter { $0.hasPrefix(LembretePlanejado.prefixo) }
        central.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
