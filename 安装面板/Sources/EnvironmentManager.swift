//
//  EnvironmentManager.swift
//  JobsEnvironmentManager
//
//  Created by Jobs on 2026年11月16日，星期一.
//

import AppKit

struct PanelConfiguration: Decodable {
    let kind: String
    let backend: String
    let preferenceDomain: String
}

struct Component {
    let identifier: String
    let name: String
    let details: String
    let installed: String

    static func parse(_ text: String) throws -> [Component] {
        var seen = Set<String>()
        return try text.split(whereSeparator: \.isNewline).map { line in
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count == 4, !columns[0].isEmpty,
                  columns[0].range(of: #"^[A-Za-z0-9][A-Za-z0-9_.@+-]*$"#, options: .regularExpression) != nil,
                  ["yes", "no", "unknown"].contains(columns[3]),
                  seen.insert(columns[0]).inserted else {
                throw PanelError.message("Invalid component catalog")
            }
            return Component(identifier: columns[0], name: columns[1], details: columns[2], installed: columns[3])
        }
    }
}

/// A selected installer may need Homebrew while repairing its runtime dependency.
enum HomebrewConsent {
    static func requiresLocation(kind: String, uninstall: Bool, selected: [Component], catalog: [Component]) -> Bool {
        guard kind == "system", !uninstall,
              catalog.first(where: { $0.identifier == "homebrew" })?.installed != "yes" else {
            return false
        }
        let runtimeTargets = Set(["homebrew", "rea", "quicktype", "codegraph", "cocoapods", "git-lfs-config"])
        return selected.contains { component in
            return runtimeTargets.contains(component.identifier) ||
                component.identifier.hasPrefix("brew.") || component.identifier.hasPrefix("cask.") ||
                component.identifier.hasPrefix("dependency.")
        }
    }
}

enum PanelError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let value):
            return value
        }
    }
}

/// Keep partial UTF-8 sequences until a whole line arrives from the worker.
final class OutputDecoder {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let line = String(decoding: pending[..<end], as: UTF8.self)
            pending.removeSubrange(...end)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        if pending.count > 65_536 {
            var length = pending.count - 4
            while length > pending.count - 8, String(data: pending.prefix(length), encoding: .utf8) == nil {
                length -= 1
            }
            lines.append(String(decoding: pending.prefix(length), as: UTF8.self))
            pending.removeFirst(length)
        }
        return lines
    }

    func finish() -> [String] {
        defer {
            pending.removeAll()
        }
        return pending.isEmpty ? [] : [String(decoding: pending, as: UTF8.self)]
    }
}

final class PanelStrings {
    static let languages = ["system", "zh-Hans", "zh-Hant", "bo", "en", "ja", "fr", "es", "de", "ru", "ko"]
    static let names = ["", "简体中文", "繁體中文", "བོད་ཡིག", "English", "日本語", "Français", "Español", "Deutsch", "Русский", "한국어"]
    let entries: [String: [String: String]]
    let defaults: UserDefaults

    init(resourceRoot: URL, domain: String) throws {
        let data = try Data(contentsOf: resourceRoot.appendingPathComponent("PanelTranslations.json"))
        entries = try JSONDecoder().decode([String: [String: String]].self, from: data)
        defaults = UserDefaults(suiteName: domain)!
    }

    var language: String {
        get {
            let value = defaults.string(forKey: "language") ?? "system"
            return Self.languages.contains(value) ? value : "system"
        }
        set {
            defaults.set(newValue, forKey: "language")
        }
    }

    var theme: String {
        get {
            let value = defaults.string(forKey: "theme") ?? "system"
            return ["system", "light", "dark"].contains(value) ? value : "system"
        }
        set {
            defaults.set(newValue, forKey: "theme")
        }
    }

    var resolved: String {
        guard language == "system" else {
            return language
        }
        let raw = (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String])?.first ?? Locale.preferredLanguages.first ?? "en"
        let value = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        if value.hasPrefix("zh") {
            return value.contains("hant") || value.contains("tw") || value.contains("hk") || value.contains("mo") ? "zh-Hant" : "zh-Hans"
        }
        let base = value.split(separator: "-").first.map(String.init) ?? "en"
        return Self.languages.contains(base) ? base : "en"
    }

    func text(_ key: String) -> String {
        return entries[resolved]?[key] ?? entries["en"]?[key] ?? key
    }

    func format(_ key: String, _ values: String...) -> String {
        var value = text(key)
        for (index, argument) in values.enumerated() {
            value = value.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        return value
    }

    func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if resolved == "bo" {
            return NSFont(name: "Kailasa", size: max(14, size)) ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
}

final class LogScrollView: NSScrollView {
    var manualScroll: (() -> Void)?
    var appearanceChanged: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            manualScroll?()
        }
        super.scrollWheel(with: event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceChanged?()
    }
}

final class LogTextView: NSTextView {
    var manualScroll: (() -> Void)?
    var strings: PanelStrings?

