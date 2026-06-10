//
//  WebtoonView.swift
//  Kanzen
//
//  Created by Dawud Osman on 01/09/2025.
//

import SwiftUI
import UIKit
import QuartzCore
import ImageIO
import Nuke

struct WebtoonView: UIViewRepresentable {
    @ObservedObject var reader_manager: readerManager
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(reader_manager: reader_manager, onTap: onTap)
    }

    func makeUIView(context: Context) -> WebtoonCollectionView {
        let layout = WebtoonCollectionLayout()
        let collectionView = WebtoonCollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.isPagingEnabled = false
        collectionView.bounces = false
        collectionView.alwaysBounceVertical = false
        collectionView.scrollsToTop = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
        collectionView.delaysContentTouches = false
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        }
        collectionView.register(WebtoonImageCell.self, forCellWithReuseIdentifier: WebtoonImageCell.reuseIdentifier)
        collectionView.onLayout = { [weak coordinator = context.coordinator, weak collectionView] in
            guard let collectionView else { return }
            coordinator?.collectionViewDidLayout(collectionView)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        collectionView.addGestureRecognizer(tap)

        context.coordinator.collectionView = collectionView
        context.coordinator.startPerfMonitoring()
        return collectionView
    }

    func updateUIView(_ uiView: WebtoonCollectionView, context: Context) {
        context.coordinator.reader_manager = reader_manager
        context.coordinator.onTap = onTap
        context.coordinator.configure(uiView, manager: reader_manager)
    }

    static func dismantleUIView(_ uiView: WebtoonCollectionView, coordinator: Coordinator) {
        coordinator.stopPerfMonitoring()
        coordinator.cancelWork()
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        var reader_manager: readerManager
        var onTap: () -> Void
        weak var collectionView: WebtoonCollectionView?

        private var pages: [PageData] = []
        private var pageHeights: [String: CGFloat] = [:]
        private var imageSizes: [String: CGSize] = [:]
        private var chapterIdentity = ""
        private var lastKnownWidth: CGFloat = 0
        private var loadingPrevious = false
        private var loadingNext = false
        private var lastReportedPage = -1
        private var lastWarmAnchor = -1
        private var activeWarmKeys = Set<String>()
        private var warmedKeys = Set<String>()
        private var pendingLayoutWorkItem: DispatchWorkItem?
        private var pendingScrollToPage: Int?
        private var didInitialPosition = false
        private var displayLink: CADisplayLink?
        private var lastDisplayTimestamp: CFTimeInterval?
        private var lastHitchLogTime = Date.distantPast
        private var lastScrollLogTime = Date.distantPast
        private var chapterWarmTask: Task<Void, Never>?

        private static let defaultImageAspectRatio: CGFloat = 2.25

        init(reader_manager: readerManager, onTap: @escaping () -> Void) {
            self.reader_manager = reader_manager
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        func configure(_ collectionView: WebtoonCollectionView, manager: readerManager) {
            let identity = Self.identity(for: manager)
            let needsInitialBuild = pages.isEmpty && !manager.currChapter.isEmpty
            if needsInitialBuild || identity != chapterIdentity || pages.map(\.id) != manager.currChapter.map(\.id) {
                reset(collectionView, manager: manager)
            }

            if manager.changeIndex,
               manager.index >= 0,
               manager.index < pages.count {
                pendingScrollToPage = manager.index
                manager.changeIndex = false
                scrollToPendingPage(in: collectionView)
            } else if !didInitialPosition, !pages.isEmpty {
                pendingScrollToPage = min(max(manager.index, 0), pages.count - 1)
                scrollToPendingPage(in: collectionView)
            }
        }

        func collectionViewDidLayout(_ collectionView: WebtoonCollectionView) {
            let width = max(collectionView.bounds.width, 1)
            if abs(width - lastKnownWidth) >= 1 {
                lastKnownWidth = width
                updateAllPageHeights(in: collectionView, preserveCurrentPage: didInitialPosition)
            }
            scrollToPendingPage(in: collectionView)
        }

        private func reset(_ collectionView: WebtoonCollectionView, manager: readerManager) {
            cancelWork()
            pages = manager.currChapter
            chapterIdentity = Self.identity(for: manager)
            pageHeights.removeAll()
            imageSizes.removeAll()
            activeWarmKeys.removeAll()
            warmedKeys.removeAll()
            lastWarmAnchor = -1
            lastReportedPage = -1
            loadingPrevious = false
            loadingNext = false
            didInitialPosition = false
            lastDisplayTimestamp = nil
            pendingScrollToPage = min(max(manager.index, 0), max(pages.count - 1, 0))

            let width = max(collectionView.bounds.width, lastKnownWidth, UIScreen.main.bounds.width, 1)
            lastKnownWidth = width
            for page in pages {
                pageHeights[page.cacheKey] = height(for: page, width: width)
            }

            updateLayoutHeights(in: collectionView)
            collectionView.reloadData()
            collectionView.layoutIfNeeded()

            ReaderLogger.shared.log(
                "Webtoon virtualized reset chapter=\(manager.selectedChapter?.chapterNumber ?? "<none>") pages=\(pages.count)",
                type: "ReaderWebtoon"
            )

            DispatchQueue.main.async { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                collectionView.layoutIfNeeded()
                self.scrollToPendingPage(in: collectionView)
                self.prefetchWindow(around: max(0, self.reader_manager.index), in: collectionView, force: true)
                self.startChapterWarmup(in: collectionView, around: max(0, self.reader_manager.index))
            }
        }

        func cancelWork() {
            pendingLayoutWorkItem?.cancel()
            pendingLayoutWorkItem = nil
            chapterWarmTask?.cancel()
            chapterWarmTask = nil
            collectionView?.visibleCells.forEach { ($0 as? WebtoonImageCell)?.cancelLoad() }
        }

        func startPerfMonitoring() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(displayLinkTick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stopPerfMonitoring() {
            displayLink?.invalidate()
            displayLink = nil
            lastDisplayTimestamp = nil
        }

        @objc private func displayLinkTick(_ link: CADisplayLink) {
            guard let previous = lastDisplayTimestamp else {
                lastDisplayTimestamp = link.timestamp
                return
            }
            lastDisplayTimestamp = link.timestamp

            let deltaMs = (link.timestamp - previous) * 1000
            guard deltaMs >= 95 else { return }

            let now = Date()
            guard now.timeIntervalSince(lastHitchLogTime) >= 1.5 else { return }
            lastHitchLogTime = now

            let collectionView = collectionView
            let offset = Int(collectionView?.contentOffset.y ?? 0)
            let contentHeight = Int(collectionView?.contentSize.height ?? 0)
            let visible = collectionView?.indexPathsForVisibleItems.map(\.item).sorted() ?? []
            ReaderLogger.shared.log(
                "Webtoon frame hitch deltaMs=\(Int(deltaMs)) page=\(lastReportedPage + 1)/\(pages.count) offset=\(offset)/\(contentHeight) visible=\(visible) activeWarm=\(activeWarmKeys.count)",
                type: "ReaderPerf"
            )
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            pages.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WebtoonImageCell.reuseIdentifier,
                for: indexPath
            ) as? WebtoonImageCell,
                  indexPath.item < pages.count else {
                return UICollectionViewCell()
            }

            let page = pages[indexPath.item]
            let targetSize = targetImageSize(for: collectionView)
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale
            cell.configure(
                page: page,
                index: indexPath.item,
                targetSize: targetSize,
                scale: scale,
                onImageSize: { [weak self, weak collectionView] page, size, index in
                    guard let self, let collectionView else { return }
                    self.updateImageSize(page: page, size: size, index: index, collectionView: collectionView)
                }
            )
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            let indexes = indexPaths.map(\.item).filter { $0 >= 0 && $0 < pages.count }
            warmPages(indexes, collectionView: collectionView)
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            (cell as? WebtoonImageCell)?.releaseDisplayedImage()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? WebtoonCollectionView, !pages.isEmpty else { return }
            updateCurrentPage(in: collectionView)
            loadAdjacentChaptersIfNeeded(collectionView)
        }

        private func scrollToPendingPage(in collectionView: WebtoonCollectionView) {
            guard let index = pendingScrollToPage,
                  index >= 0,
                  index < pages.count else { return }
            collectionView.layoutIfNeeded()
            let indexPath = IndexPath(item: index, section: 0)
            guard collectionView.numberOfItems(inSection: 0) > index else { return }
            collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
            pendingScrollToPage = nil
            didInitialPosition = true
            updateCurrentPage(in: collectionView, force: true)
            prefetchWindow(around: index, in: collectionView, force: true)
        }

        private func updateAllPageHeights(in collectionView: WebtoonCollectionView, preserveCurrentPage: Bool) {
            let currentPage = preserveCurrentPage ? max(lastReportedPage, 0) : nil
            let width = max(collectionView.bounds.width, 1)
            for page in pages {
                pageHeights[page.cacheKey] = height(for: page, width: width)
            }
            updateLayoutHeights(in: collectionView)
            collectionView.layoutIfNeeded()
            if let currentPage, currentPage < pages.count {
                pendingScrollToPage = currentPage
                scrollToPendingPage(in: collectionView)
            }
        }

        private func updateImageSize(
            page: PageData,
            size: CGSize,
            index: Int,
            collectionView: UICollectionView
        ) {
            guard size.width > 0, size.height > 0, index < pages.count, pages[index].id == page.id else { return }
            if let existing = imageSizes[page.cacheKey],
               abs(existing.width - size.width) < 0.5,
               abs(existing.height - size.height) < 0.5 {
                return
            }

            let oldHeight = pageHeights[page.cacheKey] ?? height(for: page, width: max(collectionView.bounds.width, 1))
            let oldFrame = (collectionView.collectionViewLayout as? WebtoonCollectionLayout)?.frameForItem(at: index)
            imageSizes[page.cacheKey] = size
            let newHeight = height(for: page, width: max(collectionView.bounds.width, 1))
            pageHeights[page.cacheKey] = newHeight
            let delta = newHeight - oldHeight
            guard abs(delta) >= 1 else { return }

            let pageFrame = oldFrame ?? CGRect(x: 0, y: 0, width: collectionView.bounds.width, height: oldHeight)
            let viewport = CGRect(
                x: 0,
                y: max(collectionView.contentOffset.y - collectionView.bounds.height, 0),
                width: max(collectionView.bounds.width, 1),
                height: collectionView.bounds.height * 3
            )
            let wasAboveViewport = pageFrame.maxY <= collectionView.contentOffset.y + 1
            let isNearViewport = pageFrame.intersects(viewport)

            guard wasAboveViewport || isNearViewport else {
                scheduleLayoutUpdate(in: collectionView)
                return
            }

            UIView.performWithoutAnimation {
                updateLayoutHeights(in: collectionView)
                collectionView.layoutIfNeeded()
                if wasAboveViewport {
                    let adjusted = CGPoint(
                        x: collectionView.contentOffset.x,
                        y: max(0, collectionView.contentOffset.y + delta)
                    )
                    collectionView.setContentOffset(adjusted, animated: false)
                }
            }
        }

        private func scheduleLayoutUpdate(in collectionView: UICollectionView) {
            pendingLayoutWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                UIView.performWithoutAnimation {
                    self.updateLayoutHeights(in: collectionView)
                    collectionView.layoutIfNeeded()
                }
            }
            pendingLayoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        private func updateLayoutHeights(in collectionView: UICollectionView) {
            let width = max(collectionView.bounds.width, lastKnownWidth, UIScreen.main.bounds.width, 1)
            let heights = pages.map { page in
                pageHeights[page.cacheKey] ?? height(for: page, width: width)
            }
            (collectionView.collectionViewLayout as? WebtoonCollectionLayout)?.setItemHeights(heights)
            collectionView.collectionViewLayout.invalidateLayout()
        }

        private func height(for page: PageData, width: CGFloat) -> CGFloat {
            if let size = imageSizes[page.cacheKey], size.width > 0 {
                return max(1, width * (size.height / size.width))
            }
            if let text = page.textContent {
                let constraint = CGSize(width: max(width - 48, 1), height: CGFloat.greatestFiniteMagnitude)
                let rect = (text as NSString).boundingRect(
                    with: constraint,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.preferredFont(forTextStyle: .body)],
                    context: nil
                )
                return max(320, ceil(rect.height) + 64)
            }
            return max(320, width * estimatedImageAspectRatio())
        }

        private func estimatedImageAspectRatio() -> CGFloat {
            let ratios = imageSizes.values.compactMap { size -> CGFloat? in
                guard size.width > 0, size.height > 0 else { return nil }
                return size.height / size.width
            }
            guard !ratios.isEmpty else { return Self.defaultImageAspectRatio }

            let sorted = ratios.sorted()
            let median = sorted[sorted.count / 2]
            return min(max(median, 1.6), 6.0)
        }

        private func updateCurrentPage(in collectionView: WebtoonCollectionView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let midpoint = collectionView.contentOffset.y + collectionView.bounds.height * 0.5
            let visibleIndex = (collectionView.collectionViewLayout as? WebtoonCollectionLayout)?.indexForY(midpoint)
                ?? collectionView.indexPathsForVisibleItems.sorted().first?.item

            guard let visibleIndex, visibleIndex >= 0, visibleIndex < pages.count else { return }
            if force || lastReportedPage != visibleIndex {
                lastReportedPage = visibleIndex
                reader_manager.setIndex(visibleIndex)
                prefetchWindow(around: visibleIndex, in: collectionView)

                let now = Date()
                if force || now.timeIntervalSince(lastScrollLogTime) > 2 {
                    lastScrollLogTime = now
                    ReaderLogger.shared.log("Webtoon current page=\(visibleIndex + 1)/\(pages.count)", type: "ReaderProgress")
                }
            }
        }

        private func prefetchWindow(around index: Int, in collectionView: UICollectionView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let anchor = max(0, (index / 4) * 4)
            guard force || anchor != lastWarmAnchor else { return }
            lastWarmAnchor = anchor

            let lower = max(index - 4, 0)
            let upper = min(index + 18, pages.count - 1)
            guard lower <= upper else { return }
            warmPages(Array(lower...upper), collectionView: collectionView)
        }

        private func warmPages(_ indexes: [Int], collectionView: UICollectionView) {
            let targetSize = targetImageSize(for: collectionView)
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale

            for index in indexes {
                guard index >= 0, index < pages.count else { continue }
                let page = pages[index]
                if page.textContent != nil { continue }
                if page.imageData != nil {
                    let warmKey = "data|\(page.cacheKey)"
                    guard !activeWarmKeys.contains(warmKey), !warmedKeys.contains(warmKey) else { continue }
                    activeWarmKeys.insert(warmKey)
                    Task.detached(priority: .utility) { [weak self, weak collectionView] in
                        let image = try? await ReaderWebtoonImagePipeline.loadImage(for: page, targetSize: targetSize, scale: scale)
                        await MainActor.run {
                            guard let self else { return }
                            self.activeWarmKeys.remove(warmKey)
                            guard let image, let collectionView else { return }
                            self.warmedKeys.insert(warmKey)
                            self.updateImageSize(page: page, size: image.size, index: index, collectionView: collectionView)
                        }
                    }
                    continue
                }
                guard page.urlString != nil else { continue }

                let warmKey = "\(page.cacheKey)|w\(Int(targetSize.width * scale))"
                guard !activeWarmKeys.contains(warmKey), !warmedKeys.contains(warmKey) else { continue }
                activeWarmKeys.insert(warmKey)

                Task.detached(priority: .utility) { [weak self, weak collectionView] in
                    let image = try? await ReaderWebtoonImagePipeline.loadImage(for: page, targetSize: targetSize, scale: scale)
                    await MainActor.run {
                        guard let self else { return }
                        self.activeWarmKeys.remove(warmKey)
                        guard index < self.pages.count, self.pages[index].id == page.id else { return }
                        if let image {
                            self.warmedKeys.insert(warmKey)
                            if let collectionView {
                                self.updateImageSize(page: page, size: image.size, index: index, collectionView: collectionView)
                            }
                        }
                    }
                }
            }
        }

        private func startChapterWarmup(in collectionView: UICollectionView, around index: Int) {
            chapterWarmTask?.cancel()

            let total = pages.count
            guard total > 1 else { return }

            let orderedIndexes = warmupOrder(total: total, around: index)
            let targetSize = targetImageSize(for: collectionView)
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale
            let maxWarmPages = min(total, 80)

            chapterWarmTask = Task { @MainActor [weak self, weak collectionView] in
                guard let self else { return }
                var warmedCount = 0
                for chunkStart in stride(from: 0, to: orderedIndexes.count, by: 3) {
                    if Task.isCancelled { return }
                    let chunk = Array(orderedIndexes[chunkStart..<min(chunkStart + 3, orderedIndexes.count)])
                    await withTaskGroup(of: (Int, PageData, UIImage?).self) { group in
                        for pageIndex in chunk {
                            guard pageIndex >= 0, pageIndex < self.pages.count else { continue }
                            let page = self.pages[pageIndex]
                            guard page.textContent == nil, page.imageData != nil || page.urlString != nil else { continue }
                            let warmKey = "\(page.cacheKey)|chapter|w\(Int(targetSize.width * scale))"
                            guard !self.activeWarmKeys.contains(warmKey), !self.warmedKeys.contains(warmKey) else { continue }
                            self.activeWarmKeys.insert(warmKey)
                            group.addTask {
                                let image = try? await ReaderWebtoonImagePipeline.loadImage(
                                    for: page,
                                    targetSize: targetSize,
                                    scale: scale
                                )
                                return (pageIndex, page, image)
                            }
                        }

                        for await (pageIndex, page, image) in group {
                            if Task.isCancelled { return }
                            let warmKey = "\(page.cacheKey)|chapter|w\(Int(targetSize.width * scale))"
                            self.activeWarmKeys.remove(warmKey)
                            guard let image,
                                  let collectionView,
                                  pageIndex < self.pages.count,
                                  self.pages[pageIndex].id == page.id else { continue }
                            self.warmedKeys.insert(warmKey)
                            self.updateImageSize(page: page, size: image.size, index: pageIndex, collectionView: collectionView)
                            warmedCount += 1
                        }
                    }

                    if warmedCount >= maxWarmPages {
                        ReaderLogger.shared.log(
                            "Webtoon chapter warmup paused after \(warmedCount) pages total=\(total)",
                            type: "ReaderPerf"
                        )
                        return
                    }
                }

                if warmedCount > 0 {
                    ReaderLogger.shared.log(
                        "Webtoon chapter warmup completed warmed=\(warmedCount) total=\(total)",
                        type: "ReaderPerf"
                    )
                }
            }
        }

        private func warmupOrder(total: Int, around index: Int) -> [Int] {
            let clamped = min(max(index, 0), max(total - 1, 0))
            var ordered: [Int] = []
            var seen = Set<Int>()

            func append(_ value: Int) {
                guard value >= 0, value < total, seen.insert(value).inserted else { return }
                ordered.append(value)
            }

            for offset in 0..<total {
                append(clamped + offset)
                if offset > 0 {
                    append(clamped - offset)
                }
            }
            return ordered
        }

        private func targetImageSize(for collectionView: UICollectionView) -> CGSize {
            let viewportWidth = max(collectionView.bounds.width, 1)
            let viewportHeight = max(collectionView.bounds.height, viewportWidth * 1.45)
            return CGSize(width: viewportWidth, height: viewportHeight)
        }

        private func loadAdjacentChaptersIfNeeded(_ collectionView: UICollectionView) {
            let threshold = max(collectionView.bounds.height * 1.25, 420)
            let topDistance = collectionView.contentOffset.y
            let bottomDistance = collectionView.contentSize.height - (collectionView.contentOffset.y + collectionView.bounds.height)

            if topDistance < threshold {
                prependPreviousChapterIfNeeded()
            }
            if bottomDistance < threshold {
                appendNextChapterIfNeeded()
            }
        }

        private func prependPreviousChapterIfNeeded() {
            guard !loadingPrevious else { return }
            guard (reader_manager.selectedChapter?.idx ?? 0) > 0 else { return }
            guard reader_manager.prevChapter.isEmpty else { return }

            loadingPrevious = true
            reader_manager.fetchTask(bool: false) { [weak self] in
                DispatchQueue.main.async {
                    self?.loadingPrevious = false
                }
            }
        }

        private func appendNextChapterIfNeeded() {
            guard !loadingNext else { return }
            guard let selectedChapter = reader_manager.selectedChapter,
                  let allChapters = reader_manager.chapters,
                  selectedChapter.idx < allChapters.count - 1 else { return }
            guard reader_manager.nextChapter.isEmpty else { return }

            loadingNext = true
            reader_manager.fetchTask(bool: true) { [weak self] in
                DispatchQueue.main.async {
                    self?.loadingNext = false
                }
            }
        }

        private static func identity(for manager: readerManager) -> String {
            "\(manager.selectedChapter?.idx ?? -1):\(manager.selectedChapter?.chapterNumber ?? "")"
        }
    }
}

