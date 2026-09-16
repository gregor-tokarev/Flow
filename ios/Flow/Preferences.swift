import UIKit
import FlowCore

enum Preferences {
    static var folders: Bool {
        get { UserDefaults.standard.bool(forKey: "folders") }
        set { UserDefaults.standard.set(newValue, forKey: "folders"); changed() }
    }
    static var swipes: Bool {
        get { UserDefaults.standard.object(forKey: "swipes") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "swipes"); changed() }
    }
    static var pureBlack: Bool {
        get { UserDefaults.standard.bool(forKey: "pureBlack") }
        set { UserDefaults.standard.set(newValue, forKey: "pureBlack"); changed() }
    }
    static var codeKeyboard: Bool {
        get { UserDefaults.standard.bool(forKey: "codeKeyboard") }
        set { UserDefaults.standard.set(newValue, forKey: "codeKeyboard"); changed() }
    }
    static var defaultKind: EntryKind {
        get { EntryKind(rawValue: UserDefaults.standard.string(forKey: "defaultKind") ?? "") ?? .note }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultKind"); changed() }
    }
    static var previewLines: Int {
        get { max(1, min(12, UserDefaults.standard.object(forKey: "previewLines") as? Int ?? 4)) }
        set { UserDefaults.standard.set(newValue, forKey: "previewLines"); changed() }
    }
    static var uiFont: String {
        get { UserDefaults.standard.string(forKey: "uiFont") ?? "System" }
        set { UserDefaults.standard.set(newValue, forKey: "uiFont"); changed() }
    }
    static var editorFont: String {
        get { UserDefaults.standard.string(forKey: "editorFont") ?? "UI font" }
        set { UserDefaults.standard.set(newValue, forKey: "editorFont"); changed() }
    }
    static var currentFolder: String {
        get { UserDefaults.standard.string(forKey: "currentFolder") ?? Folder.masterID }
        set { UserDefaults.standard.set(newValue, forKey: "currentFolder") }
    }
    private static func changed() { NotificationCenter.default.post(name: .flowPreferencesChanged, object: nil) }
}

enum Theme {
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.72, green: 0.65, blue: 1, alpha: 1)
            : UIColor(red: 0.46, green: 0.35, blue: 0.80, alpha: 1)
    }
    static var background: UIColor {
        UIColor { traits in
            Preferences.pureBlack && traits.userInterfaceStyle == .dark ? .black : .systemGroupedBackground
        }
    }
    static func font(editor: Bool = false, style: UIFont.TextStyle = .body) -> UIFont {
        let name = editor && Preferences.editorFont != "UI font" ? Preferences.editorFont : Preferences.uiFont
        let base = UIFont.systemFont(ofSize: editor ? 19 : 17)
        let design: UIFontDescriptor.SystemDesign = name == "Monospaced" ? .monospaced : name == "Serif" ? .serif : .default
        let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
        return UIFontMetrics(forTextStyle: style).scaledFont(for: UIFont(descriptor: descriptor, size: base.pointSize))
    }
}

extension UIViewController {
    func showError(_ error: Error) {
        let alert = UIAlertController(title: "Could not complete the action", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func performStoreAction(_ action: () throws -> Void) {
        do { try action() } catch { showError(error) }
    }
}