    override func keyDown(with event: NSEvent) {
        if [115, 116, 119, 121, 123, 124, 125, 126].contains(event.keyCode) {
            manualScroll?()
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        let copy = NSMenuItem(title: strings?.text("Copy") ?? "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)
        let all = NSMenuItem(title: strings?.text("Select all") ?? "Select all", action: #selector(selectAll(_:)), keyEquivalent: "a")
        all.target = self
        menu.addItem(all)
        return menu
    }
}

final class EnvironmentPanel: NSObject,
                              NSApplicationDelegate,
                              NSWindowDelegate,
                              NSTableViewDataSource,
                              NSTableViewDelegate,
                              NSSearchFieldDelegate {
    private let configuration: PanelConfiguration
    private let resources: URL
    private let backend: URL
    private let strings: PanelStrings
    private var window: NSWindow!
    private let heading = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let themeLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let theme = NSPopUpButton()
    private let language = NSPopUpButton()
    private let search = NSSearchField()
    private let selectAll = NSButton()
    private let clearAll = NSButton()
    private let reload = NSButton()
    private let summary = NSTextField(labelWithString: "")
    private let action = NSSegmentedControl(labels: ["", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let run = NSButton()
    private let preview = NSButton()
    private let hide = NSButton()
    private let progress = NSProgressIndicator()
    private let state = NSTextField(wrappingLabelWithString: "")
    private let stop = NSButton()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let table = NSTableView()
    private let logTitle = NSTextField(labelWithString: "")
    private let copyLog = NSButton()
    private let showLog = NSButton()
    private let follow = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let logScroll = LogScrollView()
    private let logText = LogTextView()
    private var components: [Component] = []
    private var visible: [Component] = []
    private var selection = Set<String>()
    private var results: [String: String] = [:]
    private var loading = false
    private var busy = false
    private var confirming = false
    private var worker: Process?
    private var logURL: URL?
    private var logHandle: FileHandle?
    private var statusItem: NSStatusItem?
    private var closeAlert: NSAlert?
    private var pendingClose = false
    private var completed = 0
    private var total = 0
    private var lastStateKey = "Ready. Select features and choose an action."
    private var stateValues: [String] = []
    private var logFailureReported = false
    private var activeAction: String?
    private var stopRequestURL: URL?
    private var stopRequested = false
    private var workerReportedStopped = false

    init(configuration: PanelConfiguration, resources: URL) throws {
        self.configuration = configuration
        self.resources = resources
        backend = resources.appendingPathComponent(configuration.backend)
        guard configuration.kind == "system" || configuration.kind == "env",
              configuration.backend.hasPrefix("package/"), !configuration.backend.contains(".."),
              FileManager.default.isReadableFile(atPath: backend.path) else {
            throw PanelError.message("Missing bundled backend")
        }
        strings = try PanelStrings(resourceRoot: resources, domain: configuration.preferenceDomain)
        super.init()
    }

    private func t(_ key: String) -> String {
        return strings.text(key)
    }

    private var title: String {
        return t(configuration.kind == "system" ? "System Setup Manager" : "Environment Configuration Manager")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        refreshLanguageAndTheme()
        reloadCatalog()
        NotificationCenter.default.addObserver(self, selector: #selector(systemPreferencesChanged), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(systemPreferencesChanged), name: NSLocale.currentLocaleDidChangeNotification, object: nil)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func button(_ button: NSButton, selector: Selector) {
        button.bezelStyle = .rounded
        button.target = self
        button.action = selector
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func row(_ views: [NSView], spacing: CGFloat = 10) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 980, height: 700)
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        theme.target = self
        theme.action = #selector(preferenceChanged)
        language.target = self
        language.action = #selector(preferenceChanged)
        theme.identifier = NSUserInterfaceItemIdentifier("theme")
        language.identifier = NSUserInterfaceItemIdentifier("language")
        let preferences = row([themeLabel, theme, languageLabel, language], spacing: 8)
        let titleRow = row([heading, spacer(), preferences])
        root.addArrangedSubview(titleRow)
        titleRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 3
        root.addArrangedSubview(subtitle)
        subtitle.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.widthAnchor.constraint(greaterThanOrEqualToConstant: 230).isActive = true
        button(selectAll, selector: #selector(selectAllClicked))
        button(clearAll, selector: #selector(clearAllClicked))
        button(reload, selector: #selector(reloadClicked))
        let filters = row([search, selectAll, clearAll, spacer(), reload])
        root.addArrangedSubview(filters)
        filters.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 60
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (identifier, width) in [("check", CGFloat(36)), ("component", 270), ("description", 370), ("status", 210)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.width = width
            column.minWidth = identifier == "check" ? 36 : 100
            if identifier == "check" {
                column.maxWidth = 36
            }
            table.addTableColumn(column)
        }
        let tableScroll = NSScrollView()
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.borderType = .bezelBorder
        let listContainer = NSView()
        tableScroll.translatesAutoresizingMaskIntoConstraints = false
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        listContainer.addSubview(tableScroll)
        listContainer.addSubview(empty)
        NSLayoutConstraint.activate([
            tableScroll.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            tableScroll.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: listContainer.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor),
            empty.widthAnchor.constraint(lessThanOrEqualTo: listContainer.widthAnchor, constant: -60)
        ])
        root.addArrangedSubview(listContainer)
        listContainer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        summary.textColor = .secondaryLabelColor
        root.addArrangedSubview(summary)
        action.selectedSegment = 0
        action.target = self
        action.action = #selector(actionChanged)
        button(run, selector: #selector(runClicked))
        button(preview, selector: #selector(previewClicked))
        button(hide, selector: #selector(hideClicked))
        run.bezelColor = .controlAccentColor
        let actions = row([action, spacer(), preview, run, hide])
        root.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.widthAnchor.constraint(equalToConstant: 120).isActive = true
        state.textColor = .secondaryLabelColor
        state.maximumNumberOfLines = 3
        button(stop, selector: #selector(stopClicked))
        stop.isHidden = configuration.kind != "system"
        let statusRow = row([progress, state, stop])
        root.addArrangedSubview(statusRow)
        statusRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        button(copyLog, selector: #selector(copyLogClicked))
        button(showLog, selector: #selector(showLogClicked))
        follow.state = .on
        follow.target = self
        follow.action = #selector(followChanged)
        let logs = row([logTitle, spacer(), follow, copyLog, showLog])
        root.addArrangedSubview(logs)
        logs.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        logText.isEditable = false
        logText.isSelectable = true
        logText.isRichText = false
        logText.isVerticallyResizable = true
        logText.isHorizontallyResizable = false
        logText.autoresizingMask = [.width]
        logText.minSize = NSSize(width: 0, height: 180)
        logText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logText.textContainer?.widthTracksTextView = true
        logText.textContainerInset = NSSize(width: 10, height: 10)
        logText.strings = strings
        logScroll.documentView = logText
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.manualScroll = { [weak self] in
            self?.follow.state = .off
        }
        logText.manualScroll = logScroll.manualScroll
        logScroll.appearanceChanged = { [weak self] in
            self?.applyLogPalette()
        }
        root.addArrangedSubview(logScroll)
        logScroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        logScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        let preferredLogHeight = logScroll.heightAnchor.constraint(equalToConstant: 180)
        preferredLogHeight.priority = .defaultLow
        preferredLogHeight.isActive = true
        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.autoenablesItems = false
        let close = NSMenuItem(title: t("Close Manager"), action: #selector(hideClicked), keyEquivalent: "w")
        close.target = self
        appMenu.addItem(close)
        let quit = NSMenuItem(title: t("Quit completely"), action: #selector(quitClicked), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = !busy
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let edit = NSMenuItem(title: t("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: t("Edit"))
        editMenu.addItem(withTitle: t("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: t("Select all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApplication.shared.mainMenu = menu
    }

    @objc private func preferenceChanged(_ sender: NSPopUpButton) {
        if sender === theme {
            strings.theme = ["system", "light", "dark"][theme.indexOfSelectedItem]
        } else {
            strings.language = PanelStrings.languages[language.indexOfSelectedItem]
        }
        refreshLanguageAndTheme()
    }

    @objc private func systemPreferencesChanged() {
        refreshLanguageAndTheme()
    }

    private func refreshLanguageAndTheme() {
        window.title = title
        heading.stringValue = title
        heading.font = strings.font(22, weight: .semibold)
        subtitle.stringValue = t("Choose components to install or uninstall. Existing and modified resources are preserved when ownership cannot be verified.")
        subtitle.font = strings.font(12)
        themeLabel.stringValue = t("Theme")
        languageLabel.stringValue = t("Language")
        theme.removeAllItems()
        theme.addItems(withTitles: [t("Follow system"), t("Light"), t("Dark")])
        theme.selectItem(at: ["system", "light", "dark"].firstIndex(of: strings.theme) ?? 0)
        language.removeAllItems()
        language.addItems(withTitles: [t("Follow system")] + Array(PanelStrings.names.dropFirst()))
        language.selectItem(at: PanelStrings.languages.firstIndex(of: strings.language) ?? 0)
        theme.setAccessibilityLabel(t("Theme"))
        language.setAccessibilityLabel(t("Language"))
        search.placeholderString = t("Search components")
        search.setAccessibilityLabel(t("Search components"))
        selectAll.title = t("Select visible")
        clearAll.title = t("Clear all")
        reload.title = t("Reload")
        action.setLabel(t("Install"), forSegment: 0)
        action.setLabel(t("Uninstall"), forSegment: 1)
        action.setAccessibilityLabel(t("Install or uninstall"))
        run.title = t(action.selectedSegment == 1 ? "Uninstall selected" : "Install selected")
        preview.title = t("Preview plan")
        hide.title = t("Background")
        logTitle.stringValue = t("Live log")
        logTitle.font = strings.font(13, weight: .semibold)
        copyLog.title = t("Copy log")
        showLog.title = t("Log file")
        follow.title = t("Auto-scroll")
        for control in [themeLabel, languageLabel, theme, language, search, selectAll, clearAll, reload, summary, action, run, preview, hide, state, stop, empty, copyLog, showLog, follow] as [NSControl] {
            control.font = strings.font(12)
        }
        let titles = ["", t("Component"), t("Description"), t("Status")]
        for (index, column) in table.tableColumns.enumerated() {
            column.title = titles[index]
        }
        switch strings.theme {
        case "light":
            window.appearance = NSAppearance(named: .aqua)
        case "dark":
            window.appearance = NSAppearance(named: .darkAqua)
        default:
            window.appearance = nil
        }
        applyLogPalette()
        applyFilter()
        updateControls()
        buildMenu()
        updateStatusMenu()
    }

    private func applyLogPalette() {
        let dark = window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        logText.backgroundColor = dark ? NSColor(srgbRed: 0.078, green: 0.098, blue: 0.133, alpha: 1) : NSColor(srgbRed: 0.961, green: 0.969, blue: 0.980, alpha: 1)
        logScroll.backgroundColor = logText.backgroundColor
        guard let storage = logText.textStorage else {
            return
        }
        let range = NSRange(location: 0, length: storage.length)
        let originalSelection = logText.selectedRanges
        let origin = logScroll.contentView.bounds.origin
        storage.addAttribute(.foregroundColor, value: dark ? NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1) : NSColor(srgbRed: 0.094, green: 0.133, blue: 0.188, alpha: 1), range: range)
        storage.enumerateAttribute(NSAttributedString.Key("JobsLogKind"), in: range) { value, part, _ in
            if let value = value as? String, value == "error" || value == "success" || value == "warning" {
                storage.addAttribute(.foregroundColor, value: self.logColor(value, dark: dark), range: part)
            }
        }
        logText.selectedRanges = originalSelection
        logScroll.contentView.scroll(to: origin)
        logScroll.reflectScrolledClipView(logScroll.contentView)
    }

    private func logColor(_ kind: String, dark: Bool) -> NSColor {
        switch kind {
        case "error":
            return dark ? NSColor(srgbRed: 1, green: 0.61, blue: 0.57, alpha: 1) : NSColor(srgbRed: 0.71, green: 0.14, blue: 0.09, alpha: 1)
        case "success":
            return dark ? NSColor(srgbRed: 0.46, green: 0.84, blue: 0.61, alpha: 1) : NSColor(srgbRed: 0.08, green: 0.42, blue: 0.22, alpha: 1)
        default:
            return dark ? NSColor(srgbRed: 1, green: 0.82, blue: 0.54, alpha: 1) : NSColor(srgbRed: 0.55, green: 0.32, blue: 0, alpha: 1)
        }
    }

    private func updateControls() {
        let editable = !busy && !loading && !confirming
        run.isEnabled = editable && !selection.isEmpty
        preview.isEnabled = editable && !selection.isEmpty
        action.isEnabled = editable
        selectAll.isEnabled = editable && !visible.isEmpty
        clearAll.isEnabled = editable && !selection.isEmpty
        reload.isEnabled = !busy && !loading && !confirming
        showLog.isEnabled = logURL != nil
        copyLog.isEnabled = !logText.string.isEmpty
        stop.title = t(stopRequested ? "Stop requested" : "Stop acquisition / next steps")
        stop.isEnabled = busy && activeAction == "install" && configuration.kind == "system" && !stopRequested
        summary.stringValue = strings.format("Selected {0} / {1}; visible {2}", String(selection.count), String(components.count), String(visible.count))
        var value = t(lastStateKey)
        for (index, argument) in stateValues.enumerated() {
            value = value.replacingOccurrences(of: "{\(index)}", with: argument)
        }
        state.stringValue = value
        table.reloadData()
    }

    private func setState(_ key: String, _ values: String...) {
        lastStateKey = key
        stateValues = values
        updateControls()
        updateStatusMenu()
    }

    private func friendlyName(_ component: Component) -> String {
        let names = ["clt": "Developer Command Line Tools", "ios-platform": "iOS platform", "oh-my-zsh": "Oh My Zsh", "homebrew": "Homebrew", "git-lfs-config": "Git LFS configuration", "codegraph": "CodeGraph", "quicktype": "Quicktype", "cocoapods": "CocoaPods", "rea": "REA", "jobs-env": "Jobs shell environment", "jobs-software": "Jobs software collection", "env-core": "Environment variables", "shell-behavior": "Shell behavior", "user-mounts": "User mounts", "local-custom": "Local custom configuration", "shell-entry": "Shell entry points", "runtime-support": "Command runtime support"]
        if let key = names[component.identifier] {
            return t(key)
        }
        if component.identifier.hasPrefix("brew.") || component.identifier.hasPrefix("cask.") {
            return String(component.identifier.dropFirst(5))
        }
        if component.identifier.hasPrefix("cmd-") {
            return component.name
        }
        return strings.resolved.hasPrefix("zh") ? component.name : component.identifier
    }

    private func description(_ component: Component) -> String {
        if strings.resolved.hasPrefix("zh") {
            let value = component.details
            return strings.resolved == "zh-Hant" ? value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? value : value
        }
        if component.identifier.hasPrefix("brew.") || component.identifier.hasPrefix("dependency.") {
            return t("Homebrew command-line package")
        }
        if component.identifier.hasPrefix("cask.") {
            return t("Homebrew desktop application")
        }
        if component.identifier.hasPrefix("cmd-") {
            return t("Install or restore this shell command and its files")
        }
        if component.identifier == "rea" {
            return t("REA npm runtime; MCP registration and analysis engines are configured separately")
        }
        return t("Install or restore this environment component")
    }

    private func applyFilter() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visible = components.filter { component in
            return query.isEmpty || [component.identifier, component.name, friendlyName(component), description(component)].contains { $0.localizedCaseInsensitiveContains(query) }
        }
        empty.isHidden = !visible.isEmpty || loading
        empty.stringValue = t(components.isEmpty ? "No components available. Use Reload to try again." : "No matching components. Clear the search or reload.")
        table.reloadData()
        updateControls()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return visible.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < visible.count, let identifier = tableColumn?.identifier.rawValue else {
            return nil
        }
        let component = visible[row]
        if identifier == "check" {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkChanged))
            checkbox.tag = row
            checkbox.state = selection.contains(component.identifier) ? .on : .off
            checkbox.isEnabled = !busy && !loading && !confirming
            checkbox.setAccessibilityLabel(friendlyName(component))
            return checkbox
        }
        let field = NSTextField(wrappingLabelWithString: "")
        field.font = strings.font(identifier == "component" ? 13 : 12, weight: identifier == "component" ? .medium : .regular)
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byTruncatingTail
        if identifier == "component" {
            field.stringValue = friendlyName(component)
            field.toolTip = component.identifier + "\n" + component.name
        } else if identifier == "description" {
            field.stringValue = description(component)
            field.textColor = .secondaryLabelColor
            field.toolTip = field.stringValue
        } else {
            let key = results[component.identifier] ?? (component.installed == "yes" ? "Installed" : component.installed == "no" ? "Not installed" : "Ownership unknown")
            field.stringValue = t(key)
            field.textColor = key == "Failed: see log" ? .systemRed : key == "Completed" ? .systemGreen : key == "Stopped" ? .systemOrange : .secondaryLabelColor
            field.toolTip = t(component.installed == "yes" ? "Installed" : component.installed == "no" ? "Not installed" : "Ownership unknown")
        }
        let cell = NSView()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func checkChanged(_ sender: NSButton) {
        guard sender.tag < visible.count, !busy && !loading && !confirming else {
            return
        }
        let identifier = visible[sender.tag].identifier
        if sender.state == .on {
            selection.insert(identifier)
        } else {
            selection.remove(identifier)
        }
        updateControls()
    }

    @objc private func selectAllClicked() {
        selection.formUnion(visible.map(\.identifier))
        updateControls()
    }

    @objc private func clearAllClicked() {
        selection.removeAll()
        updateControls()
    }

    @objc private func actionChanged() {
        refreshLanguageAndTheme()
    }

    @objc private func reloadClicked() {
        reloadCatalog()
    }

    private func environment() -> [String: String] {
        var value = ProcessInfo.processInfo.environment
        value["NO_COLOR"] = "1"
        value["CLICOLOR"] = "0"
        value["TERM"] = "dumb"
        value["NSUnbufferedIO"] = "YES"
        let inherited = value["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        value["PATH"] = home + "/.local/bin:" + home + "/.homebrew/bin:/opt/homebrew/bin:/usr/local/bin:" + inherited
        return value
    }

    private func reloadCatalog() {
        guard !busy && !loading && !confirming else {
            return
        }
        loading = true
        empty.isHidden = true
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        setState("Reading component status…")
        let path = backend.path
        let env = environment()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [path, "--catalog"]
            process.environment = env
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            let outcome: Result<[Component], Error>
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    throw PanelError.message(String(decoding: data, as: UTF8.self))
                }
                outcome = .success(try Component.parse(String(decoding: data, as: UTF8.self)))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.loading = false
                self.progress.stopAnimation(nil)
                self.progress.isIndeterminate = false
                self.progress.doubleValue = 0
                switch outcome {
                case .success(let values):
                    self.components = values
                    self.selection.formIntersection(values.map(\.identifier))
                    self.setState("Ready. Select features and choose an action.")
                case .failure(let error):
                    self.components = []
                    self.setState("Could not read status. See log and use Reload.")
                    self.appendLog(self.t("Could not read status. See log and use Reload.") + "\n" + error.localizedDescription + "\n", kind: "error")
                }
                self.applyFilter()
            }
        }
    }

    @objc private func previewClicked() {
        beginAction(dryRun: true)
    }

    @objc private func runClicked() {
        beginAction(dryRun: false)
    }

    private func beginAction(dryRun: Bool) {
        guard !busy && !loading && !confirming, !selection.isEmpty else {
            return
        }
        let uninstall = action.selectedSegment == 1
        let selected = components.filter { selection.contains($0.identifier) }
        if dryRun {
            start(selected, uninstall: uninstall, dryRun: true, brewLocation: nil)
            return
        }
        confirming = true
        updateControls()
        let alert = NSAlert()
        alert.window.appearance = window.appearance
        alert.messageText = t(uninstall ? "Confirm uninstall" : "Confirm installation")
        let names = selected.prefix(12).map(friendlyName).joined(separator: "\n") + (selected.count > 12 ? "\n…" : "")
        alert.informativeText = strings.format("Selected {0} components", String(selected.count)) + "\n\n" + names + "\n\n" + t(uninstall ? "Only verified managed changes are restored. Existing, shared or modified resources remain and are reported." : "This changes the selected tools and user configuration. Review the plan before continuing.")
        if !uninstall {
            alert.informativeText += "\n" + t("Missing or unhealthy dependencies required for this task are automatically installed or repaired and rechecked.")
        }
        alert.addButton(withTitle: t("Cancel")).keyEquivalent = "\r"
        alert.addButton(withTitle: t(uninstall ? "Uninstall selected" : "Install selected"))
        var location: NSPopUpButton?
        if HomebrewConsent.requiresLocation(kind: configuration.kind, uninstall: uninstall, selected: selected, catalog: components) {
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
            popup.addItems(withTitles: [t("If required, Homebrew: current user directory"), t("If required, Homebrew: system directory (Terminal)")])
            popup.setAccessibilityLabel(t("Homebrew destination"))
            popup.font = strings.font(12)
            let widestTitle = popup.itemTitles.map { ($0 as NSString).size(withAttributes: [.font: strings.font(12)]).width }.max() ?? 0
            popup.setFrameSize(NSSize(width: max(400, ceil(widestTitle) + 36), height: 30))
            alert.accessoryView = popup
            location = popup
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            self.confirming = false
            self.updateControls()
            guard response == .alertSecondButtonReturn else {
                return
            }
            let destination = location.map { $0.indexOfSelectedItem == 1 ? "system" : "user" }
            self.start(selected, uninstall: uninstall, dryRun: false, brewLocation: destination)
        }
    }

    private func prepareLog() throws {
        try? logHandle?.close()
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("JobsEnvironmentManager/Logs/" + configuration.kind, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let session = directory.appendingPathComponent(stamp + "-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let url = session.appendingPathComponent("session.log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw PanelError.message(t("Could not create log file"))
        }
        logHandle = try FileHandle(forWritingTo: url)
        logURL = url
        stopRequestURL = session.appendingPathComponent("stop-request")
        logText.string = ""
        logFailureReported = false
    }

    private func start(_ selected: [Component], uninstall: Bool, dryRun: Bool, brewLocation: String?) {
        guard !busy else {
            return
        }
        do {
            try prepareLog()
        } catch {
            presentMessage("Could not create log file", detail: error.localizedDescription)
            return
        }
        busy = true
        activeAction = dryRun ? "preview" : uninstall ? "uninstall" : "install"
        stopRequested = false
        workerReportedStopped = false
        completed = 0
        total = selected.count
        results = Dictionary(uniqueKeysWithValues: selected.map { ($0.identifier, "Waiting") })
        progress.isIndeterminate = false
        progress.doubleValue = 0
        setState(dryRun ? "Previewing plan…" : uninstall ? "Uninstalling…" : "Installing…")
        appendLog(t(dryRun ? "Preview plan" : uninstall ? "Uninstall selected" : "Install selected") + "\n" + (logURL?.path ?? "") + "\n")
        buildMenu()
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        var arguments = [backend.path, uninstall ? "--uninstall" : "--install"] + selected.map(\.identifier)
        arguments.append(dryRun ? "--dry-run" : "--yes")
        if let brewLocation {
            arguments += ["--brew-location", brewLocation]
        }
        if configuration.kind == "system", !dryRun, !uninstall, let stopRequestURL {
            arguments += ["--stop-request-file", stopRequestURL.path]
        }
        process.arguments = arguments
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        runWorker(process, pipe: pipe, selected: selected, dryRun: dryRun, uninstall: uninstall)
    }

    private func runWorker(_ process: Process, pipe: Pipe, selected: [Component], dryRun: Bool, uninstall: Bool) {
        worker = process
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var exitStatus: Int32 = 2
            do {
                try process.run()
                let decoder = OutputDecoder()
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty {
                        break
                    }
                    let lines = decoder.append(data)
                    DispatchQueue.main.async {
                        self?.consumeLines(lines, dryRun: dryRun, uninstall: uninstall)
                    }
                }
                let tail = decoder.finish()
                process.waitUntilExit()
                exitStatus = process.terminationStatus
                DispatchQueue.main.async {
                    self?.consumeLines(tail, dryRun: dryRun, uninstall: uninstall)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.appendLog(error.localizedDescription + "\n", kind: "error")
                }
            }
            let code = exitStatus
            DispatchQueue.main.async {
                self?.finishWorker(selected: selected, exitStatus: code)
            }
        }
    }

    private func finishWorker(selected: [Component], exitStatus: Int32) {
        let wasStopped = exitStatus == 130 && (stopRequested || workerReportedStopped)
        let terminal = ["Completed", "Plan ready", "Failed: see log", "Stopped", "Not run"]
        for component in selected where !terminal.contains(results[component.identifier] ?? "") {
            let prior = results[component.identifier]
            results[component.identifier] = wasStopped ? (prior == "Waiting" ? "Not run" : "Stopped") : "Failed: see log"
        }
        let succeeded = selected.filter { ["Completed", "Plan ready"].contains(results[$0.identifier] ?? "") }.count
        let failures = selected.filter { results[$0.identifier] == "Failed: see log" }.count
        let stopped = selected.filter { results[$0.identifier] == "Stopped" }.count
        let notRun = selected.filter { results[$0.identifier] == "Not run" }.count
        busy = false
        worker = nil
        activeAction = nil
        stopRequestURL = nil
        stopRequested = false
        completed = selected.count
        progress.doubleValue = 1
        appendLog(strings.format("Exit code: {0}", String(exitStatus)) + "\n", kind: wasStopped ? "warning" : exitStatus == 0 ? "success" : "error")
        if wasStopped {
            setState("Stopped: {0} succeeded, {1} failed, {2} stopped, {3} not run", String(succeeded), String(failures), String(stopped), String(notRun))
        } else if (exitStatus != 0 && failures == 0) || stopped + notRun > 0 {
            setState("Task failed")
        } else {
            setState("Finished: {0} succeeded, {1} failed", String(succeeded), String(failures))
        }
        appendLog(state.stringValue + "\n", kind: wasStopped ? "warning" : failures == 0 && exitStatus == 0 ? "success" : "error")
        try? logHandle?.synchronize()
        try? logHandle?.close()
        logHandle = nil
        buildMenu()
    }

    /// Only the worker decides when acquisition or the current transaction can stop safely.
    @objc private func stopClicked() {
        guard busy, activeAction == "install", configuration.kind == "system", !stopRequested,
              let stopRequestURL else {
            return
        }
        let temporary = stopRequestURL.deletingLastPathComponent().appendingPathComponent(".stop-request-" + UUID().uuidString)
        do {
            guard FileManager.default.createFile(atPath: temporary.path, contents: Data("stop\n".utf8), attributes: [.posixPermissions: 0o600]) else {
                throw PanelError.message(t("Could not submit stop request"))
            }
            try FileManager.default.moveItem(at: temporary, to: stopRequestURL)
            stopRequested = true
            setState("Stop requested. The current safe unit will finish before stopping.")
            appendLog(t("Stop requested. The current safe unit will finish before stopping.") + "\n", kind: "warning")
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            presentMessage("Could not submit stop request", detail: error.localizedDescription)
        }
    }

    private func consumeLines(_ lines: [String], dryRun: Bool, uninstall: Bool) {
        var output: [String] = []
        for line in lines {
            if line == "JOBS_MANAGER_STOPPED" {
                workerReportedStopped = true
                output.append(line)
                continue
            }
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, parts[0] == "JOBS_MANAGER_EVENT",
                  ["running", "success", "failed", "skipped"].contains(parts[2]) else {
                output.append(line)
                continue
            }
            if results[parts[1]] != nil {
                switch parts[2] {
                case "running":
                    results[parts[1]] = dryRun ? "Previewing plan…" : uninstall ? "Uninstalling…" : "Installing…"
                case "success":
                    results[parts[1]] = dryRun ? "Plan ready" : "Completed"
                case "skipped":
                    results[parts[1]] = parts[3] == "cancelled" ? "Stopped" : "Not run"
                default:
                    results[parts[1]] = "Failed: see log"
                }
            }
            output.append("[" + parts[1] + "] " + parts[3])
        }
        if !output.isEmpty {
            appendLog(output.joined(separator: "\n") + "\n")
        }
        completed = results.values.filter { ["Completed", "Plan ready", "Failed: see log", "Stopped", "Not run"].contains($0) }.count
        progress.doubleValue = total > 0 ? Double(completed) / Double(total) : 0
        if stopRequested {
            setState("Stop requested. The current safe unit will finish before stopping.")
        } else {
            setState("Completed {0} / {1}", String(completed), String(total))
        }
    }

    private func appendLog(_ message: String, kind: String = "normal") {
        let clean = message.replacingOccurrences(of: "\u{1B}\\][^\u{7}\u{1B}]*(?:\u{7}|\u{1B}\\\\)|\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if let logHandle, let data = clean.data(using: .utf8) {
            do {
                try logHandle.write(contentsOf: data)
            } catch {
                if !logFailureReported {
                    logFailureReported = true
                    presentMessage("Log file write failed. Visible output remains available to copy.", detail: error.localizedDescription)
                }
            }
        }
        let dark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let foreground = kind == "normal" ? (dark ? NSColor(srgbRed: 0.90, green: 0.92, blue: 0.95, alpha: 1) : NSColor(srgbRed: 0.094, green: 0.133, blue: 0.188, alpha: 1)) : logColor(kind, dark: dark)
        let attributed = NSAttributedString(string: clean, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: foreground, NSAttributedString.Key("JobsLogKind"): kind])
        logText.textStorage?.append(attributed)
        if let storage = logText.textStorage, storage.length > 1_000_000 {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length - 750_000))
        }
        if follow.state == .on {
            logText.scrollToEndOfDocument(nil)
        }
        copyLog.isEnabled = !logText.string.isEmpty
    }

    @objc private func followChanged() {
        if follow.state == .on {
            logText.scrollToEndOfDocument(nil)
        }
    }

    @objc private func copyLogClicked() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText.string, forType: .string)
    }

    @objc private func showLogClicked() {
        guard let logURL else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([logURL])
    }

    private func presentMessage(_ key: String, detail: String = "") {
        let alert = NSAlert()
        alert.window.appearance = window.appearance
        alert.messageText = t(key)
        alert.informativeText = detail
        alert.addButton(withTitle: t("OK"))
        alert.beginSheetModal(for: window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        requestClose()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestClose()
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreWindow()
        return false
    }

    @objc private func hideClicked() {
        requestClose()
    }

    @objc private func quitClicked() {
        if busy {
            backgroundWindow()
        } else {
            NSApplication.shared.stop(nil)
            wakeRunLoop()
        }
    }

    private func requestClose() {
        if busy {
            backgroundWindow()
            return
        }
        guard !pendingClose && !confirming else {
            return
        }
        pendingClose = true
        let alert = NSAlert()
        closeAlert = alert
        alert.window.appearance = window.appearance
        alert.messageText = t("Close management panel")
        alert.informativeText = t("Keep the manager in the menu bar or quit completely?")
        alert.addButton(withTitle: t("Background"))
        alert.addButton(withTitle: t("Quit completely"))
        alert.addButton(withTitle: t("Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else {
                return
            }
            self.pendingClose = false
            self.closeAlert = nil
            if self.busy || response == .alertFirstButtonReturn {
                self.backgroundWindow()
            } else if response == .alertSecondButtonReturn {
                self.quitClicked()
            }
        }
    }

    private func backgroundWindow() {
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            guard let button = item.button else {
                NSStatusBar.system.removeStatusItem(item)
                return
            }
            let icon = NSApplication.shared.applicationIconImage?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            icon?.isTemplate = false
            button.image = icon
            statusItem = item
        }
        updateStatusMenu()
        window.orderOut(nil)
    }

    private func updateStatusMenu() {
        guard let statusItem else {
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let status = NSMenuItem(title: state.stringValue, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let show = NSMenuItem(title: t("Show management panel"), action: #selector(restoreWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let quit = NSMenuItem(title: t("Quit completely"), action: #selector(quitClicked), keyEquivalent: "")
        quit.target = self
        quit.isEnabled = !busy
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.toolTip = title + "\n" + state.stringValue
        statusItem.button?.setAccessibilityLabel(title)
    }

    @objc private func restoreWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func wakeRunLoop() {
        if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }

    /// The bounded worker exercises the same pipe reader, button action and completion path as installation.
    private func cancellationSmokeTest() throws {
        guard configuration.kind == "system" else {
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JobsPanelStopSmoke-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let request = directory.appendingPathComponent("stop-request")
        let targets = ["rea", "quicktype", "codegraph"].map {
            return Component(identifier: $0, name: $0, details: "Fixture", installed: "no")
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", """
        printf 'JOBS_MANAGER_EVENT\\trea\\tsuccess\\tverified\\n'
        printf 'JOBS_MANAGER_EVENT\\tquicktype\\trunning\\twaiting\\n'
        printf 'fake-first-output\\n'
        for attempt in {1..250}; do
            [[ ! -f "$1" ]] || break
            /bin/sleep 0.02
        done
        [[ -f "$1" ]] || exit 2
        printf 'JOBS_MANAGER_EVENT\\tquicktype\\tskipped\\tcancelled\\n'
        printf 'JOBS_MANAGER_EVENT\\tcodegraph\\tskipped\\tnot-started\\n'
        printf 'JOBS_MANAGER_STOPPED\\n'
        exit 130
        """, "panel-stop-smoke", request.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        components = targets
        selection = Set(targets.map(\.identifier))
        search.stringValue = ""
        results = Dictionary(uniqueKeysWithValues: targets.map { ($0.identifier, "Waiting") })
        total = targets.count
        completed = 0
        busy = true
        activeAction = "install"
        stopRequested = false
        workerReportedStopped = false
        stopRequestURL = request
        applyFilter()
        runWorker(process, pipe: pipe, selected: targets, dryRun: false, uninstall: false)
        requestClose()
        let outputDeadline = Date(timeIntervalSinceNow: 3)
        while busy, !logText.string.contains("fake-first-output"), Date() < outputDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard busy, !window.isVisible, logText.string.contains("fake-first-output"), stop.isEnabled else {
            throw PanelError.message("Background worker output or stop action was unavailable")
        }
        stop.performClick(nil)
        let permissions = try FileManager.default.attributesOfItem(atPath: request.path)[.posixPermissions] as? NSNumber
        guard stopRequested, permissions?.intValue == 0o600 else {
            throw PanelError.message("Stop action did not publish a private request")
        }
        let finishDeadline = Date(timeIntervalSinceNow: 8)
        while busy, Date() < finishDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard !busy, results["rea"] == "Completed", results["quicktype"] == "Stopped",
              results["codegraph"] == "Not run", !results.values.contains("Failed: see log"),
              lastStateKey == "Stopped: {0} succeeded, {1} failed, {2} stopped, {3} not run",
              stateValues == ["1", "0", "1", "1"], !window.isVisible, statusItem != nil else {
            throw PanelError.message("Cooperative stop lost results, logs or background state")
        }
        print("PASS: bounded worker, background pipe output, native stop button, private request file, exit 130 and distinct completed/stopped/not-run results")
    }

    /// Exercise native layout and preferences using a disposable defaults domain.
    func smokeTest() throws {
        buildWindow()
        components = try Component.parse("rea\tREA\tRuntime\tno\ncmd-check\tcheck\tShell command\tyes\n")
        for language in PanelStrings.languages where language != "system" {
            strings.language = language
            for theme in ["system", "light", "dark"] {
                strings.theme = theme
                refreshLanguageAndTheme()
                window.contentView?.layoutSubtreeIfNeeded()
                guard !heading.stringValue.isEmpty, !run.title.isEmpty, selection.isEmpty,
                      table.numberOfRows == 2, !run.isEnabled, !stop.isEnabled,
                      stop.isHidden == (configuration.kind != "system") else {
                    throw PanelError.message("Native panel initialization failed")
                }
            }
        }
        selection.insert("rea")
        updateControls()
        guard run.isEnabled else {
            throw PanelError.message("Selected action stayed disabled")
        }
        action.selectedSegment = 1
        actionChanged()
        guard selection == Set(["rea"]), run.title == t("Uninstall selected") else {
            throw PanelError.message("Changing actions lost selection")
        }
        search.stringValue = "cmd-check"
        applyFilter()
        guard visible.count == 1, visible[0].identifier == "cmd-check" else {
            throw PanelError.message("Component search failed")
        }
        selectAllClicked()
        guard selection == Set(["rea", "cmd-check"]) else {
            throw PanelError.message("Visible selection changed hidden components")
        }
        clearAllClicked()
        guard selection.isEmpty, !run.isEnabled else {
            throw PanelError.message("Empty selection allowed an action")
        }
        follow.state = .off
        appendLog("Native log: 中文\n", kind: "success")
        let originalLog = logText.string
        strings.theme = "dark"
        refreshLanguageAndTheme()
        guard logText.string == originalLog, follow.state == .off else {
            throw PanelError.message("Preferences changed the log or follow state")
        }
        busy = true
        updateControls()
        requestClose()
        guard statusItem != nil, !window.isVisible, !run.isEnabled else {
            throw PanelError.message("Busy close did not preserve background operation")
        }
        guard statusItem?.menu?.items.last?.isEnabled == false else {
            throw PanelError.message("Busy task allowed full exit")
        }
        busy = false
        updateStatusMenu()
        guard statusItem != nil, statusItem?.menu?.items.last?.isEnabled == true else {
            throw PanelError.message("Completion lost the background entry")
        }
        try cancellationSmokeTest()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        strings.defaults.removePersistentDomain(forName: configuration.preferenceDomain)
        window.orderOut(nil)
        print("PASS: native controls, 10 languages × 3 themes, selection/search/action switching, log preservation, busy-close and background retention")
    }
}

func selfTest(resources: URL, configuration: PanelConfiguration) throws {
    let strings = try PanelStrings(resourceRoot: resources, domain: "com.jobs.environmentmanager.selftest." + UUID().uuidString)
    let keys = Set(strings.entries["en"]?.keys.map { $0 } ?? [])
    for language in PanelStrings.languages where language != "system" {
        guard let values = strings.entries[language], keys == Set(values.keys), values.values.allSatisfy({ !$0.isEmpty }) else {
            throw PanelError.message("Incomplete translations: " + language)
        }
    }
    let catalog = try Component.parse("rea\tREA\tRuntime\tno\ncmd-hello\tHello\tCommand\tyes\nbrew.python@3.13\tpython@3.13\tPackage\tunknown\n")
    guard catalog.count == 3 else {
        throw PanelError.message("Catalog parse failed")
    }
    let missingBrew = Component(identifier: "homebrew", name: "Homebrew", details: "", installed: "no")
    let healthyBrew = Component(identifier: "homebrew", name: "Homebrew", details: "", installed: "yes")
    let installationCatalog = catalog + [missingBrew]
    for identifier in ["homebrew", "brew.node", "cask.flutter", "dependency.node@24", "rea", "quicktype", "codegraph", "cocoapods", "git-lfs-config"] {
        let target = Component(identifier: identifier, name: identifier, details: "", installed: "no")
        guard HomebrewConsent.requiresLocation(kind: "system", uninstall: false, selected: [target], catalog: installationCatalog),
              !HomebrewConsent.requiresLocation(kind: "system", uninstall: false, selected: [target], catalog: catalog + [healthyBrew]),
              !HomebrewConsent.requiresLocation(kind: "system", uninstall: true, selected: [target], catalog: installationCatalog),
              !HomebrewConsent.requiresLocation(kind: "env", uninstall: false, selected: [target], catalog: installationCatalog) else {
            throw PanelError.message("Homebrew consent did not match the installation dependency path")
        }
    }
    for identifier in ["clt", "ios-platform", "oh-my-zsh", "jobs-env", "jobs-software"] {
        let target = Component(identifier: identifier, name: identifier, details: "", installed: "no")
        guard !HomebrewConsent.requiresLocation(kind: "system", uninstall: false, selected: [target], catalog: installationCatalog) else {
            throw PanelError.message("Unrelated component requested Homebrew consent")
        }
    }
    do {
        _ = try Component.parse("rea\tREA\tRuntime\tno\nrea\tREA\tRuntime\tno\n")
        throw PanelError.message("Duplicate component accepted")
    } catch PanelError.message(let value) where value == "Invalid component catalog" {
        // Expected rejection keeps duplicate IDs from creating ambiguous actions.
    }
    let decoder = OutputDecoder()
    let bytes = Array("中文\nNext\rDone".utf8)
    var lines: [String] = []
    for byte in bytes {
        lines += decoder.append(Data([byte]))
    }
    lines += decoder.finish()
    guard lines == ["中文", "Next", "Done"] else {
        throw PanelError.message("UTF-8 log framing failed")
    }
    guard FileManager.default.isReadableFile(atPath: resources.appendingPathComponent(configuration.backend).path) else {
        throw PanelError.message("Missing bundled backend")
    }
    print("PASS: translations (10 languages), catalog validation, dependency-path consent, UTF-8 log framing, bundled backend")
}

do {
    guard let resources = Bundle.main.resourceURL else {
        throw PanelError.message("Missing application resources")
    }
    let configuration = try JSONDecoder().decode(PanelConfiguration.self, from: Data(contentsOf: resources.appendingPathComponent("PanelConfiguration.json")))
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.isEmpty || arguments == ["--self-test"] || arguments == ["--diagnose"] || arguments == ["--smoke-test-native"] else {
        throw PanelError.message("Supported options: --self-test, --diagnose, --smoke-test-native")
    }
    if arguments == ["--self-test"] || arguments == ["--diagnose"] {
        try selfTest(resources: resources, configuration: configuration)
        if arguments == ["--diagnose"] {
            print("Resources: " + resources.path)
            print("Backend: " + resources.appendingPathComponent(configuration.backend).path)
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [resources.appendingPathComponent(configuration.backend).path, "--catalog"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw PanelError.message(String(decoding: data, as: UTF8.self))
            }
            let components = try Component.parse(String(decoding: data, as: UTF8.self))
            print("Catalog components: \(components.count); read-only inspection passed")
        }
    } else {
        let application = NSApplication.shared
        let disposable = arguments == ["--smoke-test-native"]
        let profile = disposable ? PanelConfiguration(kind: configuration.kind, backend: configuration.backend, preferenceDomain: "com.jobs.environmentmanager.native-smoke." + UUID().uuidString) : configuration
        let panel = try EnvironmentPanel(configuration: profile, resources: resources)
        application.setActivationPolicy(.regular)
        if disposable {
            application.finishLaunching()
            try panel.smokeTest()
        } else {
            application.delegate = panel
            application.run()
        }
    }
} catch {
    FileHandle.standardError.write(Data(("JobsEnvironmentManager: " + error.localizedDescription + "\n").utf8))
    exit(2)
}