final class WebtoonCollectionView: UICollectionView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

final class WebtoonCollectionLayout: UICollectionViewLayout {
    private var itemHeights: [CGFloat] = []
    private var cachedAttributes: [UICollectionViewLayoutAttributes] = []
    private var contentSize: CGSize = .zero
    private var lastPreparedWidth: CGFloat = 0

    func setItemHeights(_ heights: [CGFloat]) {
        itemHeights = heights.map { max($0, 1) }
        cachedAttributes.removeAll()
        contentSize = .zero
        lastPreparedWidth = 0
        invalidateLayout()
    }

    override func prepare() {
        guard let collectionView else { return }
        let width = max(collectionView.bounds.width, 1)
        guard cachedAttributes.isEmpty || abs(width - lastPreparedWidth) >= 0.5 else { return }

        cachedAttributes.removeAll()
        lastPreparedWidth = width
        var y: CGFloat = 0
        for (index, height) in itemHeights.enumerated() {
            let indexPath = IndexPath(item: index, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
            attributes.frame = CGRect(x: 0, y: y, width: width, height: max(height, 1))
            cachedAttributes.append(attributes)
            y += max(height, 1)
        }
        contentSize = CGSize(width: width, height: y)
    }

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < cachedAttributes.count else { return nil }
        return cachedAttributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return true }
        return abs(collectionView.bounds.width - newBounds.width) >= 0.5
    }

    func frameForItem(at index: Int) -> CGRect? {
        if cachedAttributes.isEmpty {
            prepare()
        }
        guard index >= 0, index < cachedAttributes.count else { return nil }
        return cachedAttributes[index].frame
    }

    func indexForY(_ y: CGFloat) -> Int? {
        if cachedAttributes.isEmpty {
            prepare()
        }
        guard !cachedAttributes.isEmpty else { return nil }

        var lower = 0
        var upper = cachedAttributes.count - 1
        while lower <= upper {
            let middle = (lower + upper) / 2
            let frame = cachedAttributes[middle].frame
            if y < frame.minY {
                upper = middle - 1
            } else if y > frame.maxY {
                lower = middle + 1
            } else {
                return middle
            }
        }
        return min(max(lower, 0), cachedAttributes.count - 1)
    }
}

