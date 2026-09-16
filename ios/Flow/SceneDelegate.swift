import UIKit
import FlowCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var store: FlowStore?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        self.window = window
        window.tintColor = Theme.accent
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            var directory = base.appendingPathComponent("Flow", isDirectory: true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                directory = base.appendingPathComponent("FlowUITests", isDirectory: true)
                if ProcessInfo.processInfo.arguments.contains("--reset-library") {
                    try? FileManager.default.removeItem(at: directory)
                    UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
                }
            }
            #endif
            let store = try FlowStore(directory: directory)
            self.store = store
            // Flow has no account or cloud sync. Exclude its local library from device backups too.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            let home = HomeViewController(store: store)
            let navigation = UINavigationController(rootViewController: home)
            navigation.navigationBar.prefersLargeTitles = true
            window.rootViewController = navigation
        } catch {
            let controller = UIViewController()
            controller.view.backgroundColor = .systemBackground
            window.rootViewController = controller
            window.makeKeyAndVisible()
            let alert = UIAlertController(title: "Could not open Flow", message: error.localizedDescription + "\nYour saved files have not been replaced.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel))
            controller.present(alert, animated: false)
            return
        }
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NotificationCenter.default.post(name: .flowSaveRequested, object: nil)
    }
}

extension Notification.Name {
    static let flowSaveRequested = Notification.Name("flowSaveRequested")
    static let flowPreferencesChanged = Notification.Name("flowPreferencesChanged")
}
