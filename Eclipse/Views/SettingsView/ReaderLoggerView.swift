//
//  ReaderLoggerView.swift
//  Eclipse
//

import SwiftUI

struct ReaderLoggerView: View {
    @StateObject private var loggerManager = ReaderLoggerManager.shared
    @State private var searchText = ""
    @State private var selectedCategory = "All"
#if !os(tvOS)
    @State private var exportItem: ExportItem?
#endif
    @State private var exportErrorMessage: String?

    private var filteredLogs: [LogEntry] {
        var logs = loggerManager.logs

        if selectedCategory != "All" {
            logs = logs.filter { $0.type == selectedCategory }
        }

        if !searchText.isEmpty {
            logs = logs.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.type.localizedCaseInsensitiveContains(searchText)
            }
        }

        return logs.sorted { $0.timestamp > $1.timestamp }
    }

    private var availableCategories: [String] {
        let categories = Set(loggerManager.logs.map { $0.type }).sorted()
        return ["All"] + categories
    }

    var body: some View {
        List {
            EclipseScrollTracker()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .eclipseHideListRowSeparator()

            Picker("Category", selection: $selectedCategory) {
                ForEach(availableCategories, id: \.self) { category in
                    Text(category).tag(category)
                }
            }
            .pickerStyle(.menu)
            .listRowBackground(Color.clear)
            .eclipseHideListRowSeparator()

            if filteredLogs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary)

                    Text("No reader logs found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .listRowBackground(Color.clear)
                .eclipseHideListRowSeparator()
            } else {
                ForEach(filteredLogs) { log in
                    LogEntryRow(log: log)
                        .id(log.id)
                }
            }
        }
        .navigationTitle("Reader Logs")
        .eclipseSettingsStyle()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
#if !os(tvOS)
                    Button(action: {
                        Task {
                            do {
                                let exportCategory = selectedCategory == "All" ? nil : selectedCategory
                                let url = try await ReaderLogger.shared.exportLogsToTempFile(category: exportCategory)
                                exportItem = ExportItem(url: url)
                            } catch {
                                exportErrorMessage = "Failed to export reader logs."
                            }
                        }
                    }) {
                        Label("Export Reader Logs", systemImage: "square.and.arrow.up")
                    }
#endif
                    Button(action: {
                        loggerManager.clearLogs()
                    }) {
                        Label("Clear Reader Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { _ in exportErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
#if !os(tvOS)
        .sheet(item: $exportItem) { item in
            ActivityView(items: [item.url])
        }
#endif
    }
}

final class ReaderLoggerManager: ObservableObject {
    static let shared = ReaderLoggerManager()

    @Published var logs: [LogEntry] = []
    private let maxLogs = 1000

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLogNotification),
            name: NSNotification.Name("ReaderLoggerNotification"),
            object: nil
        )

        DispatchQueue.main.async {
            self.loadExistingLogs()
        }
    }

    @MainActor
    private func loadExistingLogs() {
        Task {
            let existingLogsString = await ReaderLogger.shared.getLogsAsync()
            if !existingLogsString.isEmpty {
                let logEntries = parseLogsString(existingLogsString)
                DispatchQueue.main.async {
                    self.logs = logEntries
                }
            }
        }
    }

    private func parseLogsString(_ logsString: String) -> [LogEntry] {
        let logSections = logsString.components(separatedBy: "\n----\n")
        var parsedLogs: [LogEntry] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-MM HH:mm:ss"

        for section in logSections {
            guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            let pattern = #"\[([^\]]+)\] \[([^\]]+)\] (.+)"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: section, options: [], range: NSRange(section.startIndex..., in: section)) {

                let timestampRange = Range(match.range(at: 1), in: section)!
                let typeRange = Range(match.range(at: 2), in: section)!
                let messageRange = Range(match.range(at: 3), in: section)!

                let timestampString = String(section[timestampRange])
                let type = ReaderLogger.displayCategory(for: String(section[typeRange]))
                let message = String(section[messageRange])

                if let timestamp = dateFormatter.date(from: timestampString) {
                    parsedLogs.append(LogEntry(timestamp: timestamp, message: message, type: type))
                }
            }
        }

        return parsedLogs.sorted { $0.timestamp > $1.timestamp }
    }

    @objc private func handleLogNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let message = userInfo["message"] as? String,
              let type = userInfo["type"] as? String else { return }

        DispatchQueue.main.async {
            self.addLog(message: message, type: type)
        }
    }

    func addLog(message: String, type: String) {
        let log = LogEntry(timestamp: Date(), message: message, type: ReaderLogger.displayCategory(for: type))
        logs.insert(log, at: 0)

        if logs.count > maxLogs {
            logs = Array(logs.prefix(maxLogs))
        }
    }

    func clearLogs() {
        logs.removeAll()
        Task {
            await ReaderLogger.shared.clearLogsAsync()
        }
    }
}
