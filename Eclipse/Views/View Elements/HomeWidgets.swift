//
//  HomeWidgets.swift
//  Eclipse
//
//  Forward-style discover widgets for the home page.
//

import SwiftUI
import Kingfisher

// MARK: - Network Section Widget

struct NetworkSectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let networks = WidgetNetwork.curated
    private var metrics: ExperimentalMediaDesignMetrics { .current }
    
    var body: some View {
        let availableNetworks = networks.filter { network in
            let items = widgetData["network_\(network.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableNetworks.isEmpty {
            VStack(alignment: .leading, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 18 : 16) {
                Text("Network")
                    .font(ExperimentalFeatureState.isEnabledAtLaunch ? .system(size: isIPad ? 34 : 29, weight: .heavy) : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, isIPad ? 24 : 16)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 22 : 16) {
                        ForEach(availableNetworks) { network in
                            let items = widgetData["network_\(network.id)"] ?? []
                            NavigationLink(destination: DiscoverDetailView(
                                title: network.name,
                                initialItems: items,
                                loadMore: { page in
                                    (try? await tmdbService.discoverByNetwork(networkId: network.id, page: page)) ?? []
                                }
                            )) {
                                networkCard(network: network, items: items)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, isIPad ? 24 : 16)
                }
                .modifier(ScrollClipModifier())
            }
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? metrics.sectionSpacing : 24)
        }
    }
    
    @ViewBuilder
    private func networkCard(network: WidgetNetwork, items: [TMDBSearchResult]) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let posterWidth: CGFloat = isExperimental ? (isIPad ? 124 : 96) : (isIPad ? 100 : 80)
        let posterHeight: CGFloat = isExperimental ? (isIPad ? 178 : 142) : (isIPad ? 150 : 120)
        let cardWidth: CGFloat = isExperimental ? (isIPad ? 430 : 330) : (isIPad ? 340 : 260)
        let cardHeight: CGFloat = isExperimental ? (isIPad ? 220 : 178) : (isIPad ? 190 : 160)
        let radius = isExperimental ? metrics.cardRadius : 16

        ZStack(alignment: .leading) {
            HStack(spacing: -20) {
                Spacer()
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    KFImage(URL(string: item.fullPosterURL ?? ""))
                        .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: posterWidth, height: posterHeight)))
                        .placeholder { Color.gray.opacity(0.3) }
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(width: posterWidth, height: posterHeight)
                        .clipShape(RoundedRectangle(cornerRadius: isExperimental ? 13 : 10, style: .continuous))
                        .rotationEffect(.degrees(Double(index - 1) * 5))
                        .offset(y: index == 1 ? -5 : 5)
                        .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 5)
                }
            }
            .padding(.trailing, isExperimental ? 20 : 12)
            .padding(.vertical, 12)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(network.name)
                    .font(isExperimental ? .system(size: isIPad ? 34 : 28, weight: .heavy) : .title2)
                    .fontWeight(.heavy)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            }
            .padding(.leading, isExperimental ? 24 : 16)
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(
            LinearGradient(
                colors: isExperimental
                    ? [Color.black.opacity(0.58), Color(red: 0.12, green: 0.10, blue: 0.15).opacity(metrics.glassOpacity)]
                    : [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(isExperimental ? 0.12 : 0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isExperimental ? 0.28 : 0), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Genre/Category Section Widget

struct GenreSectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let genres = WidgetGenre.curated
    private var metrics: ExperimentalMediaDesignMetrics { .current }
    private var columns: [GridItem] {
        if isIPad {
            return [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }
    
    var body: some View {
        let availableGenres = genres.filter { genre in
            let items = widgetData["genre_\(genre.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableGenres.isEmpty {
            VStack(alignment: .leading, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 18 : 16) {
                Text("Category")
                    .font(ExperimentalFeatureState.isEnabledAtLaunch ? .system(size: isIPad ? 34 : 29, weight: .heavy) : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, isIPad ? 24 : 16)
                
                LazyVGrid(columns: columns, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 16 : 12) {
                    ForEach(Array(availableGenres.prefix(6))) { genre in
                        let items = widgetData["genre_\(genre.id)"] ?? []
                        NavigationLink(destination: DiscoverDetailView(
                            title: genre.name,
                            initialItems: items,
                            loadMore: { page in
                                (try? await tmdbService.discoverByGenre(genreId: genre.id, page: page)) ?? []
                            }
                        )) {
                            genreCard(genre: genre, items: items)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, isIPad ? 24 : 16)
            }
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? metrics.sectionSpacing : 24)
        }
    }
    
    @ViewBuilder
    private func genreCard(genre: WidgetGenre, items: [TMDBSearchResult]) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let posterWidth = CGFloat(isExperimental ? 72 : 60) * iPadScale
        let posterHeight = CGFloat(isExperimental ? 92 : 80) * iPadScale
        let radius = isExperimental ? metrics.cardRadius : 14

        HStack(spacing: 0) {
            if let posterURL = items.first?.fullPosterURL {
                KFImage(URL(string: posterURL))
                    .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: posterWidth, height: posterHeight)))
                    .placeholder { Color.gray.opacity(0.3) }
                    .resizable()
                    .aspectRatio(2/3, contentMode: .fill)
                    .frame(width: posterWidth, height: posterHeight)
                    .clipShape(RoundedRectangle(cornerRadius: isExperimental ? 12 : 8, style: .continuous))
                    .padding(.leading, isExperimental ? 14 : 10)
                    .padding(.vertical, 10)
                    .shadow(color: .black.opacity(isExperimental ? 0.20 : 0), radius: 8, x: 0, y: 4)
            }
            
            Spacer()
            
            Text(genre.name)
                .font(isExperimental ? .system(size: isIPad ? 22 : 19, weight: .bold) : .subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.trailing, isExperimental ? 18 : 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CGFloat(isExperimental ? 100 : 80) * iPadScale)
        .background(
            LinearGradient(
                colors: isExperimental
                    ? [Color.black.opacity(0.54), Color(red: 0.15, green: 0.10, blue: 0.13).opacity(metrics.glassOpacity)]
                    : [Color.yellow.opacity(0.15), Color.orange.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(isExperimental ? 0.12 : 0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isExperimental ? 0.20 : 0), radius: 14, x: 0, y: 8)
    }
}

// MARK: - Company Section Widget

struct CompanySectionWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let tmdbService: TMDBService
    
    private let companies = WidgetCompany.curated
    private var metrics: ExperimentalMediaDesignMetrics { .current }
    private var columns: [GridItem] {
        if isIPad {
            return [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }
    
    var body: some View {
        let availableCompanies = companies.filter { company in
            let items = widgetData["company_\(company.id)"] ?? []
            return !items.isEmpty
        }
        
        if !availableCompanies.isEmpty {
            VStack(alignment: .leading, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 18 : 16) {
                Text("Company")
                    .font(ExperimentalFeatureState.isEnabledAtLaunch ? .system(size: isIPad ? 34 : 29, weight: .heavy) : .title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, isIPad ? 24 : 16)
                
                LazyVGrid(columns: columns, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 16 : 12) {
                    ForEach(Array(availableCompanies.prefix(4))) { company in
                        let items = widgetData["company_\(company.id)"] ?? []
                        NavigationLink(destination: DiscoverDetailView(
                            title: company.name,
                            initialItems: items,
                            loadMore: { page in
                                (try? await tmdbService.discoverByCompany(companyId: company.id, page: page)) ?? []
                            }
                        )) {
                            companyCard(company: company, items: items)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, isIPad ? 24 : 16)
            }
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? metrics.sectionSpacing : 24)
        }
    }
    
    @ViewBuilder
    private func companyCard(company: WidgetCompany, items: [TMDBSearchResult]) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let backdropWidth: CGFloat = isIPad ? 360 : 260
        let backdropHeight: CGFloat = isExperimental ? (isIPad ? 138 : 116) : 100
        let radius = isExperimental ? metrics.cardRadius : 14

        ZStack {
            if let backdropURL = items.first?.fullBackdropURL {
                KFImage(URL(string: backdropURL))
                    .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: backdropWidth, height: backdropHeight)))
                    .placeholder { Color.gray.opacity(0.15) }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: backdropHeight)
                    .clipped()
                    .overlay(Color.black.opacity(isExperimental ? 0.38 : 0.55))
            } else {
                Color.black.opacity(isExperimental ? 0.52 : 0.06)
            }
            
            Text(company.name)
                .font(isExperimental ? .system(size: isIPad ? 28 : 22, weight: .heavy) : (isIPad ? .title3 : .headline))
                .fontWeight(.heavy)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: backdropHeight * iPadScale)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(isExperimental ? 0.12 : 0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isExperimental ? 0.22 : 0), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Ranked List Widget

struct RankedListWidget: View {
    let catalogId: String
    let title: String
    let items: [TMDBSearchResult]
    let tmdbService: TMDBService
    private var metrics: ExperimentalMediaDesignMetrics { .current }
    
    var body: some View {
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 22 : 16) {
                    NavigationLink(destination: DiscoverDetailView(
                        title: title,
                        initialItems: items
                    )) {
                        rankedCard(title: title, items: items)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, isIPad ? 24 : 16)
            }
            .modifier(ScrollClipModifier())
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? metrics.sectionSpacing : 24)
        }
    }
    
    @ViewBuilder
    private func rankedCard(title: String, items: [TMDBSearchResult]) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let posterWidth: CGFloat = isExperimental ? (isIPad ? 132 : 102) : (isIPad ? 112 : 86)
        let posterHeight: CGFloat = isExperimental ? 164 : 140
        let radius = isExperimental ? metrics.cardRadius : 16

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { _, item in
                    KFImage(URL(string: item.fullPosterURL ?? ""))
                        .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: posterWidth, height: posterHeight)))
                        .placeholder { Color.gray.opacity(0.3) }
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: posterHeight)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isExperimental ? 16 : 10, style: .continuous))
            .padding(.horizontal, isExperimental ? 14 : 12)
            .padding(.top, isExperimental ? 14 : 12)
            
            HStack(spacing: 6) {
                Image(systemName: "laurel.leading")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.7))
                
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Image(systemName: "laurel.trailing")
                    .font(.caption)
                    .foregroundColor(.yellow.opacity(0.7))
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.prefix(3).enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.subheadline)
                            .fontWeight(.heavy)
                            .foregroundColor(.yellow.opacity(0.8))
                            .frame(width: 20)
                        
                        Text(item.displayTitle)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: isExperimental ? (isIPad ? 420 : 330) : (isIPad ? 360 : 280))
        .background(
            LinearGradient(
                colors: isExperimental
                    ? [Color.black.opacity(0.56), Color(red: 0.13, green: 0.10, blue: 0.16).opacity(metrics.glassOpacity)]
                    : [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(isExperimental ? 0.12 : 0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isExperimental ? 0.28 : 0), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Featured Spotlight Widget

struct FeaturedSpotlightWidget: View {
    let widgetData: [String: [TMDBSearchResult]]
    let genreName: String
    let tmdbService: TMDBService
    private var metrics: ExperimentalMediaDesignMetrics { .current }
    
    var body: some View {
        let items = widgetData["featured"] ?? []
        
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 18 : 16) {
                if let spotlight = items.first {
                    NavigationLink(destination: DiscoverDetailView(
                        title: "Popular \u{00B7} \(genreName)",
                        initialItems: items,
                        heroItem: spotlight,
                        loadMore: { page in
                            guard let genre = WidgetGenre.curated.first(where: { $0.name == genreName }) else { return [] }
                            return (try? await tmdbService.discoverByGenre(genreId: genre.id, mediaType: "tv", page: page)) ?? []
                        }
                    )) {
                        spotlightBanner(spotlight: spotlight)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: ExperimentalFeatureState.isEnabledAtLaunch ? 24 : 14) {
                        ForEach(Array(items.dropFirst().prefix(8))) { item in
                            NavigationLink(destination: MediaDetailView(searchResult: item)) {
                                spotlightSmallCard(item: item)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, isIPad ? 24 : 16)
                }
                .modifier(ScrollClipModifier())
            }
            .padding(.top, ExperimentalFeatureState.isEnabledAtLaunch ? metrics.sectionSpacing : 24)
        }
    }
    
    @ViewBuilder
    private func spotlightBanner(spotlight: TMDBSearchResult) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let bannerHeight: CGFloat = isExperimental ? (isIPad ? 360 : 286) : (isIPad ? 280 : 200)
        let radius = isExperimental ? metrics.cardRadius + 4 : 16

        ZStack(alignment: isExperimental ? .center : .bottomLeading) {
            KFImage(URL(string: spotlight.fullBackdropURL ?? spotlight.fullPosterURL ?? ""))
                .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: UIScreen.main.bounds.width, height: bannerHeight)))
                .placeholder {
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: bannerHeight)
                .clipped()
            
            LinearGradient(
                colors: isExperimental
                    ? [.clear, .black.opacity(0.18), .black.opacity(0.68)]
                    : [.clear, .black.opacity(0.7), .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(alignment: isExperimental ? .center : .leading, spacing: isExperimental ? 8 : 6) {
                HStack(spacing: 6) {
                    Image(systemName: "laurel.leading")
                        .font(isExperimental ? .title2 : .caption)
                        .foregroundColor(.white.opacity(0.86))
                    
                    Text("Popular \u{00B7} \(genreName)")
                        .font(isExperimental ? .system(size: isIPad ? 34 : 28, weight: .heavy) : .headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    
                    Image(systemName: "laurel.trailing")
                        .font(isExperimental ? .title2 : .caption)
                        .foregroundColor(.white.opacity(0.86))
                }
                
                Text(spotlight.displayTitle)
                    .font(isExperimental ? .system(size: isIPad ? 20 : 17, weight: .medium) : .caption)
                    .foregroundColor(.white.opacity(isExperimental ? 0.78 : 0.7))
                    .lineLimit(1)
            }
            .padding(ExperimentalFeatureState.isEnabledAtLaunch ? 22 : 16)
            .frame(maxWidth: .infinity, alignment: isExperimental ? .center : .leading)
            .background(alignment: .bottom) {
                if isExperimental {
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.34)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bannerHeight * 0.42)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: bannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(isExperimental ? 0.14 : 0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isExperimental ? 0.30 : 0), radius: 22, x: 0, y: 12)
        .padding(.horizontal, isIPad ? 24 : 16)
    }
    
    @ViewBuilder
    private func spotlightSmallCard(item: TMDBSearchResult) -> some View {
        let isExperimental = ExperimentalFeatureState.isEnabledAtLaunch
        let posterWidth = CGFloat(isExperimental ? 198 : 120) * iPadScale
        let posterHeight = CGFloat(isExperimental ? 112 : 180) * iPadScale
        let posterShadowRadius: CGFloat = isIPad ? 3 : 6
        let radius = isExperimental ? metrics.cardRadius : 12

        VStack(alignment: .leading, spacing: 6) {
            KFImage(URL(string: isExperimental ? (item.fullBackdropURL ?? item.fullPosterURL ?? "") : (item.fullPosterURL ?? "")))
                .setProcessor(DownsamplingImageProcessor(size: homeImageDecodeSize(width: posterWidth, height: posterHeight)))
                .placeholder {
                    FallbackImageView(
                        isMovie: item.isMovie,
                        size: CGSize(width: posterWidth, height: posterHeight)
                    )
                }
                .resizable()
                .aspectRatio(isExperimental ? 16/9 : 2/3, contentMode: .fill)
                .frame(width: posterWidth, height: posterHeight)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: isExperimental ? 12 : posterShadowRadius, x: 0, y: isExperimental ? 7 : 3)
            
            Text(item.displayTitle)
                .font(.system(size: isExperimental ? 19 : 12, weight: .medium))
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: posterWidth, alignment: .leading)
            
            HStack(spacing: 4) {
                if !item.displayDate.isEmpty {
                    let date = item.displayDate
                    Text(isExperimental ? String(date.prefix(4)) : String(date.prefix(10)))
                        .font(.system(size: isExperimental ? 15 : 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .frame(width: posterWidth, alignment: .leading)
        }
    }
}
