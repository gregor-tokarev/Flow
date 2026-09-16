import UIKit
import FlowCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var store: FlowStore?
    private var libraryDirectory: URL?

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
            libraryDirectory = directory
            let store = try FlowStore(directory: directory)
            try install(store)
        } catch {
            showStartupError(error)
        }
    }

    private func install(_ store: FlowStore) throws {
        guard let window else { return }
        // Flow has no account or cloud sync. Exclude its local library from device backups too.
        var directory = store.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        self.store = store
        let home = HomeViewController(store: store)
        let navigation = UINavigationController(rootViewController: home)
        navigation.navigationBar.prefersLargeTitles = true
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        if !store.missingAttachments.isEmpty {
            DispatchQueue.main.async {
                let count = store.missingAttachments.count
                let alert = UIAlertController(title: "Some attachment files are missing",
                    message: "\(count) files could not be found. Your notes and attachment records are still available. Restore a backup to recover the missing files.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                home.present(alert, animated: true)
            }
        }
    }

    private func showStartupError(_ error: Error) {
        guard let window else { return }
        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let alert = UIAlertController(title: "Could not open Flow", message: error.localizedDescription + "\nYour saved files have not been replaced. Starting a new library preserves the original files separately so they can be recovered later.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        if let directory = libraryDirectory {
            alert.addAction(UIAlertAction(title: "Start a new library", style: .destructive) { [weak self] _ in
                guard let self else { return }
                do {
                    let recovery = try FlowStore.startNewLibrary(at: directory)
                    try self.install(recovery.store)
                } catch { self.showStartupError(error) }
            })
        }
        controller.present(alert, animated: false)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NotificationCenter.default.post(name: .flowSaveRequested, object: nil)
    }
}

extension Notification.Name {
    static let flowSaveRequested = Notification.Name("flowSaveRequested")
    static let flowPreferencesChanged = Notification.Name("flowPreferencesChanged")
}
