import UserNotifications
import OSLog
import AppKit

private let log = Logger.service("notification")

final class UserNotificationService: Service {
    static let shared = UserNotificationService()
    
    var tools: [Tool] {
        return [notify]
    }
    
    var isActivated: Bool {
        get async {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            
            switch settings.authorizationStatus {
            case .notDetermined:
                log.info("Authorization status - Not Determined: User hasn't made a choice yet")
                return await requestAuthorization()
            case .denied:
                log.info("Authorization status - Denied: Notifications are disabled")
                await openAppSettings()
                return false
            case .authorized, .provisional, .ephemeral:
                log.info("Authorization status - Authorized: Notifications are allowed")
                return true
            @unknown default: break
            }
            return false
        }
    }
    
    func activate() async throws {
        Task { @MainActor in
            await requestAuthorization()
        }
    }
    
    var notify: Tool {
        Tool(
            name: "notify",
            description: "Notify user with short message.",
            inputSchema: .object(
                properties: [
                    "message": .string(description: "Short message that will be displyed to user")
                ],
                required: ["message"],
                additionalProperties: false
            ),
            annotations: .init(
                title: "User notifications",
                readOnlyHint: true,
                openWorldHint: false
            )
        ) { [weak self] arguments in
            guard let self, let message = arguments["message"]?.stringValue else {
                return Value.bool(false)
            }
            return await Value.bool(self.sendNotification(message: message))
        }
    }
    
    @discardableResult
    @MainActor
    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let options = UNAuthorizationOptions([.alert, .sound, .badge])
        do {
            NSApp.activate(ignoringOtherApps: true)
            let granted = try await center.requestAuthorization(options: options)
            log.info("Authorization granted")
            return granted
        } catch {
            log.warning("Authorization not granted: \(error.localizedDescription)")
            return false
        }
    }
    
    @MainActor
    func openRequestDialog() {
        let alert = NSAlert()
        alert.messageText = "Setup You Notifications"
        alert.informativeText = "Будь ласка, дозвольте сповіщення в Системних параметрах, щоб отримувати важливі оновлення."
        
        // Додаємо кнопки (перша кнопка стає кнопкою за замовчуванням)
        alert.addButton(withTitle: "Відкрити Параметри")
        alert.addButton(withTitle: "Скасувати")
        
        // Показуємо алерт на екрані
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            Task { @MainActor in
                await requestAuthorization()
            }
        }
    }
    
    @MainActor
    func openAppSettings() {
        let alert = NSAlert()
        alert.messageText = "Сповіщення вимкнено"
        alert.informativeText = "Будь ласка, дозвольте сповіщення в Системних параметрах, щоб отримувати важливі оновлення."
        
        // Додаємо кнопки (перша кнопка стає кнопкою за замовчуванням)
        alert.addButton(withTitle: "Відкрити Параметри")
        alert.addButton(withTitle: "Скасувати")
        
        // Показуємо алерт на екрані
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Відкриваємо безпосередньо розділ сповіщень у системних налаштуваннях macOS
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    public func sendNotification(message: String) async -> Bool {
        if await !isActivated {
            guard await requestAuthorization() else { return false }
        }
        let center = UNUserNotificationCenter.current()
        
        let content = UNMutableNotificationContent()
        content.title = "iMCP"
        content.body = message
        content.sound = .default
        
        let immediate: UNNotificationTrigger? = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: immediate
        )
        
        do {
            try await center.add(request)
            log.info("Notification added to queue")
            return true
        } catch {
            log.error("Error sending notification: \(error.localizedDescription)")
            return false
        }
    }
}