final class WebtoonImageCell: UICollectionViewCell {
    static let reuseIdentifier = "WebtoonImageCell"

    private let pageView = WebtoonPageView()
    private var currentPageId: PageData.ID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .black
        backgroundColor = .black
        pageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            pageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentPageId = nil
        pageView.cancelLoad()
        pageView.prepareForReuse()
    }

    func configure(
        page: PageData,
        index: Int,
        targetSize: CGSize,
        scale: CGFloat,
        onImageSize: @escaping (PageData, CGSize, Int) -> Void
    ) {
        currentPageId = page.id
        pageView.configure(page: page, index: index)
        pageView.onImageSize = { [weak self] page, size, index in
            guard self?.currentPageId == page.id else { return }
            onImageSize(page, size, index)
        }
        pageView.onRetry = { [weak self] _ in
            guard self?.currentPageId == page.id else { return }
            self?.pageView.prepareForRetry()
            self?.pageView.loadIfNeeded(targetSize: targetSize, scale: scale)
        }
        pageView.loadIfNeeded(targetSize: targetSize, scale: scale)
    }

    func cancelLoad() {
        pageView.cancelLoad()
    }

    func releaseDisplayedImage() {
        pageView.releaseDisplayedImage()
    }
}

final class WebtoonPageView: UIView, UIGestureRecognizerDelegate {
    private let imageView = UIImageView()
    private let textLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    private var page: PageData?
    private var pageIndex = 0
    private var currentTaskId: UUID?
    private var imageLoadTask: Task<Void, Never>?
    private var imageTask: ImageTask?
    private var didAttemptLoad = false
    private var didLoadSuccessfully = false
    private var zoomScale: CGFloat = 1
    private var zoomTranslation: CGPoint = .zero

