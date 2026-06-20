//
//  AidokuSourcesSettingsView.swift
//  Kanzen
//

#if !os(tvOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AidokuSourcesSettingsView: View {
    @EnvironmentObject private var moduleManager: ModuleManager
    @StateObject private var sourceManager = AidokuSourceManager.shared
    @State private var sourceListURL = ""
    @State private var isImportingPackage = false
    @State private var isBusy = false
    @State private var alertMessage: String?
    @State private var showAvailableSources = true

    private var visibleAvailableSources: [AidokuSourceListEntry] {
        sourceManager.availableSources
            .filter { sourceManager.showMatureSources || !$0.isMature }
            .sorted {
                if $0.listName != $1.listName { return $0.listName < $1.listName }
                return $0.info.name.localizedCaseInsensitiveCompare($1.info.name) == .orderedAscending
            }
    }

    private var installedSources: [AidokuInstalledSource] {
        sourceManager.installedSources
            .filter { sourceManager.showMatureSources || !$0.isMature }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    var body: some View {
        List {
            Section(header: Text("Source Lists"), footer: Text("No default Aidoku list is bundled. Add source lists you trust.")) {
                HStack {
                    TextField("https://example.com/list.json", text: $sourceListURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Add") {
                        addSourceList()
                    }
                    .disabled(sourceListURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                }

                if sourceManager.sourceLists.isEmpty {
                    Text("No source lists added")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(sourceManager.sourceLists) { list in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(list.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(list.url)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            if let error = list.lastError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            } else {
                                Text("\(list.sourceCount) sources")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                sourceManager.removeSourceList(list)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }

                Button {
                    refreshLists()
                } label: {
                    Label(sourceManager.isRefreshing ? "Refreshing..." : "Refresh Lists", systemImage: "arrow.clockwise")
                }
                .disabled(sourceManager.isRefreshing || isBusy)
            }
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())

            Section(header: Text("Installed Sources"), footer: Text("Disabled or hidden mature sources do not appear on Discover or Search.")) {
                Toggle("Show Mature Sources", isOn: $sourceManager.showMatureSources)
                Toggle("Auto-Update Sources", isOn: $sourceManager.autoUpdateSources)

                Button {
                    Task {
                        await sourceManager.updateAllInstalledSources()
                    }
                } label: {
                    Label(sourceManager.isUpdatingSources ? "Updating Sources..." : "Update All Sources", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(sourceManager.isUpdatingSources || installedSources.isEmpty)

                if installedSources.isEmpty {
                    Text("No Aidoku sources installed")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(installedSources) { source in
                        installedSourceRow(source)
                    }
                    .onMove { offsets, destination in
                        sourceManager.move(from: offsets, to: destination)
                    }
                }

                Button {
                    isImportingPackage = true
                } label: {
                    Label("Import .aix Package", systemImage: "square.and.arrow.down")
                }
            }
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())

            Section(header: Text("Available Sources")) {
                DisclosureGroup(isExpanded: $showAvailableSources) {
                    if visibleAvailableSources.isEmpty {
                        Text(sourceManager.sourceLists.isEmpty ? "Add a source list to see installable sources." : "No installable sources found.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(visibleAvailableSources) { entry in
                            availableSourceRow(entry)
                        }
                    }
                } label: {
                    HStack {
                        Text("Installable Sources")
                        Spacer()
                        Text("\(visibleAvailableSources.count)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .eclipseExperimentalSettingsRows()
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Aidoku Sources")
        .navigationBarTitleDisplayMode(.inline)
        .eclipseSettingsStyle()
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $isImportingPackage) {
            AidokuPackageDocumentPicker { url in
                importPackage(url)
            }
        }
        .alert("Aidoku Sources", isPresented: Binding(
            get: { alertMessage != nil },
            set: { _ in alertMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func installedSourceRow(_ source: AidokuInstalledSource) -> some View {
        HStack(spacing: 12) {
            SourceIconView(urlString: source.iconURLString, fallbackSystemName: "shippingbox")

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(source.isEnabled ? .primary : .secondary)
                Text("\(source.languages.joined(separator: ", ")) - v\(source.version) - \(source.contentRating.kanzenTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(statusText(for: source))
                    .font(.caption2)
                    .foregroundColor(source.lastError == nil ? .secondary : .red)
                if let error = source.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            Menu {
                Button(source.isEnabled ? "Disable" : "Enable") {
                    sourceManager.toggle(source)
                }

                Button("Update") {
                    Task { await sourceManager.updateInstalledSource(source) }
                }
                .disabled(source.packageURL == nil)

                Button(role: .destructive) {
                    sourceManager.remove(source)
                } label: {
                    Text("Delete")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private func statusText(for source: AidokuInstalledSource) -> String {
        if source.lastError != nil {
            return source.isEnabled ? "Enabled - needs attention" : "Disabled - needs attention"
        }
        if source.packageURL == nil {
            return source.isEnabled ? "Enabled - local package" : "Disabled - local package"
        }
        if sourceManager.isUpdatingSources {
            return "Checking for updates"
        }
        return source.isEnabled ? "Enabled - current" : "Disabled - current"
    }

    private func availableSourceRow(_ entry: AidokuSourceListEntry) -> some View {
        let installed = sourceManager.installedSources.first { $0.id == entry.id }

        return HStack(spacing: 12) {
            SourceIconView(urlString: entry.iconURLString, fallbackSystemName: "shippingbox")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.info.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(entry.info.resolvedLanguages.joined(separator: ", ")) - v\(entry.info.version) - \(entry.info.resolvedContentRating.kanzenTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(entry.listName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(installed == nil ? "Install" : "Update") {
                install(entry)
            }
            .disabled(isBusy)
        }
    }

    private func addSourceList() {
        let value = sourceListURL
        isBusy = true
        Task {
            do {
                try await sourceManager.addSourceList(value)
                await MainActor.run {
                    sourceListURL = ""
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    private func refreshLists() {
        isBusy = true
        Task {
            await sourceManager.refreshSourceLists()
            await MainActor.run {
                isBusy = false
            }
        }
    }

    private func install(_ entry: AidokuSourceListEntry) {
        isBusy = true
        Task {
            do {
                try await sourceManager.install(entry)
                await MainActor.run { isBusy = false }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    private func importPackage(_ url: URL) {
        isBusy = true
        Task {
            do {
                _ = try await sourceManager.importSourcePackage(from: url)
                await MainActor.run { isBusy = false }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }
}

private struct SourceIconView: View {
    let urlString: String
    let fallbackSystemName: String

    var body: some View {
        AsyncImage(url: URL(string: urlString)) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            Image(systemName: fallbackSystemName)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct AidokuPackageDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let aixType = UTType(filenameExtension: "aix") ?? .data
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [aixType, .zip, .data], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}
#endif
