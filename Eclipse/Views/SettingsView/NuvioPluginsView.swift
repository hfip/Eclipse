//
//  NuvioPluginsView.swift
//  Eclipse
//

import SwiftUI

struct NuvioPluginsView: View {
    @StateObject private var manager = NuvioPluginManager.shared
    @StateObject private var accentColorManager = AccentColorManager.shared
    @State private var repositoryURL = ""
    @State private var isAddingRepository = false
    @State private var isRefreshingAll = false
    @State private var testingProviderID: String?
    @State private var alert: PluginAlert?

    private var accent: Color { accentColorManager.currentAccentColor }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                overviewSection
                addRepositorySection
                repositoriesSection
                providersSection
            }
            .padding(.top, 16)
            .padding(.bottom, 32)
            .background(EclipseScrollTracker())
        }
        .navigationTitle("Plugins")
        .background(SettingsGradientBackground().ignoresSafeArea())
        .eclipseDarkToolbar()
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
        VStack(spacing: 8) {
            GlassSection {
                VStack(spacing: 0) {
                    GlassDetailRow(icon: "puzzlepiece.extension.fill", iconColor: .mint, title: "Plugins Enabled") {
                        Toggle("", isOn: Binding(
                            get: { manager.pluginsEnabled },
                            set: { manager.setPluginsEnabled($0) }
                        ))
                        .labelsHidden()
                        .tint(accent)
                    }

                    GlassDivider()

                    GlassDetailRow(icon: "square.stack.3d.up.fill", iconColor: .purple, title: "Group Streams by Repository") {
                        Toggle("", isOn: Binding(
                            get: { manager.groupStreamsByRepository },
                            set: { manager.setGroupStreamsByRepository($0) }
                        ))
                        .labelsHidden()
                        .tint(accent)
                    }

                    GlassDivider()

                    GlassDetailRow(icon: "shippingbox.fill", iconColor: .orange, title: "Repositories") {
                        Text("\(manager.repositories.count)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }

                    GlassDivider()

                    GlassDetailRow(icon: "puzzlepiece.extension", iconColor: .cyan, title: "Providers") {
                        Text("\(manager.scrapers.count)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            GlassSectionFooter("Enabled plugin providers appear in manual stream results and Services Auto Mode.")
        }
    }

    private var addRepositorySection: some View {
        GlassSection(header: "Add Repository") {
            VStack(spacing: 0) {
                TextField("Repository URL", text: $repositoryURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .tint(accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                GlassDivider(leadingInset: 16)

                Button {
                    addRepository()
                } label: {
                    GlassDetailRow(icon: "plus.circle.fill", iconColor: .green, title: "Install Repository") {
                        if isAddingRepository {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white.opacity(0.6))
                        } else {
                            EmptyView()
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAddingRepository)
            }
        }
    }

    @ViewBuilder
    private var repositoriesSection: some View {
        GlassSection(header: "Repositories") {
            if manager.repositories.isEmpty {
                emptyText("No plugin repositories installed")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(manager.repositories.enumerated()), id: \.element.id) { index, repository in
                        repositoryRow(repository)
                        if index < manager.repositories.count - 1 {
                            GlassDivider(leadingInset: 16)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repository: NuvioPluginRepositoryItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(repository.hostLabel)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    if let version = repository.version, !version.isEmpty {
                        Text("Version \(version)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }
                    if let description = repository.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(2)
                    }
                }

                Spacer()

                if repository.isRefreshing {
                    ProgressView()
                        .tint(.white.opacity(0.6))
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
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Button {
                    refreshRepository(repository)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(accent)
                }
                .buttonStyle(.borderless)
                .disabled(repository.isRefreshing)

                Button(role: .destructive) {
                    manager.removeRepository(repository.manifestUrl)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var providersSection: some View {
        GlassSection(header: "Providers") {
            if manager.scrapers.isEmpty {
                emptyText("No plugin providers installed")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedScrapers.enumerated()), id: \.element.id) { index, scraper in
                        providerRow(scraper)
                        if index < sortedScrapers.count - 1 {
                            GlassDivider(leadingInset: 16)
                        }
                    }
                }
            }
        }
    }

    private func providerRow(_ scraper: NuvioPluginScraper) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scraper.name)
                        .font(.headline)
                        .foregroundColor(.white)
                    if !scraper.description.isEmpty {
                        Text(scraper.description)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(2)
                    }
                    Text(providerSubtitle(for: scraper))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { scraper.enabled },
                    set: { manager.toggleScraper(scraper.id, enabled: $0) }
                ))
                .labelsHidden()
                .tint(accent)
                .disabled(!scraper.manifestEnabled)
            }

            HStack(spacing: 8) {
                ForEach(scraper.supportedTypes.map(NuvioPluginSupport.normalizeType).removingDuplicates(), id: \.self) { type in
                    Text(type.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
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
                            .tint(.white.opacity(0.6))
                    } else {
                        Image(systemName: "play.circle")
                            .foregroundColor(accent)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(testingProviderID != nil || !scraper.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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
