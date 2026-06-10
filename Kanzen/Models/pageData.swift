//
//  pageData.swift
//  Kanzen
//
//  Created by Dawud Osman on 15/07/2025.
//

import SwiftUI
import Foundation
import Kingfisher

enum ChapterPosition {
    case prev
    case curr
    case next
}

enum ReaderPageContent: Equatable {
    case url(String, headers: [String: String] = [:])
    case imageData(Data)
    case text(String)
    case transition
}

struct PageData: Identifiable, Equatable {
    let id = UUID()
    let content: ReaderPageContent

    init(content: String) {
        if content == "CHAPTER_END" {
            self.content = .transition
        } else {
            self.content = .url(content)
        }
    }

    init(content: ReaderPageContent) {
        self.content = content
    }

    var urlString: String? {
        if case .url(let value, _) = content {
            return value
        }
        return nil
    }

    var headers: [String: String] {
        if case .url(_, let headers) = content {
            return headers
        }
        return [:]
    }

    var imageData: Data? {
        if case .imageData(let data) = content {
            return data
        }
        return nil
    }

    var textContent: String? {
        if case .text(let text) = content {
            return text
        }
        return nil
    }

    var isTransition: Bool {
        if case .transition = content {
            return true
        }
        return false
    }

    var cacheKey: String {
        switch content {
        case .url(let value, _):
            return value
        case .imageData:
            return "image-data-\(id.uuidString)"
        case .text(let text):
            return "text-\(text.hashValue)-\(id.uuidString)"
        case .transition:
            return "transition-\(id.uuidString)"
        }
    }

    var body: chapterView {
        chapterView(page: self, index: "0")
    }

    static func == (lhs: PageData, rhs: PageData) -> Bool {
        lhs.id == rhs.id
    }
}

struct Chapters: Identifiable {
    let id = UUID()
    let language: String
    var chapters: [Chapter]
}

struct Chapter: Identifiable {
    let id = UUID()
    let chapterNumber: String
    let idx: Int
    let chapterData: [ChapterData]?
}

enum ChapterIdentityNormalizer {
    static func key(for chapterNumber: String) -> String {
        let lowered = chapterNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let numberPattern = #"(\d+(?:\.\d+)?)"#

        if let match = firstMatch(
            in: lowered,
            pattern: #"\bvol(?:ume)?\.?\s*\#(numberPattern).*?\b(?:ch(?:apter)?|ep(?:isode)?|episode)\.?\s*\#(numberPattern)"#
        ),
           let volumeRange = Range(match.range(at: 1), in: lowered),
           let chapterRange = Range(match.range(at: 2), in: lowered) {
            let chapter = normalizedNumericString(String(lowered[chapterRange]))
            return "v\(normalizedNumericString(String(lowered[volumeRange]))):c\(chapter)"
        }

        if let match = firstMatch(
            in: lowered,
            pattern: #"\b(?:ch(?:apter)?|ep(?:isode)?|episode)\.?\s*\#(numberPattern)"#
        ),
           let chapterRange = Range(match.range(at: 1), in: lowered) {
            return "c\(normalizedNumericString(String(lowered[chapterRange])))"
        }

        if let match = firstMatch(in: lowered, pattern: #"^\s*\#(numberPattern)\b"#),
           let chapterRange = Range(match.range(at: 1), in: lowered) {
            return "c\(normalizedNumericString(String(lowered[chapterRange])))"
        }

        return lowered
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    static func deduplicatedNumbers(_ numbers: [String]) -> [String] {
        var seen = Set<String>()
        return numbers.filter { number in
            seen.insert(key(for: number)).inserted
        }
    }

    static func deduplicatedChapters(_ chapters: [Chapter], reindex: Bool = false) -> [Chapter] {
        var seen = Set<String>()
        let unique = chapters.filter { chapter in
            seen.insert(key(for: chapter.chapterNumber)).inserted
        }

        guard reindex else { return unique }
        return unique.enumerated().map { index, chapter in
            Chapter(
                chapterNumber: chapter.chapterNumber,
                idx: index,
                chapterData: chapter.chapterData
            )
        }
    }

    private static func normalizedNumericString(_ value: String) -> String {
        guard let number = Double(value) else { return value }
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(number))
        }
        return String(number)
    }

    private static func firstMatch(in value: String, pattern: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    }
}

struct ChapterData: Identifiable {
    let id = UUID()
    var scanlationGroup: String = ""
    var title: String = ""
    let params: Any?

    init?(dict: [String: Any]) {
        if let scanlationGroup = dict["scanlation_group"] as? String, let params = dict["id"] {
            self.scanlationGroup = scanlationGroup
            self.params = params
            self.title = dict["title"] as? String ?? ""
            return
        }

        if let href = dict["href"] as? String {
            self.params = href
            self.title = dict["title"] as? String ?? ""
            self.scanlationGroup = ""
            return
        }

        return nil
    }

    init(params: Any?, title: String = "", scanlationGroup: String = "") {
        self.params = params
        self.title = title
        self.scanlationGroup = scanlationGroup
    }
}

struct chapterView: View {
    let page: PageData
    let index: String

