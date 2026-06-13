//
//  BackupManagementView.swift
//  Eclipse
//
//  Created by Soupy-dev on 05/01/2026.
//

import SwiftUI
import UniformTypeIdentifiers

#if !os(tvOS)
struct BackupDocument: FileDocument {
    var data: Data
    
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    static var importableContentTypes: [UTType] { [.json, .plainText, .text, .data] }
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}
#endif

struct BackupManagementView: View {
    @State private var showRestoreConfirmation = false
    @State private var showMessageAlert = false
    @State private var backupMessage = ""
    @State private var isProcessing = false
    @State private var showDocumentPicker = false
    @State private var showBackupExporter = false
    @State private var selectedBackupURL: URL? = nil
    @State private var backupFileToExport: Data? = nil
    @State private var backupFileName = ""
    
    var body: some View {
        List {
            Section {
                Button(action: createBackup) {
                    HStack {
                        Label("Create Backup", systemImage: "arrow.up.doc")
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isProcessing)
                .foregroundColor(.primary)
            } header: {
                Text("Export")
            } footer: {
                Text("Create a backup file containing all your collections, settings, watch progress, tracker logins including MAL, and service configurations.")
            }
            .background(EclipseScrollTracker())
            
            Section {
                Button(action: { showDocumentPicker = true }) {
                    HStack {
                        Label("Import Backup", systemImage: "arrow.down.doc")
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isProcessing)
                .foregroundColor(.primary)
            } header: {
                Text("Import")
            } footer: {
                Text("Restore all data from a previously saved backup file. This will overwrite your current settings and progress.")
            }
            
            if !backupMessage.isEmpty {
                Section {
                    HStack {
                        Image(systemName: backupMessage.contains("Success") || backupMessage.contains("created") ? "checkmark.circle" : "info.circle")
                            .foregroundColor(backupMessage.contains("Success") || backupMessage.contains("created") ? .green : .blue)
                        Text(backupMessage)
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Backup & Import")
        .eclipseSettingsStyle()
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showDocumentPicker,
            allowedContentTypes: BackupDocument.importableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleImportResult(result)
        }
        .fileExporter(
            isPresented: $showBackupExporter,
            document: BackupDocument(data: backupFileToExport ?? Data()),
            contentType: .json,
            defaultFilename: backupFileName
        ) { result in
            isProcessing = false
            switch result {
            case .success:
                backupMessage = "Backup saved successfully!"
                showMessageAlert = true
                Logger.shared.log("Backup saved successfully", type: "Info")
            case .failure(let error):
                backupMessage = "Failed to save backup: \(error.localizedDescription)"
                showMessageAlert = true
                Logger.shared.log("Backup save failed: \(error.localizedDescription)", type: "Error")
            }
        }
        #endif
        .alert("Restore Confirmation", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) {
                clearSelectedBackup()
            }
            Button("Restore", role: .destructive) {
                performRestore()
            }
        } message: {
            Text("This will overwrite your current settings, collections, watch progress, tracker logins including MAL, and service configurations with the backup data. Continue?")
        }
        .alert("Message", isPresented: $showMessageAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupMessage)
        }
    }
    
    private func createBackup() {
        isProcessing = true
        backupMessage = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let backupURL = BackupManager.shared.createBackup() {
                DispatchQueue.main.async {
                    // Prepare file for export and show file exporter
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                    backupFileName = "Eclipse_Backup_\(dateFormatter.string(from: Date())).json"
                    
                    if let fileData = try? Data(contentsOf: backupURL) {
                        backupFileToExport = fileData
                        showBackupExporter = true
                    } else {
                        backupMessage = "Failed to read backup file."
                    }
                    isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    isProcessing = false
                    backupMessage = "Failed to create backup. Please try again."
                }
            }
        }
    }
    
    #if !os(tvOS)
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let selectedFile = urls.first else {
                backupMessage = "No backup file selected"
                showMessageAlert = true
                return
            }

            do {
                clearSelectedBackup()
                self.selectedBackupURL = try prepareSelectedBackupForRestore(from: selectedFile)
                // Ask for confirmation before restoring
                showRestoreConfirmation = true
            } catch {
                backupMessage = "Failed to select file: \(error.localizedDescription)"
                showMessageAlert = true
                Logger.shared.log("Import file preparation failed: \(error.localizedDescription)", type: "Error")
            }
            
        case .failure(let error):
            backupMessage = "Failed to select file: \(error.localizedDescription)"
            showMessageAlert = true
            Logger.shared.log("Import error: \(error.localizedDescription)", type: "Error")
        }
    }
    #endif
    
    private func performRestore() {
        guard let backupURL = selectedBackupURL else {
            backupMessage = "No backup file selected"
            showMessageAlert = true
            return
        }
        
        isProcessing = true
        backupMessage = ""
        showRestoreConfirmation = false
        
        DispatchQueue.global(qos: .userInitiated).async {
            let success = BackupManager.shared.restoreBackup(from: backupURL)
            try? FileManager.default.removeItem(at: backupURL)
            
            DispatchQueue.main.async {
                isProcessing = false
                selectedBackupURL = nil
                if success {
                    backupMessage = "Backup restored successfully! Please restart the app to see all changes."
                } else {
                    backupMessage = "Failed to restore backup. The file may be corrupted or completely incompatible."
                }
                showMessageAlert = true
            }
        }
    }

    private func clearSelectedBackup() {
        if let selectedBackupURL {
            try? FileManager.default.removeItem(at: selectedBackupURL)
        }
        selectedBackupURL = nil
    }

    #if !os(tvOS)
    private func prepareSelectedBackupForRestore(from sourceURL: URL) throws -> URL {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let values = try? sourceURL.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            throw CocoaError(.fileReadCorruptFile)
        }

        let data = try coordinatedDataContents(of: sourceURL)
        guard !data.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let importDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("EclipseBackupImports", isDirectory: true)
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)

        let localURL = importDirectory
            .appendingPathComponent("selected-backup-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try data.write(to: localURL, options: .atomic)
        Logger.shared.log("Prepared selected backup for restore: \(sourceURL.lastPathComponent)", type: "Info")
        return localURL
    }

    private func coordinatedDataContents(of sourceURL: URL) throws -> Data {
        var coordinationError: NSError?
        var readError: Error?
        var data: Data?

        NSFileCoordinator().coordinate(readingItemAt: sourceURL, options: [], error: &coordinationError) { coordinatedURL in
            do {
                data = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let readError = readError {
            throw readError
        }
        if let coordinationError = coordinationError {
            throw coordinationError
        }
        guard let data = data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }
    #endif
}

#Preview {
    if #available(iOS 16.0, *) {
        NavigationStack {
            BackupManagementView()
        }
    } else {
        NavigationView {
            BackupManagementView()
        }
    }
}