    var onImageSize: ((PageData, CGSize, Int) -> Void)?
    var onRetry: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(page: PageData, index: Int) {
        self.page = page
        self.pageIndex = index
        didAttemptLoad = false
        didLoadSuccessfully = false
        currentTaskId = nil
        imageLoadTask?.cancel()
        imageTask?.cancel()
        imageLoadTask = nil
        imageTask = nil
        imageView.image = nil
        textLabel.text = nil
        resetZoom(animated: false)
        showPlaceholder()
    }

    func prepareForReuse() {
        imageLoadTask?.cancel()
        imageTask?.cancel()
        imageLoadTask = nil
        imageTask = nil
        imageView.image = nil
        textLabel.text = nil
        currentTaskId = nil
        didAttemptLoad = false
        didLoadSuccessfully = false
        onImageSize = nil
        onRetry = nil
        resetZoom(animated: false)
        showPlaceholder()
    }

    func prepareForRetry() {
        didAttemptLoad = false
        didLoadSuccessfully = false
        currentTaskId = nil
        imageLoadTask?.cancel()
        imageTask?.cancel()
        imageLoadTask = nil
        imageTask = nil
        imageView.image = nil
    }

    func cancelLoad() {
        imageLoadTask?.cancel()
        imageTask?.cancel()
        imageLoadTask = nil
        imageTask = nil
        currentTaskId = nil
    }