    var body: some View {
        if page.isTransition {
            TransitionPage(index: index)
        } else if let text = page.textContent {
            ReaderTextPageView(text: text)
        } else if let data = page.imageData, let image = UIImage(data: data) {
            ReaderDataImageView(image: image)
        } else if let urlString = page.urlString, let url = URL(string: urlString) {
            ReaderKFImage(url: url, page: page)
        } else {
            Text("Page failed to load")
                .foregroundColor(.white.opacity(0.75))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}

private struct ReaderTextPageView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
        }
        .background(Color.black)
    }
}

private struct ReaderDataImageView: View {
    let image: UIImage

    var body: some View {
        GeometryReader { proxy in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: max(proxy.size.width, 1))
                .frame(maxHeight: .infinity)
                .background(Color.black)
        }
        .background(Color.black)
    }
}

private struct ReaderKFImage: View {
    let url: URL
    let page: PageData

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            if let modifier = page.requestModifier {
                baseImage
                    .requestModifier(modifier)
                    .readerPageImageStyle(width: width)
            } else {
                baseImage
                    .readerPageImageStyle(width: width)
            }
        }
        .background(Color.black)
    }

    private var baseImage: KFImage {
        KFImage(url)
            .placeholder {
                CircularLoader()
            }
            .resizable()
    }
}

extension PageData {
    var requestModifier: AnyModifier? {
        guard !headers.isEmpty else { return nil }
        return AnyModifier { request in
            var request = request
            for (field, value) in headers {
                request.setValue(value, forHTTPHeaderField: field)
            }
            return request
        }
    }
}

enum ReaderPageImageOptions {
    static func options(
        for page: PageData,
        targetSize: CGSize? = nil,
        scaleFactor: CGFloat? = nil
    ) -> KingfisherOptionsInfo {
        options(headers: page.headers, targetSize: targetSize, scaleFactor: scaleFactor)
    }

    static func makePrefetchers(
        for pages: [PageData],
        targetSize: CGSize? = nil,
        scaleFactor: CGFloat? = nil
    ) -> [ImagePrefetcher] {
        var seen = Set<String>()
        var groups: [String: (headers: [String: String], urls: [URL])] = [:]

        for page in pages {
            guard let value = page.urlString,
                  let url = URL(string: value) else { continue }

            let groupKey = headerKey(page.headers)
            let seenKey = "\(groupKey)|\(value)"
            guard seen.insert(seenKey).inserted else { continue }

            var group = groups[groupKey] ?? (headers: page.headers, urls: [])
            group.urls.append(url)
            groups[groupKey] = group
        }

        return groups.values.map { group in
            ImagePrefetcher(
                urls: group.urls,
                options: options(headers: group.headers, targetSize: targetSize, scaleFactor: scaleFactor)
            )
        }
    }

    static func start(_ prefetchers: [ImagePrefetcher]) {
        prefetchers.forEach { $0.start() }
    }

    static func stop(_ prefetchers: inout [ImagePrefetcher]) {
        prefetchers.forEach { $0.stop() }
        prefetchers.removeAll()
    }

    private static func options(
        headers: [String: String],
        targetSize: CGSize?,
        scaleFactor: CGFloat?
    ) -> KingfisherOptionsInfo {
        var values: KingfisherOptionsInfo = [
            .cacheOriginalImage,
            .transition(.none),
            .backgroundDecode
        ]

        if let targetSize {
            values.append(.processor(DownsamplingImageProcessor(size: targetSize)))
        }

        if let scaleFactor {
            values.append(.scaleFactor(scaleFactor))
        }

        if !headers.isEmpty {
            values.append(.requestModifier(AnyModifier { request in
                var request = request
                for (field, value) in headers {
                    request.setValue(value, forHTTPHeaderField: field)
                }
                return request
            }))
        }

        return values
    }

    private static func headerKey(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\u{1F}")
    }
}

private extension KFImage {
    func readerPageImageStyle(width: CGFloat) -> some View {
        scaledToFit()
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background(Color.black)
    }
}

// MARK: - Zoomable Image View for Paged Reader

struct ZoomablePageView: UIViewRepresentable {
    let page: PageData

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .black

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            imageView.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])

        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView
        context.coordinator.load(page: page)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.load(page: page)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        private var currentPageKey: String?

        func load(page: PageData) {
            guard currentPageKey != page.cacheKey else { return }
            currentPageKey = page.cacheKey

            if let data = page.imageData {
                imageView?.image = UIImage(data: data)
                return
            }

            guard let urlString = page.urlString, let url = URL(string: urlString) else {
                imageView?.image = nil
                return
            }

            let scale = scrollView?.window?.screen.scale ?? UIScreen.main.scale
            let options = ReaderPageImageOptions.options(for: page, scaleFactor: scale)
            imageView?.kf.setImage(with: url, options: options)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > 1.0 {
                scrollView.setZoomScale(1.0, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let rect = CGRect(x: location.x - 50, y: location.y - 50, width: 100, height: 100)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

struct TransitionPage: View {
    var index: String

    var body: some View {
        Text("Chapter \(index) End")
            .frame(maxWidth: .infinity)
            .clipped()
    }
}
