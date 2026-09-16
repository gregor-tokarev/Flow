import UIKit
import FlowCore

final class HomeViewController: UITableViewController, UISearchResultsUpdating {
    private let store: FlowStore
    private var entries: [Entry] = []
    private let search = UISearchController(searchResultsController: nil)
    private let emptyLabel = UILabel()
    private var activeFolder: String? { Preferences.folders ? Preferences.currentFolder : nil }

    init(store: FlowStore) {
        self.store = store
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Flow"
        tableView.register(EntryCell.self, forCellReuseIdentifier: "Entry")
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 108
        tableView.keyboardDismissMode = .onDrag
        tableView.cellLayoutMarginsFollowReadableWidth = true
        tableView.dragInteractionEnabled = true
        tableView.accessibilityIdentifier = "entries"
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = "Search entries"
        navigationItem.searchController = search
        definesPresentationContext = true
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(openSettings)),
            editButtonItem
        ]
        navigationItem.rightBarButtonItems?.first?.accessibilityLabel = "Settings"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        store.onChange = { [weak self] in self?.reload() }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .flowPreferencesChanged, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
        reload()
    }

    @objc private func reload() {
        guard isViewLoaded else { return }
        if !store.folders.contains(where: { $0.id == Preferences.currentFolder }) {
            Preferences.currentFolder = Folder.masterID
        }
        tableView.backgroundColor = Theme.background
        let query = search.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        entries = store.entries(in: activeFolder).filter { query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) }
        tableView.reloadData()
        emptyLabel.text = query.isEmpty ? "Nothing here yet.\nTap + to add a note or task." : "No matching entries."
        tableView.backgroundView = entries.isEmpty ? emptyLabel : nil
        if Preferences.folders {
            let folder = store.folders.first { $0.id == Preferences.currentFolder }
            let button = UIBarButtonItem(title: folder?.name ?? "Master", image: UIImage(systemName: "folder"), target: self, action: #selector(openFolders))
            button.accessibilityLabel = "Folders"
            navigationItem.leftBarButtonItem = button
        } else {
            navigationItem.leftBarButtonItem = nil
        }
        let undo = UIBarButtonItem(title: "Undo", image: UIImage(systemName: "arrow.uturn.backward"), target: self, action: #selector(undoDelete))
        undo.isEnabled = store.undoActionName != nil
        undo.accessibilityHint = store.undoActionName
        let countLabel = UILabel()
        countLabel.text = "\(entries.count) \(entries.count == 1 ? "entry" : "entries")"
        countLabel.font = .preferredFont(forTextStyle: .footnote)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        let count = UIBarButtonItem(customView: countLabel)
        let add = UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: self, action: #selector(addEntry))
        add.accessibilityLabel = "New entry"
        add.accessibilityIdentifier = "newEntry"
        toolbarItems = [undo, .flexibleSpace(), count, .flexibleSpace(), add]
    }

    func updateSearchResults(for searchController: UISearchController) { reload() }

    @objc private func addEntry() {
        let entry = Entry(type: Preferences.defaultKind, folderId: Preferences.folders ? Preferences.currentFolder : Folder.masterID)
        let editor = EditorViewController(store: store, entry: entry, isNew: true)
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func openSettings() {
        let navigation = UINavigationController(rootViewController: SettingsViewController(store: store))
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    @objc private func openFolders() {
        let controller = FoldersViewController(store: store, mode: .select { [weak self] id in
            Preferences.currentFolder = id
            self?.reload()
        })
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func undoDelete() { performStoreAction { try store.undoDeletion() } }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { entries.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = entries[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Entry", for: indexPath) as! EntryCell
        cell.configure(entry, hasAttachments: !store.attachments(for: entry.id).isEmpty)
        cell.onToggle = { [weak self] in
            guard let self else { return }
            self.performStoreAction { try self.store.toggleCompleted(entry.id) }
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        navigationController?.pushViewController(EditorViewController(store: store, entry: entries[indexPath.row]), animated: true)
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        search.searchBar.text?.isEmpty != false
    }

    override func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
        let entry = entries.remove(at: source.row)
        entries.insert(entry, at: destination.row)
        performStoreAction { try store.reorderEntries(entries.map(\.id), in: activeFolder) }
        reload()
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete { delete(entries[indexPath.row]) }
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Preferences.swipes else { return UISwipeActionsConfiguration(actions: []) }
        let entry = entries[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.delete(entry)
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard Preferences.swipes else { return UISwipeActionsConfiguration(actions: []) }
        let entry = entries[indexPath.row]
        let action = UIContextualAction(style: .normal, title: entry.type == .task ? "Toggle" : "Make task") { [weak self] _, _, done in
            self?.performStoreAction {
                guard let self else { return }
                if entry.type == .task { try self.store.toggleCompleted(entry.id) }
                else { var updated = entry; updated.type = .task; try self.store.save(updated) }
            }
            done(true)
        }
        action.backgroundColor = Theme.accent
        action.image = UIImage(systemName: "checkmark.circle")
        return UISwipeActionsConfiguration(actions: [action])
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let entry = entries[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let convert = UIAction(title: entry.type == .note ? "Make task" : "Make note", image: UIImage(systemName: "checklist")) { _ in
                var updated = entry
                updated.type = entry.type == .note ? .task : .note
                updated.completed = false
                self.performStoreAction { try self.store.save(updated) }
            }
            var actions: [UIMenuElement] = [convert]
            if Preferences.folders {
                actions.append(UIAction(title: "Move to folder", image: UIImage(systemName: "folder")) { _ in
                    let picker = FoldersViewController(store: self.store, mode: .move { id in
                        self.performStoreAction { try self.store.moveEntry(entry.id, to: id) }
                    })
                    self.present(UINavigationController(rootViewController: picker), animated: true)
                })
            }
            actions.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self.delete(entry) })
            return UIMenu(children: actions)
        }
    }

    private func delete(_ entry: Entry) { performStoreAction { try store.deleteEntry(entry.id) } }
}

private final class EntryCell: UITableViewCell {
    var onToggle: (() -> Void)?
    private let card = UIView()
    private let text = UILabel()
    private let toggle = UIButton(type: .system)
    private let attachment = UIImageView(image: UIImage(systemName: "paperclip"))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        text.adjustsFontForContentSizeCategory = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toggle.addTarget(self, action: #selector(toggled), for: .touchUpInside)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.widthAnchor.constraint(equalToConstant: 44).isActive = true
        toggle.heightAnchor.constraint(equalToConstant: 44).isActive = true
        attachment.tintColor = .tertiaryLabel
        attachment.contentMode = .scaleAspectFit
        attachment.widthAnchor.constraint(equalToConstant: 16).isActive = true
        attachment.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let stack = UIStackView(arrangedSubviews: [toggle, text, attachment])
        stack.alignment = .top
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func toggled() { onToggle?() }

    func configure(_ entry: Entry, hasAttachments: Bool) {
        text.font = Theme.font()
        text.numberOfLines = Preferences.previewLines
        text.textColor = entry.completed ? .secondaryLabel : .label
        let value = entry.text.isEmpty ? (hasAttachments ? "Attachment" : "Empty \(entry.type.rawValue)") : entry.text
        text.attributedText = NSAttributedString(string: value, attributes: entry.completed ? [.strikethroughStyle: NSUnderlineStyle.single.rawValue] : [:])
        toggle.isHidden = entry.type != .task
        toggle.setImage(UIImage(systemName: entry.completed ? "checkmark.circle.fill" : "circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 24)), for: .normal)
        toggle.accessibilityLabel = entry.completed ? "Mark incomplete" : "Complete task"
        toggle.accessibilityValue = entry.completed ? "Completed" : "Incomplete"
        attachment.isHidden = !hasAttachments
        attachment.accessibilityLabel = "Has attachments"
        attachment.isAccessibilityElement = hasAttachments
    }
}
