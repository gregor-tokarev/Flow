import UIKit
import UniformTypeIdentifiers
import QuickLook
import FlowCore

final class EditorViewController: UIViewController, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate,
                                  UIDocumentPickerDelegate, QLPreviewControllerDataSource {
    private let store: FlowStore
    private var entry: Entry
    private let isNew: Bool
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let kindControl = UISegmentedControl(items: ["Note", "Task"])
    private let attachmentsTable = UITableView(frame: .zero, style: .plain)
    private var attachments: [Attachment] = []
    private var attachmentsHeight: NSLayoutConstraint!
    private var previewItem: AttachmentPreview?
    private var errorPresented = false

    init(store: FlowStore, entry: Entry, isNew: Bool = false) {
        self.store = store
        self.entry = entry
        self.isNew = isNew
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.titleView = kindControl
        kindControl.selectedSegmentIndex = entry.type == .note ? 0 : 1
        kindControl.addTarget(self, action: #selector(kindChanged), for: .valueChanged)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        textView.delegate = self
        textView.text = entry.text
        textView.font = Theme.font(editor: true)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        textView.accessibilityLabel = "Entry text"
        textView.accessibilityIdentifier = "entryText"
        let keyboardToolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        let attach = UIBarButtonItem(image: UIImage(systemName: "paperclip"), style: .plain, target: self, action: #selector(addAttachment))
        attach.accessibilityLabel = "Attach file"
        let hideKeyboard = UIBarButtonItem(image: UIImage(systemName: "keyboard.chevron.compact.down"), style: .plain, target: self, action: #selector(dismissKeyboard))
        hideKeyboard.accessibilityLabel = "Hide keyboard"
        hideKeyboard.accessibilityIdentifier = "hideEntryKeyboard"
        keyboardToolbar.items = [attach, .flexibleSpace(), hideKeyboard]
        textView.inputAccessoryView = keyboardToolbar
        if Preferences.codeKeyboard {
            textView.autocorrectionType = .no
            textView.autocapitalizationType = .none
            textView.smartQuotesType = .no
            textView.smartDashesType = .no
            textView.spellCheckingType = .no
        }
        placeholder.text = "Any ideas?"
        placeholder.font = textView.font
        placeholder.textColor = .placeholderText
        placeholder.isUserInteractionEnabled = false
        placeholder.isAccessibilityElement = false
        textView.addSubview(placeholder)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: textView.contentLayoutGuide.topAnchor, constant: 24),
            placeholder.leadingAnchor.constraint(equalTo: textView.frameLayoutGuide.leadingAnchor, constant: 25)
        ])
        placeholder.isHidden = !entry.text.isEmpty
        attachmentsTable.dataSource = self
        attachmentsTable.delegate = self
        attachmentsTable.backgroundColor = .clear
        attachmentsTable.rowHeight = 60
        attachmentsTable.accessibilityLabel = "Attachments"
        let stack = UIStackView(arrangedSubviews: [textView, attachmentsTable])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        attachmentsHeight = attachmentsTable.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            attachmentsHeight
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(saveRequested), name: .flowSaveRequested, object: nil)
        refreshAttachments()
        updateToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew && entry.text.isEmpty && attachments.isEmpty { textView.becomeFirstResponder() }
    }

    func textViewDidChange(_ textView: UITextView) {
        entry.text = textView.text
        placeholder.isHidden = !entry.text.isEmpty
        saveRequested()
    }

    @objc private func saveRequested() {
        do { try save() }
        catch {
            guard !errorPresented else { return }
            errorPresented = true
            let alert = UIAlertController(title: "Your changes could not be saved", message: error.localizedDescription + "\nKeep this editor open and try again.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.errorPresented = false })
            present(alert, animated: true)
        }
    }

    private func save(force: Bool = false) throws {
        if let saved = store.entry(entry.id) { entry.position = saved.position }
        if !force && store.entry(entry.id) == nil && entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        try store.save(entry)
    }

    @objc private func done() {
        do { try save(); navigationController?.popViewController(animated: true) }
        catch { showError(error) }
    }

    @objc private func dismissKeyboard() { textView.resignFirstResponder() }

    @objc private func kindChanged() {
        entry.type = kindControl.selectedSegmentIndex == 0 ? .note : .task
        if entry.type == .note { entry.completed = false }
        saveRequested()
        updateToolbar()
    }

    private func updateToolbar() {
        let attach = UIBarButtonItem(image: UIImage(systemName: "paperclip"), style: .plain, target: self, action: #selector(addAttachment))
        attach.accessibilityLabel = "Attach file"
        let share = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareEntry))
        let undo = UIBarButtonItem(title: "Undo", style: .plain, target: self, action: #selector(undoDelete))
        undo.isEnabled = store.undoActionName != nil
        var actions: [UIMenuElement] = []
        if Preferences.folders {
            actions.append(UIAction(title: "Move to folder", image: UIImage(systemName: "folder")) { [weak self] _ in self?.moveEntry() })
        }
        actions.append(UIAction(title: "Delete entry", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            do {
                if self.store.entry(self.entry.id) != nil { try self.store.deleteEntry(self.entry.id) }
                self.navigationController?.popViewController(animated: true)
            } catch { self.showError(error) }
        })
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: UIMenu(children: actions))
        more.accessibilityLabel = "Entry actions"
        var items: [UIBarButtonItem] = [attach, .flexibleSpace(), share, .flexibleSpace(), undo]
        if entry.type == .task {
            let completed = UIBarButtonItem(image: UIImage(systemName: entry.completed ? "checkmark.circle.fill" : "circle"), style: .plain, target: self, action: #selector(toggleCompleted))
            completed.accessibilityLabel = entry.completed ? "Mark incomplete" : "Complete task"
            items += [.flexibleSpace(), completed]
        }
        items += [.flexibleSpace(), more]
        toolbarItems = items
    }

    @objc private func toggleCompleted() {
        entry.completed.toggle()
        saveRequested()
        updateToolbar()
    }

    private func moveEntry() {
        let picker = FoldersViewController(store: store, mode: .move { [weak self] id in
            guard let self else { return }
            do {
                try self.save(force: true)
                try self.store.moveEntry(self.entry.id, to: id)
                if let entry = self.store.entry(self.entry.id) { self.entry = entry }
            } catch { self.showError(error) }
        })
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    @objc private func addAttachment() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = self
        textView.resignFirstResponder()
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        do {
            try save(force: true)
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
                try store.addAttachment(from: url, to: entry.id, mimeType: type?.preferredMIMEType)
            }
        } catch { showError(error) }
        refreshAttachments()
    }

    private func refreshAttachments() {
        attachments = store.attachments(for: entry.id)
        attachmentsHeight.constant = CGFloat(min(attachments.count, 3)) * 60
        attachmentsTable.reloadData()
        updateToolbar()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { attachments.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let attachment = attachments[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        content.text = attachment.fileName
        content.secondaryText = ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file)
        content.image = UIImage(systemName: "doc")
        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        do {
            let attachment = attachments[indexPath.row]
            previewItem = AttachmentPreview(url: try store.attachmentURL(attachment), title: attachment.fileName)
            let preview = QLPreviewController()
            preview.dataSource = self
            present(preview, animated: true)
        } catch { showError(error) }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let attachment = attachments[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.performStoreAction { try self.store.deleteAttachment(attachment.id) }
            self.refreshAttachments()
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func undoDelete() {
        performStoreAction { try store.undoDeletion() }
        refreshAttachments()
    }

    @objc private func shareEntry(_ sender: UIBarButtonItem) {
        do {
            try save()
            var items: [Any] = []
            if !entry.text.isEmpty { items.append(entry.text) }
            items += try attachments.map { try store.attachmentURL($0) }
            guard !items.isEmpty else { return }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            sheet.popoverPresentationController?.barButtonItem = sender
            present(sheet, animated: true)
        } catch { showError(error) }
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewItem == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { previewItem! }
}

private final class AttachmentPreview: NSObject, QLPreviewItem {
    let previewItemURL: URL?
    let previewItemTitle: String?
    init(url: URL, title: String) { previewItemURL = url; previewItemTitle = title }
}
