import SwiftUI
import AppKit

public struct ChatListView: NSViewRepresentable {
    @ObservedObject var viewModel: ChatViewModel
    var fontSize: CGFloat

    public init(viewModel: ChatViewModel, fontSize: CGFloat = 12.0) {
        self.viewModel = viewModel
        self.fontSize = fontSize
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let tableView = ChatTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ChatColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMessages(viewModel.messages)
    }

    public final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ChatListView
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var displayedMessages: [ChatMessage] = []

        init(_ parent: ChatListView) {
            self.parent = parent
        }

        func updateMessages(_ newMessages: [ChatMessage]) {
            guard let tableView = tableView else { return }

            let wasAtBottom = isUserNearBottom()
            displayedMessages = newMessages

            if let col = tableView.tableColumns.first {
                let targetWidth = tableView.bounds.width
                if targetWidth > 50 && abs(col.width - targetWidth) > 2 {
                    col.width = targetWidth
                }
            }

            tableView.reloadData()

            if wasAtBottom && !newMessages.isEmpty {
                DispatchQueue.main.async {
                    tableView.scrollRowToVisible(newMessages.count - 1)
                }
            }
        }

        private func isUserNearBottom() -> Bool {
            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView else { return true }
            let visibleRect = scrollView.contentView.visibleRect
            let docHeight = documentView.bounds.height
            return (visibleRect.origin.y + visibleRect.size.height) >= (docHeight - 50)
        }

        public func numberOfRows(in tableView: NSTableView) -> Int {
            return displayedMessages.count
        }

        public func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < displayedMessages.count else { return 24 }
            let message = displayedMessages[row]
            let colWidth = tableView.tableColumns.first?.width ?? tableView.bounds.width
            let horizontalPadding = DesignTokens.Spacing.lg * 2
            let contentWidth = max(colWidth - horizontalPadding, 100)

            let attrStr = makeAttributedString(for: message)
            let rect = attrStr.boundingRect(
                with: NSSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return max(ceil(rect.height) + 8, 22)
        }

        public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < displayedMessages.count else { return nil }
            let message = displayedMessages[row]

            let identifier = NSUserInterfaceItemIdentifier("ChatCell")
            var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = identifier
                let textField = NSTextField(labelWithAttributedString: NSAttributedString())
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byWordWrapping
                textField.maximumNumberOfLines = 0
                textField.isSelectable = true
                cell?.addSubview(textField)
                cell?.textField = textField

                if let cell = cell {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: DesignTokens.Spacing.lg),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -DesignTokens.Spacing.lg),
                        textField.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                        textField.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
                    ])
                }
            }

            cell?.textField?.attributedStringValue = makeAttributedString(for: message)
            return cell
        }

        private func makeAttributedString(for message: ChatMessage) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let baseSize = parent.fontSize
            let badgeSize = max(baseSize - 2, 9)

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2.5
            paragraphStyle.lineBreakMode = .byWordWrapping

            // Rozetler
            for badge in message.badges {
                let badgeType = badge.type.lowercased()
                let badgeColor: NSColor
                let badgeLabel: String

                switch badgeType {
                case "moderator":
                    badgeLabel = "MOD"
                    badgeColor = NSColor.systemGreen
                case "subscriber":
                    badgeLabel = "SUB"
                    badgeColor = NSColor.systemPurple
                case "vip":
                    badgeLabel = "VIP"
                    badgeColor = NSColor.systemPink
                case "broadcaster":
                    badgeLabel = "HOST"
                    badgeColor = NSColor.systemRed
                default:
                    badgeLabel = String(badge.type.prefix(3)).uppercased()
                    badgeColor = NSColor.systemGray
                }

                let badgeAttr = NSAttributedString(
                    string: "[\(badgeLabel)] ",
                    attributes: [
                        .font: NSFont.boldSystemFont(ofSize: badgeSize),
                        .foregroundColor: badgeColor,
                        .paragraphStyle: paragraphStyle
                    ]
                )
                result.append(badgeAttr)
            }

            // Gönderen kullanıcı adı
            var senderColor = NSColor.systemBlue
            if let hex = message.senderColorHex, let customColor = NSColor(hexString: hex) {
                senderColor = customColor
            }

            let usernameAttr = NSAttributedString(
                string: "\(message.senderUsername): ",
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: baseSize),
                    .foregroundColor: senderColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
            result.append(usernameAttr)

            // Mesaj metni
            let messageAttr = NSAttributedString(
                string: message.content,
                attributes: [
                    .font: NSFont.systemFont(ofSize: baseSize),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle
                ]
            )
            result.append(messageAttr)

            return result
        }
    }
}

final class ChatTableView: NSTableView {
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        if let col = tableColumns.first {
            col.width = bounds.width
        }
        noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<numberOfRows))
    }
}

// Hex renk çevirici
private extension NSColor {
    convenience init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let intVal = UInt64(hex, radix: 16) else {
            return nil
        }
        let r = CGFloat((intVal >> 16) & 0xFF) / 255.0
        let g = CGFloat((intVal >> 8) & 0xFF) / 255.0
        let b = CGFloat(intVal & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
