import AppKit

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Superwhisper-style history: a search field on top and transcriptions shown as
/// rounded cards grouped by day. Click a card to copy it to the clipboard.
final class HistoryCardsView: NSView, NSSearchFieldDelegate {
    private let searchField = NSSearchField()
    private let stack = NSStackView()

    private let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"; return f
    }()
    private let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; return f
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let entries = HistoryStore.shared.search(searchField.stringValue)

        if entries.isEmpty {
            let empty = NSTextField(labelWithString: searchField.stringValue.isEmpty ? "No transcriptions yet." : "No matches.")
            empty.font = .systemFont(ofSize: 13)
            empty.textColor = .secondaryLabelColor
            stack.addArrangedSubview(empty)
            return
        }

        var lastDay = ""
        for entry in entries {
            let day = dayLabel(for: entry.date)
            if day != lastDay {
                stack.addArrangedSubview(headerLabel(day))
                lastDay = day
            }
            let c = card(for: entry)
            stack.addArrangedSubview(c)
            // Pin width AFTER insertion, so the card and stack share a common ancestor.
            c.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    // MARK: - Build

    private func build() {
        searchField.placeholderString = "Search history"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.controlSize = .large
        searchField.font = .systemFont(ofSize: 14)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scrollView.documentView = doc

        addSubview(searchField)
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            doc.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: doc.bottomAnchor, constant: -16),
        ])
    }

    private func headerLabel(_ text: String) -> NSView {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = .secondaryLabelColor
        // small top padding before each group
        let wrap = NSStackView(views: [l])
        wrap.orientation = .vertical
        wrap.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        return wrap
    }

    private func card(for entry: HistoryEntry) -> NSView {
        let row = ClickableRow(action: { [weak self] in self?.copy(entry.text) })
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        row.layer?.cornerRadius = 10

        let text = NSTextField(wrappingLabelWithString: entry.text)
        text.font = .systemFont(ofSize: 14)
        text.maximumNumberOfLines = 4
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false

        var captionText = timeFormatter.string(from: entry.date)
        if let app = entry.appName, !app.isEmpty { captionText = "\(app) • \(captionText)" }
        let caption = NSTextField(labelWithString: captionText)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .tertiaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(text)
        row.addSubview(caption)
        NSLayoutConstraint.activate([
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            text.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            caption.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 6),
            caption.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            caption.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            caption.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
        ])
        return row
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayHeaderFormatter.string(from: date)
    }

    func controlTextDidChange(_ obj: Notification) { reload() }
}
