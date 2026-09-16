import UIKit
import FlowCore

final class FoldersViewController: UITableViewController {
    enum Mode {
        case select((String) -> Void)
        case move((String) -> Void)
        var onSelect: (String) -> Void {
            switch self { case .select(let action), .move(let action): return action }
        }
    }
    private let store: FlowStore
    private let mode: Mode
    private var folders: [Folder] = []
    private var entryCounts: [String: Int] = [:]

    init(store: FlowStore, mode: Mode) {
        self.store = store
        self.mode = mode
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        if case .move = mode { title = "Move to folder" } else { title = "Folders" }
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addFolder)), editButtonItem]
        navigationItem.rightBarButtonItems?.first?.accessibilityLabel = "New folder"
        tableView.dragInteractionEnabled = true
        reload()
    }

    private func reload() {
        folders = store.folders
        entryCounts = store.library.entries.reduce(into: [:]) { $0[$1.folderId, default: 0] += 1 }
        tableView.reloadData()
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func addFolder() { editFolder(nil) }

    private func editFolder(_ folder: Folder?) {
        let alert = UIAlertController(title: folder == nil ? "New folder" : "Rename folder", message: nil, preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "Name"; field.text = folder?.name; field.autocapitalizationType = .sentences }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            var updated = folder ?? Folder(name: "")
            updated.name = alert?.textFields?.first?.text ?? ""
            self.performStoreAction { try self.store.saveFolder(updated) }
            self.reload()
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { folders.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let folder = folders[indexPath.row]
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = folder.name
        content.secondaryText = "\(entryCounts[folder.id, default: 0])"
        content.image = UIImage(systemName: "folder")
        cell.contentConfiguration = content
        cell.accessoryType = folder.id == Preferences.currentFolder ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let folder = folders[indexPath.row]
        if isEditing { editFolder(folder) }
        else { dismiss(animated: true) { [mode] in mode.onSelect(folder.id) } }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.allowsSelectionDuringEditing = true
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let folder = folders.remove(at: source.row)
        folders.insert(folder, at: destination.row)
        performStoreAction { try store.reorderFolders(folders.map(\.id)) }
        reload()
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        folders[indexPath.row].id == Folder.masterID ? .none : .delete
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        let folder = folders[indexPath.row]
        let count = store.entries(in: folder.id).count
        let alert = UIAlertController(title: "Delete \(folder.name)?", message: "This also deletes \(count) entries. You can undo this from the home screen.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.performStoreAction { try self.store.deleteFolder(folder.id) }
            self.reload()
        })
        present(alert, animated: true)
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let folder = folders[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in self?.editFolder(folder) }])
        }
    }
}
