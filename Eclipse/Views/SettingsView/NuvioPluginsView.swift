//
//  NuvioPluginsView.swift
//  Eclipse
//

import SwiftUI

struct NuvioPluginsView: View {
    @StateObject private var manager = NuvioPluginManager.shared
    @State private var repositoryURL = ""
    @State private var isAddingRepository = false
    @State private var isRefreshingAll = false
    @State private var testingProviderID: String?
    @State private var alert: PluginAlert?

    var body: some View {
        List {
            overviewSection
            addRepositorySection
            repositoriesSection
            providersSection
        }
        .navigationTitle("Plugins")
        .eclipseSettingsStyle()
        .toolbar {
#if !os(tvOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.repositories.isEmpty || isRefreshingAll)
            }
#endif
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            manager.load()
        }
    }

    private var overviewSection: some View {
        Section {
            Toggle("Plugins Enabled", isOn: Binding(
                get: { manager.pluginsEnabled },
                set: { manager.setPluginsEnabled($0) }
            ))

            Toggle("Group Streams by Repository", isOn: Binding(
                get: { manager.groupStreamsByRepository },
                set: { manager.setGroupStreamsByRepository($0) }
            ))

            HStack {
                Label("Repositories", systemImage: "shippingbox")
                Spacer()
                Text("\(manager.repositories.count)")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("Providers", systemImage: "puzzlepiece.extension")
                Spacer()
                Text("\(manager.scrapers.count)")
                    .foregroundColor(.secondary)
            }
        } footer: {
            Text("Enabled plugin providers appear in manual stream results and Services Auto Mode.")
        }
    }

    private var addRepositorySection: some View {
        Section {
            TextField("Repository URL", text: $repositoryURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                addRepository()
            } label: {
                HStack {
                    Label("Install Repository", systemImage: "plus.circle")
                    Spacer()
                    if isAddingRepository {
                        ProgressView()
                    }
                }
            }
            .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingRepository)
        } header: {
            Text("Add Repository")
        }
    }

    @ViewBuilder
    private var repositoriesSection: some View {
        Section {
            if manager.repositories.isEmpty {
                Text("No plugin repositories installed")
                    .foregroundColor(.secondary)
            } else {
                ForEach(manager.repositories) { repository in
                    repositoryRow(repository)
                }
            }
        } header: {
            Text("Repositories")
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repository: NuvioPluginRepositoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                    Text(repository.hostLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let version = repository.version, !version.isEmpty {
                        Text("Version \(version)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if repository.isRefreshing {
                    ProgressView()
                }
            }

            if let error = repository.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack {
                Label("\(repository.scraperCount) provider\(repository.scraperCount == 1 ? "" : "s")", systemImage: "puzzlepiece.extension")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    refreshRepository(repository)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(repository.isRefreshing)

                Button(role: .destructive) {
                    manager.removeRepository(repository.manifestUrl)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var providersSection: some View {
        Section {
            if manager.scrapers.isEmpty {
                Text("No plugin providers installed")
                    .foregroundColor(.secondary)
            } else {
                ForEach(sortedScrapers) { scraper in
                    providerRow(scraper)
                }
            }
        } header: {
            Text("Providers")
        }
    }

    private func providerRow(_ scraper: NuvioPluginScraper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scraper.name)
                        .font(.headline)
                    if !scraper.description.isEmpty {
                        Text(scraper.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Text(providerSubtitle(for: scraper))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { scraper.enabled },
                    set: { manager.toggleScraper(scraper.id, enabled: $0) }
                ))
                .labelsHidden()
                .disabled(!scraper.manifestEnabled)
            }

            HStack(spacing: 8) {
                ForEach(scraper.supportedTypes.map(NuvioPluginSupport.normalizeType).removingDuplicates(), id: \.self) { type in
                    Text(type.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.16))
                        .cornerRadius(5)
                }

                if !scraper.manifestEnabled {
                    Text("Disabled by repo")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
                        .cornerRadius(5)
                }

                Spacer()

                Button {
                    testProvider(scraper)
                } label: {
                    if testingProviderID == scraper.id {
                        ProgressView()
                    } else {
                        Image(systemName: "play.circle")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(testingProviderID != nil || !scraper.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var sortedScrapers: [NuvioPluginScraper] {
        manager.scrapers.sorted {
            if $0.repositoryUrl != $1.repositoryUrl {
                return $0.repositoryUrl.localizedCaseInsensitiveCompare($1.repositoryUrl) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func providerSubtitle(for scraper: NuvioPluginScraper) -> String {
        let repositoryName = manager.repositories.first(where: { $0.manifestUrl == scraper.repositoryUrl })?.name
        let version = scraper.version.trimmingCharacters(in: .whitespacesAndNewlines)
        return [repositoryName, version.isEmpty ? nil : "v\(version)"]
            .compactMap { $0 }
            .joined(separator: " - ")
    }

    private func addRepository() {
        let requested = repositoryURL
        isAddingRepository = true
        Task {
            do {
                try await manager.addRepository(rawURL: requested)
                await MainActor.run {
                    repositoryURL = ""
                    isAddingRepository = false
                }
            } catch {
                await MainActor.run {
                    isAddingRepository = false
                    alert = PluginAlert(title: "Plugin Error", message: error.localizedDescription)
                }
            }
        }
    }

    private func refreshRepository(_ repository: NuvioPluginRepositoryItem) {
        Task {
            await manager.refreshRepository(repository.manifestUrl)
        }
    }

    private func refreshAll() {
        isRefreshingAll = true
        Task {
            await manager.refreshAll()
            await MainActor.run {
                isRefreshingAll = false
            }
        }
    }

    private func testProvider(_ scraper: NuvioPluginScraper) {
        testingProviderID = scraper.id
        Task {
            do {
                let streams = try await manager.testScraper(scraper.id)
                await MainActor.run {
                    testingProviderID = nil
                    alert = PluginAlert(
                        title: "Provider Test",
                        message: streams.isEmpty ? "Provider ran, but returned no direct HTTP streams." : "Provider returned \(streams.count) direct HTTP stream\(streams.count == 1 ? "" : "s")."
                    )
                }
            } catch {
                await MainActor.run {
                    testingProviderID = nil
                    alert = PluginAlert(title: "Provider Test Failed", message: error.localizedDescription)
                }
            }
        }
    }
}

private struct PluginAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