    func releaseDisplayedImage() {
        guard zoomScale <= 1.01 else { return }
        imageLoadTask?.cancel()
        imageTask?.cancel()
        imageLoadTask = nil
        imageTask = nil
        imageView.image = nil
        currentTaskId = nil
        didLoadSuccessfully = false
        didAttemptLoad = false
        showPlaceholder()
    }

    func loadIfNeeded(targetSize: CGSize, scale: CGFloat) {
        guard !didLoadSuccessfully else { return }
        if didAttemptLoad, retryButton.isHidden { return }
        didAttemptLoad = true
        load(targetSize: targetSize, scale: scale)
    }

    private func setup() {
        backgroundColor = .black
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        pinchGesture.delegate = self
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        addGestureRecognizer(pinchGesture)
        addGestureRecognizer(panGesture)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.font = .preferredFont(forTextStyle: .body)
        textLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        textLabel.backgroundColor = .black
        addSubview(textLabel)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        addSubview(activityIndicator)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Retry", for: .normal)
        retryButton.tintColor = .white
        retryButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        retryButton.layer.cornerRadius = 12
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        addSubview(retryButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),

            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            retryButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        showPlaceholder()
    }

    private func load(targetSize: CGSize, scale: CGFloat) {
        guard let page else {
            showFailure()
            return
        }

        if let text = page.textContent {
            textLabel.text = text
            didLoadSuccessfully = true
            showText()
            return
        }

        guard page.imageData != nil || page.urlString != nil else {
            showFailure()
            return
        }

        let taskId = UUID()
        currentTaskId = taskId
        showLoading()
        imageLoadTask?.cancel()
        imageTask?.cancel()

        imageLoadTask = Task { [weak self] in
            do {
                let image = try await ReaderWebtoonImagePipeline.loadImage(
                    for: page,
                    targetSize: targetSize,
                    scale: scale,
                    taskSink: { [weak self] task in
                        Task { @MainActor in
                            self?.imageTask = task
                        }
                    }
                )
                await MainActor.run {
                    guard let self,
                          self.currentTaskId == taskId,
                          let currentPage = self.page,
                          currentPage.id == page.id else { return }
                    self.imageView.image = image
                    self.didLoadSuccessfully = true
                    self.showImage()
                    self.onImageSize?(page, image.size, self.pageIndex)
                }
            } catch {
                await MainActor.run {
                    guard let self,
                          self.currentTaskId == taskId,
                          let currentPage = self.page,
                          currentPage.id == page.id else { return }
                    self.showFailure()
                }
            }
        }
    }

