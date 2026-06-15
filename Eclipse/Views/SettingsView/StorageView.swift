//
//  StorageView.swift
//  Eclipse
//
//  Created by Francesco on 04/11/25.
//

import SwiftUI

private struct StorageBreakdownItem: Identifiable {
    let id = UUID()
    let title: String
    let sizeBytes: Int64
}

struct StorageView: View {
    @State private var cacheSizeBytes: Int64 = 0
    @State private var storageBreakdown: [StorageBreakdownItem] = []
    @State private var isLoading: Bool = true
    @State private var isClearing: Bool = false
    @State private var showConfirmClear: Bool = false
    @State private var errorMessage: String?
    
    @AppStorage("autoClearCacheEnabled") private var autoClearCacheEnabled = false
    @AppStorage("autoClearCacheThresholdMB") private var autoClearCacheThresholdMB: Double = 500
    
    private let cacheThresholdOptions: [Double] = [100, 250, 500, 1000, 2000, 5000]
    
    var body: some View {
        List {
            Section(header: Text("APP CACHE"), footer: Text("Cache includes images and other temporary files that can be removed.")) {
                HStack {
                    Text("Cache Size")
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(formattedCacheSize)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(role: .destructive) {
                    showConfirmClear = true
                } label: {
                    if isClearing {
                        HStack {
                            ProgressView()
                            Text("Clearing Cache...")
                        }
                    } else {
                        Text("Clear Cache")
                    }
                }
                .disabled(isClearing || (isLoading && cacheSizeBytes == 0))
            }
            .background(EclipseScrollTracker())

            if ExperimentalFeatureState.isEnabledAtLaunch || ExperimentalFeatureState.isMPVAdvancedPlaybackAvailable {
                Section(
                    header: Text("STORAGE BREAKDOWN"),
                    footer: Text(ExperimentalFeatureState.isMPVAdvancedPlaybackAvailable ? "MPV warmup files are temporary cache data and are excluded from downloads, backup, and iCloud." : "MPV warmup cache actions require MPV as the default in-app player with the Metal renderer.")
                ) {
                    ForEach(storageBreakdown) { item in
                        HStack {
                            Text(item.title)
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        ExperimentalMPVPreloadManager.shared.clearCache()
                        refreshCacheSize()
                    } label: {
                        Text("Clear MPV Warmup Cache")
                    }
                    .disabled(!ExperimentalFeatureState.isMPVAdvancedPlaybackAvailable || isLoading || isClearing)
                }
            }
            
            Section(header: Text("AUTO-CLEAR CACHE"), footer: Text("Automatically clear cache when it exceeds the specified size.")) {
                Toggle("Enable Auto-Clear", isOn: $autoClearCacheEnabled)
                
                if autoClearCacheEnabled {
                    HStack {
                        Text("Threshold")
                        Spacer()
                        Picker("", selection: $autoClearCacheThresholdMB) {
                            ForEach(cacheThresholdOptions, id: \.self) { value in
                                Text(formatThreshold(value)).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    Text("Cache will be cleared when size exceeds \(formatThreshold(autoClearCacheThresholdMB))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let errorMessage {
                Section(header: Text("ERROR")) {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Storage")
        .eclipseSettingsStyle()
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: refreshCacheSize) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading || isClearing)
                .help("Recalculate cache size")
            }
        }
        .onAppear {
            refreshCacheSize()
        }
        .onChange(of: autoClearCacheEnabled) { enabled in
            if enabled {
                Logger.shared.log("Auto-clear cache enabled with threshold: \(formatThreshold(autoClearCacheThresholdMB))", type: "Storage")
            }
        }
        .alert("Clear Cache?", isPresented: $showConfirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearCache() }
        } message: {
            Text("This will remove cached files. You may need to re-download some content later.")
        }
    }
    
    private var formattedCacheSize: String {
        ByteCountFormatter.string(fromByteCount: cacheSizeBytes, countStyle: .file)
    }
    
    private func formatThreshold(_ mb: Double) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", mb / 1000)
        }
        return String(format: "%.0f MB", mb)
    }
    
    private func refreshCacheSize() {
        errorMessage = nil
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let size = calculateDirectorySize(at: cachesDirectory())
            let breakdown = calculateStorageBreakdown()
            DispatchQueue.main.async {
                self.cacheSizeBytes = size
                self.storageBreakdown = breakdown
                self.isLoading = false
                
                // Check if auto-clear should be triggered
                if self.autoClearCacheEnabled {
                    let thresholdBytes = Int64(self.autoClearCacheThresholdMB * 1_000_000)
                    if size > thresholdBytes {
                        Logger.shared.log("Cache size (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))) exceeds threshold (\(self.formatThreshold(self.autoClearCacheThresholdMB))). Auto-clearing...", type: "Storage")
                        self.autoClearCache()
                    }
                }
            }
        }
    }
    
    private func clearCache() {
        errorMessage = nil
        isClearing = true
        performCacheClear { size in
            self.cacheSizeBytes = size
            self.isClearing = false
            self.isLoading = false
        }
    }
    
    private func autoClearCache() {
        performCacheClear { size in
            self.cacheSizeBytes = size
            Logger.shared.log("Auto-clear completed. New cache size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))", type: "Storage")
        }
    }
    
    private func performCacheClear(completion: @escaping (Int64) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let dir = cachesDirectory()
                let fileManager = FileManager.default
                let items = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
                for url in items {
                    try? fileManager.removeItem(at: url)
                }
                
                URLCache.shared.removeAllCachedResponses()
                
                let size = calculateDirectorySize(at: dir)
                let breakdown = calculateStorageBreakdown()
                DispatchQueue.main.async {
                    self.storageBreakdown = breakdown
                    completion(size)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isClearing = false
                    self.isLoading = false
                }
            }
        }
    }

    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        var total: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                if resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize {
                    total += Int64(fileSize)
                }
            } catch {
                continue
            }
        }
        return total
    }
    
    private func cachesDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func calculateStorageBreakdown() -> [StorageBreakdownItem] {
        let documents = documentsDirectory()
        let caches = cachesDirectory()
        let downloads = DownloadManager.shared.downloadsDirectory
        let mpvPreload = ExperimentalMPVPreloadManager.shared.cacheDirectory

        return [
            StorageBreakdownItem(title: "Document Directory", sizeBytes: calculateDirectorySize(at: documents)),
            StorageBreakdownItem(title: "Image Cache", sizeBytes: calculateNamedCacheSize(in: caches, matching: ["kingfisher", "imagecache", "image-cache"])),
            StorageBreakdownItem(title: "MPV Warmup Cache", sizeBytes: ExperimentalMPVPreloadManager.shared.cacheSizeBytes),
            StorageBreakdownItem(title: "Downloads / Video Storage", sizeBytes: calculateDirectorySize(at: downloads)),
            StorageBreakdownItem(title: "Subtitle Cache", sizeBytes: calculateFileSize(in: [documents, caches, downloads], extensions: ["srt", "vtt", "ass", "ssa"])),
            StorageBreakdownItem(title: "Service / Plugin / Source Cache", sizeBytes: calculateNamedCacheSize(in: caches, matching: ["service", "plugin", "source", "stremio", "nuvio"])),
            StorageBreakdownItem(title: "Reader Cache", sizeBytes: calculateNamedCacheSize(in: caches, matching: ["kanzen", "aidoku", "reader", "manga"]))
        ].map { item in
            if item.title == "Document Directory" {
                let adjusted = max(0, item.sizeBytes - calculateDirectorySize(at: downloads))
                return StorageBreakdownItem(title: item.title, sizeBytes: adjusted)
            }
            if item.title == "Image Cache", item.sizeBytes == 0 {
                let adjusted = max(0, calculateDirectorySize(at: caches) - calculateDirectorySize(at: mpvPreload))
                return StorageBreakdownItem(title: item.title, sizeBytes: adjusted)
            }
            return item
        }
    }

    private func calculateNamedCacheSize(in directory: URL, matching tokens: [String]) -> Int64 {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return 0
        }

        return items.reduce(Int64(0)) { total, url in
            let name = url.lastPathComponent.lowercased()
            guard tokens.contains(where: { name.contains($0) }) else { return total }
            return total + calculateDirectorySize(at: url)
        }
    }

    private func calculateFileSize(in directories: [URL], extensions: Set<String>) -> Int64 {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        var total: Int64 = 0

        for directory in directories {
            guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                guard extensions.contains(fileURL.pathExtension.lowercased()),
                      let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let fileSize = values.fileSize else {
                    continue
                }
                total += Int64(fileSize)
            }
        }

        return total
    }
}

#Preview {
    StorageView()
}
