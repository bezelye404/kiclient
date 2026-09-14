import SwiftUI
import AppKit

public struct DevConsoleView: View {
    @ObservedObject var logger: AppLogger = AppLogger.shared
    let mpvController: MPVController?
    let onClose: () -> Void

    @State private var selectedCategory: String = "TÜMÜ"
    @State private var selectedLevel: String = "TÜMÜ"
    @State private var searchText: String = ""
    @State private var commandInput: String = ""
    @State private var lastCommandOutput: String = ""
    @State private var autoScroll: Bool = true

    // Canlı donanım metrikleri
    @State private var currentRAMMB: Double = 0.0
    @State private var currentCPUPercent: Double = 0.0
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    public init(mpvController: MPVController? = nil, onClose: @escaping () -> Void) {
        self.mpvController = mpvController
        self.onClose = onClose
    }

    private var filteredEntries: [LogEntry] {
        logger.entries.filter { entry in
            if selectedCategory != "TÜMÜ" && entry.category.rawValue != selectedCategory {
                return false
            }
            if selectedLevel != "TÜMÜ" && entry.level.rawValue != selectedLevel {
                return false
            }
            if !searchText.isEmpty && !entry.message.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Üst Durum ve Başlık Çubuğu
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal.fill")
                        .foregroundColor(.green)
                    Text("Geliştirici Konsolu")
                        .font(.headline)
                }

                Spacer()

                // Canlı Donanım Metrikleri Rozetleri
                HStack(spacing: 8) {
                    metricBadge(title: "RAM", value: String(format: "%.1f MB", currentRAMMB), color: currentRAMMB > 400 ? .orange : .green)
                    metricBadge(title: "CPU", value: String(format: "%.1f%%", currentCPUPercent), color: currentCPUPercent > 20 ? .orange : .blue)
                    metricBadge(title: "Decode", value: "VideoToolbox", color: .purple)
                }

                Divider().frame(height: 18)

                Button(action: {
                    logger.clear()
                    lastCommandOutput = ""
                }) {
                    Label("Temizle", systemImage: "trash")
                }
                .buttonStyle(BorderlessButtonStyle())
                .font(.caption)

                Button(action: {
                    copyLogsToClipboard()
                }) {
                    Label("Kopyala", systemImage: "doc.on.doc")
                }
                .buttonStyle(BorderlessButtonStyle())
                .font(.caption)

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Filtre Çubuğu
            HStack(spacing: 10) {
                Picker("Kategori:", selection: $selectedCategory) {
                    Text("TÜMÜ").tag("TÜMÜ")
                    ForEach(LogCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue).tag(cat.rawValue)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 130)

                Picker("Seviye:", selection: $selectedLevel) {
                    Text("TÜMÜ").tag("TÜMÜ")
                    ForEach(LogLevel.allCases, id: \.self) { lvl in
                        Text(lvl.rawValue).tag(lvl.rawValue)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 110)

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Loglarda ara...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                Toggle("Oto-Kaydır", isOn: $autoScroll)
                    .toggleStyle(CheckboxToggleStyle())
                    .font(.caption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Konsol Log Akışı
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text("[\(entry.category.rawValue)]")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(categoryColor(entry.category))

                                Text("[\(entry.level.rawValue)]")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(levelColor(entry.level))

                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(messageColor(entry.level))
                                    .textSelection(.enabled)
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .background(Color.black.opacity(0.92))
                .onChange(of: logger.entries.count) { _ in
                    if autoScroll, let last = filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Komut Satırı Çıktısı (Son Yanıt Varsa)
            if !lastCommandOutput.isEmpty {
                HStack {
                    Text("Yanıt:")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(lastCommandOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }

            // Alt mpv İnteraktif Komut Girişi
            HStack(spacing: 8) {
                Text(">")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)

                TextField("mpv komutu girin (örn: set volume 70, get_property time-pos, show-text 'Test')", text: $commandInput)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        executeCommand()
                    }

                Button("Çalıştır") {
                    executeCommand()
                }
                .buttonStyle(BorderedButtonStyle())
                .font(.caption)
                .disabled(commandInput.trimmingCharacters(in: .whitespaces).isEmpty || mpvController == nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minHeight: 240, maxHeight: 380)
        .onAppear {
            updateMetrics()
        }
        .onReceive(timer) { _ in
            updateMetrics()
        }
    }

    private func updateMetrics() {
        currentRAMMB = AppLogger.getMemoryUsageMB()
        currentCPUPercent = AppLogger.getCPUUsagePercentage()
    }

    private func executeCommand() {
        guard let controller = mpvController else { return }
        let cmd = commandInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }

        let result = controller.executeUserCommand(cmd)
        lastCommandOutput = result
        commandInput = ""
    }

    private func copyLogsToClipboard() {
        let lines = filteredEntries.map { "[\($0.formattedTime)] [\($0.category.rawValue)] [\($0.level.rawValue)] \($0.message)" }
        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastCommandOutput = "Tüm loglar panoya kopyalandı (\(filteredEntries.count) satır)."
    }

    @ViewBuilder
    private func metricBadge(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }

    private func categoryColor(_ category: LogCategory) -> Color {
        switch category {
        case .system: return .purple
        case .player: return .cyan
        case .chat: return .pink
        case .network: return .orange
        case .auth: return .blue
        }
    }

    private func messageColor(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .debug: return .gray
        case .info: return .white
        }
    }
}