    private func showLoading() {
        imageView.isHidden = true
        textLabel.isHidden = true
        retryButton.isHidden = true
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
    }

    private func showImage() {
        imageView.isHidden = false
        textLabel.isHidden = true
        retryButton.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    private func showText() {
        imageView.isHidden = true
        textLabel.isHidden = false
        retryButton.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    private func showFailure() {
        imageView.isHidden = true
        textLabel.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
        retryButton.isHidden = false
    }

    private func showPlaceholder() {
        imageView.isHidden = true
        textLabel.isHidden = true
        retryButton.isHidden = true
        activityIndicator.stopAnimating()
        activityIndicator.isHidden = true
    }

    @objc private func retryTapped() {
        prepareForRetry()
        onRetry?(pageIndex)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard imageView.image != nil else { return }

        switch gesture.state {
        case .began, .changed:
            zoomScale = min(max(zoomScale * gesture.scale, 1), 4)
            gesture.scale = 1
            if zoomScale <= 1.01 {
                resetZoom(animated: false)
            } else {
                constrainZoomTranslation()
                applyZoomTransform(animated: false)
            }
        case .ended, .cancelled, .failed:
            if zoomScale <= 1.05 {
                resetZoom(animated: true)
            } else {
                constrainZoomTranslation()
                applyZoomTransform(animated: true)
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard imageView.image != nil, zoomScale > 1 else { return }
        let delta = gesture.translation(in: self)
        zoomTranslation.x += delta.x
        zoomTranslation.y += delta.y
        gesture.setTranslation(.zero, in: self)
        constrainZoomTranslation()
        applyZoomTransform(animated: false)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        gestureRecognizer === pinchGesture || gestureRecognizer === panGesture
    }

    private func resetZoom(animated: Bool) {
        zoomScale = 1
        zoomTranslation = .zero
        applyZoomTransform(animated: animated)
    }

    private func constrainZoomTranslation() {
        guard zoomScale > 1 else {
            zoomTranslation = .zero
            return
        }
        let maxX = bounds.width * (zoomScale - 1) * 0.5
        let maxY = bounds.height * (zoomScale - 1) * 0.5
        zoomTranslation.x = min(max(zoomTranslation.x, -maxX), maxX)
        zoomTranslation.y = min(max(zoomTranslation.y, -maxY), maxY)
    }

    private func applyZoomTransform(animated: Bool) {
        let changes = {
            self.imageView.transform = CGAffineTransform(
                translationX: self.zoomTranslation.x,
                y: self.zoomTranslation.y
            ).scaledBy(x: self.zoomScale, y: self.zoomScale)
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }
}

private enum ReaderWebtoonImagePipeline {
    static func loadImage(
        for page: PageData,
        targetSize: CGSize,
        scale: CGFloat,
        taskSink: ((ImageTask) -> Void)? = nil
    ) async throws -> UIImage {
        if let data = page.imageData {
            return try await decodeImageData(data, targetWidth: targetSize.width, scale: scale)
        }

        guard let urlString = page.urlString, let url = URL(string: urlString) else {
            throw ReaderWebtoonImageError.invalidPage
        }

        if url.isFileURL {
            return try await decodeFileImage(at: url, targetWidth: targetSize.width, scale: scale)
        }

        var urlRequest = URLRequest(url: url)
        for (field, value) in page.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }

        let imageRequest = ImageRequest(
            urlRequest: urlRequest,
            processors: [
                ReaderWebtoonDownsampleProcessor(width: max(targetSize.width, 1), scaleFactor: scale)
            ]
        )
        let task = ImagePipeline.shared.loadImage(
            with: imageRequest,
            progress: { _, _, _ in },
            completion: { _ in }
        )
        taskSink?(task)
        let response = try await task.response
        if Task.isCancelled {
            throw CancellationError()
        }
        return response.image
    }

    private static func decodeImageData(_ data: Data, targetWidth: CGFloat, scale: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
                throw ReaderWebtoonImageError.decodeFailed
            }
            return try decodeImageSource(source, targetWidth: targetWidth, scale: scale)
        }.value
    }

    private static func decodeFileImage(at url: URL, targetWidth: CGFloat, scale: CGFloat) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
                throw ReaderWebtoonImageError.decodeFailed
            }
            return try decodeImageSource(source, targetWidth: targetWidth, scale: scale)
        }.value
    }

    private static func decodeImageSource(_ source: CGImageSource, targetWidth: CGFloat, scale: CGFloat) throws -> UIImage {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = CGFloat((properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0)
        let pixelHeight = CGFloat((properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0)

        let targetPixelWidth = max(1, targetWidth * scale)
        let maxPixelSize: CGFloat
        if pixelWidth > 0, pixelHeight > 0, pixelWidth > targetPixelWidth {
            maxPixelSize = max(targetPixelWidth, pixelHeight * (targetPixelWidth / pixelWidth))
        } else {
            maxPixelSize = max(pixelWidth, pixelHeight, targetPixelWidth)
        }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize))
        ] as [CFString: Any] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw ReaderWebtoonImageError.decodeFailed
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

private enum ReaderWebtoonImageError: Error {
    case invalidPage
    case decodeFailed
}

private struct ReaderWebtoonDownsampleProcessor: ImageProcessing {
    let width: CGFloat
    let scaleFactor: CGFloat

    var identifier: String {
        "com.luna.reader.webtoon.downsample?w=\(Int(width * scaleFactor))"
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard image.size.width > width, width > 0 else { return image }

        let finalWidth = width
        let finalHeight = image.size.height * (finalWidth / image.size.width)
        let finalSize = CGSize(width: finalWidth, height: finalHeight)

        var data = image.pngData()
        if data == nil {
            data = image.jpegData(compressionQuality: 1)
        }
        guard let data else { return image }

        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return image
        }

        let maxDimension = round(max(finalSize.width, finalSize.height) * scaleFactor)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as [CFString: Any] as CFDictionary

        guard let output = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return image
        }
        return PlatformImage(cgImage: output, scale: scaleFactor, orientation: image.imageOrientation)
    }
}
