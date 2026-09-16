import UIKit
import UniformTypeIdentifiers
import FlowCore

final class SettingsViewController: UITableViewController, UIDocumentPickerDelegate {
    private let store: FlowStore
    private var isBusy = false
    private var exportURL: URL?

    init(store: FlowStore) { self.store = store; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        tableView.backgroundColor = Theme.background
    }
    @objc private func close() { dismiss(animated: true) }
    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [3, 4, 2, 1][section] }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Features", "Editor", "Your data", "About"][section]
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Folders are optional. With folders off, all entries appear together."
        case 2: return "Backups include notes, tasks, folders, and files. The .flow format works with Flow for Android. Import replaces the current library after you confirm."
        case 3: return "Everything stays on this device. No account, analytics, or cloud sync."
        default: return nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        switch (indexPath.section, indexPath.row) {
        case (0, 0): configureSwitch(cell, title: "Folders", value: Preferences.folders, tag: 0)
        case (0, 1): configureSwitch(cell, title: "Swipe gestures", value: Preferences.swipes, tag: 1)
        case (0, 2): configureSwitch(cell, title: "Pure black", value: Preferences.pureBlack, tag: 2)
        case (1, 0): cell.textLabel?.text = "Default entry type"; cell.detailTextLabel?.text = Preferences.defaultKind.rawValue.capitalized
        case (1, 1): cell.textLabel?.text = "Fonts"; cell.detailTextLabel?.text = Preferences.uiFont
        case (1, 2): cell.textLabel?.text = "Preview lines"; cell.detailTextLabel?.text = String(Preferences.previewLines)
        case (1, 3): configureSwitch(cell, title: "Code keyboard", value: Preferences.codeKeyboard, tag: 3)
        case (2, 0): cell.textLabel?.text = isBusy ? "Working…" : "Export backup"; cell.imageView?.image = UIImage(systemName: "square.and.arrow.up")
        case (2, 1): cell.textLabel?.text = "Import backup"; cell.imageView?.image = UIImage(systemName: "square.and.arrow.down")
        default: cell.textLabel?.text = "Flow for iOS"; cell.detailTextLabel?.text = "1.0"
        }
        if indexPath.section == 1 && indexPath.row < 3 { cell.accessoryType = .disclosureIndicator }
        if indexPath.section == 2 { cell.textLabel?.textColor = view.tintColor; cell.isUserInteractionEnabled = !isBusy }
        return cell
    }

    private func configureSwitch(_ cell: UITableViewCell, title: String, value: Bool, tag: Int) {
        cell.textLabel?.text = title
        let toggle = UISwitch()
        toggle.isOn = value
        toggle.tag = tag
        toggle.accessibilityLabel = title
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        cell.accessoryView = toggle
        cell.selectionStyle = .none
    }

    @objc private func toggleChanged(_ toggle: UISwitch) {
        switch toggle.tag {
        case 0: Preferences.folders = toggle.isOn
        case 1: Preferences.swipes = toggle.isOn
        case 2: Preferences.pureBlack = toggle.isOn; tableView.backgroundColor = Theme.background
        default: Preferences.codeKeyboard = toggle.isOn
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (1, 0): choose("Default entry type", values: ["Note", "Task"], selected: Preferences.defaultKind.rawValue.capitalized) { Preferences.defaultKind = $0 == "Task" ? .task : .note }
        case (1, 1):
            let controller = FontSettingsViewController()
            navigationController?.pushViewController(controller, animated: true)
        case (1, 2): choose("Preview lines", values: (1...12).map(String.init), selected: String(Preferences.previewLines)) { Preferences.previewLines = Int($0) ?? 4 }
        case (2, 0): exportBackup()
        case (2, 1):
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.flowBackup, .zip, .json, .data], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        default: break
        }
    }

    private func choose(_ title: String, values: [String], selected: String, action: @escaping (String) -> Void) {
        navigationController?.pushViewController(ChoiceViewController(title: title, values: values, selected: selected) { [weak self] value in
            action(value)
            self?.tableView.reloadData()
        }, animated: true)
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        isModalInPresentation = busy
        navigationController?.isModalInPresentation = busy
        navigationItem.rightBarButtonItem?.isEnabled = !busy
        tableView.reloadData()
    }

    private func exportBackup() {
        guard !isBusy else { return }
        do {
            let library = store.library
            let urls = try Dictionary(uniqueKeysWithValues: library.attachments.map { ($0.id, try store.attachmentURL($0)) })
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("Flow-backup.flow")
            setBusy(true)
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) { try FlowBackup.export(library: library, attachmentURLs: urls, to: url) }.value
                    exportURL = url
                    setBusy(false)
                    let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                    picker.delegate = self
                    present(picker, animated: true)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    setBusy(false)
                    showError(error)
                }
            }
        } catch { showError(error) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanExport() }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportURL != nil { cleanExport(); return }
        guard let url = urls.first else { return }
        setBusy(true)
        Task {
            do {
                let backup = try await Task.detached(priority: .userInitiated) {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try FlowBackup.prepare(from: url)
                }.value
                setBusy(false)
                confirmImport(backup)
            } catch { setBusy(false); showError(error) }
        }
    }

    private func confirmImport(_ backup: PreparedBackup) {
        let library = backup.library
        let notes = library.entries.filter { $0.type == .note }.count
        let tasks = library.entries.count - notes
        let message = "This backup contains \(notes) notes, \(tasks) tasks, \(library.folders.count) folders, and \(library.attachments.count) attachments.\n\nIt will replace all entries and attachments on this device. Export a backup first if you want to keep them."
        let alert = UIAlertController(title: "Replace library?", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Replace library", style: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                try self.store.restore(backup)
                Preferences.currentFolder = Folder.masterID
                self.dismiss(animated: true)
            } catch { self.showError(error) }
        })
        present(alert, animated: true)
    }

    private func cleanExport() {
        if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()) }
        exportURL = nil
    }
}

private final class FontSettingsViewController: UITableViewController {
    init() { super.init(style: .insetGrouped); title = "Fonts" }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = indexPath.row == 0 ? "UI font" : "Editor font"
        cell.detailTextLabel?.text = indexPath.row == 0 ? Preferences.uiFont : Preferences.editorFont
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let editor = indexPath.row == 1
        let values = (editor ? ["UI font"] : []) + ["System", "Monospaced", "Serif"]
        let controller = ChoiceViewController(title: editor ? "Editor font" : "UI font", values: values, selected: editor ? Preferences.editorFont : Preferences.uiFont) { [weak self] value in
            if editor { Preferences.editorFont = value } else { Preferences.uiFont = value }
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(controller, animated: true)
    }
}

private final class ChoiceViewController: UITableViewController {
    private let values: [String]
    private let selected: String
    private let onSelect: (String) -> Void
    init(title: String, values: [String], selected: String, onSelect: @escaping (String) -> Void) {
        self.values = values
        self.selected = selected
        self.onSelect = onSelect
        super.init(style: .insetGrouped)
        self.title = title
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { values.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = values[indexPath.row]
        cell.accessoryType = values[indexPath.row] == selected ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect(values[indexPath.row])
        navigationController?.popViewController(animated: true)
    }
}

extension UTType {
    static let flowBackup = UTType(importedAs: "dev.jvqtil.flow.backup", conformingTo: .zip)
}
