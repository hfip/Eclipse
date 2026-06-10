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
import AsyncDisplayKit

struct WebtoonView: UIViewRepresentable {
    @ObservedObject var reader_manager: readerManager
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(reader_manager: reader_manager, onTap: onTap)
    }

    func makeUIView(context: Context) -> WebtoonTextureContainerView {
        let layout = WebtoonOffsetPreservingLayout()
        let containerView = WebtoonTextureContainerView(layout: layout)
        let collectionNode = containerView.collectionNode
        let collectionView = collectionNode.view
        layout.fallbackHeightProvider = { [weak coordinator = context.coordinator] indexPath, width in
            coordinator?.estimatedHeight(for: indexPath.item, width: width) ?? max(320, width * Coordinator.defaultImageAspectRatio)
        }
        collectionNode.backgroundColor = .black
        collectionNode.dataSource = context.coordinator
        collectionNode.delegate = context.coordinator
        collectionNode.setTuningParameters(collectionNode.tuningParameters(for: .display), for: .minimum, rangeType: .display)
        collectionNode.setTuningParameters(collectionNode.tuningParameters(for: .preload), for: .minimum, rangeType: .preload)
        collectionNode.setTuningParameters(collectionNode.tuningParameters(for: .display), for: .lowMemory, rangeType: .display)
        collectionNode.setTuningParameters(collectionNode.tuningParameters(for: .preload), for: .lowMemory, rangeType: .preload)
        collectionNode.contentInset = .zero
        collectionNode.showsVerticalScrollIndicator = false
        collectionNode.showsHorizontalScrollIndicator = false
        collectionNode.automaticallyManagesSubnodes = true
        collectionNode.shouldAnimateSizeChanges = false
        collectionNode.insetsLayoutMarginsFromSafeArea = false
        collectionView.backgroundColor = .black
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
        containerView.onLayout = { [weak coordinator = context.coordinator, weak collectionNode] in
            guard let collectionNode else { return }
            coordinator?.collectionNodeDidLayout(collectionNode)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        collectionView.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        collectionView.addGestureRecognizer(pinch)

        context.coordinator.collectionNode = collectionNode
        return containerView
    }

    func updateUIView(_ uiView: WebtoonTextureContainerView, context: Context) {
        context.coordinator.reader_manager = reader_manager
        context.coordinator.onTap = onTap
        context.coordinator.configure(uiView.collectionNode, manager: reader_manager)
    }

    static func dismantleUIView(_ uiView: WebtoonTextureContainerView, coordinator: Coordinator) {
        coordinator.stopPerfMonitoring()
        coordinator.cancelWork()
    }

    final class Coordinator: NSObject, ASCollectionDataSource, ASCollectionDelegate, UIGestureRecognizerDelegate {
        var reader_manager: readerManager
        var onTap: () -> Void
        weak var collectionNode: ASCollectionNode?

        private var pages: [PageData] = []
        private var pagesSignature = ""
        private var recentImageRatios: [CGFloat] = []
        private var chapterIdentity = ""
        private var lastKnownWidth: CGFloat = 0
        private var loadingPrevious = false
        private var loadingNext = false
        private var lastReportedPage = -1
        private var pendingLayoutWorkItem: DispatchWorkItem?
        private var pendingScrollToPage: Int?
        private var didInitialPosition = false
        private var needsDeferredLayoutUpdate = false
        private var displayLink: CADisplayLink?
        private var lastDisplayTimestamp: CFTimeInterval?
        private var lastHitchLogTime = Date.distantPast
        private var lastScrollLogTime = Date.distantPast
        private var pendingScrollRetryScheduled = false
        private var pinchStartScale: CGFloat = 1

        fileprivate static let defaultImageAspectRatio: CGFloat = 2.25

        init(reader_manager: readerManager, onTap: @escaping () -> Void) {
            self.reader_manager = reader_manager
            self.onTap = onTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let collectionNode,
                  let layout = collectionNode.view.collectionViewLayout as? WebtoonOffsetPreservingLayout else { return }

            let collectionView = collectionNode.view
            switch gesture.state {
            case .began:
                pinchStartScale = layout.zoomScale
            case .changed, .ended:
                let nextScale = min(max(pinchStartScale * gesture.scale, 1), 5)
                setZoomScale(nextScale, in: collectionView, layout: layout, anchor: gesture.location(in: collectionView))
            case .cancelled, .failed:
                pinchStartScale = layout.zoomScale
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        func configure(_ collectionNode: ASCollectionNode, manager: readerManager) {
            (collectionNode.view.collectionViewLayout as? WebtoonOffsetPreservingLayout)?.fallbackHeightProvider = { [weak self] indexPath, width in
                self?.estimatedHeight(for: indexPath.item, width: width) ?? max(320, width * Self.defaultImageAspectRatio)
            }
            let identity = Self.identity(for: manager)
            let signature = Self.pagesSignature(for: manager.currChapter)
            let needsInitialBuild = pages.isEmpty && !manager.currChapter.isEmpty
            if needsInitialBuild || identity != chapterIdentity || signature != pagesSignature {
                reset(collectionNode, manager: manager, signature: signature)
            }

            if manager.changeIndex,
               manager.index >= 0,
               manager.index < pages.count {
                pendingScrollToPage = manager.index
                manager.changeIndex = false
                scrollToPendingPage(in: collectionNode)
            } else if !didInitialPosition, !pages.isEmpty {
                pendingScrollToPage = min(max(manager.index, 0), pages.count - 1)
                scrollToPendingPage(in: collectionNode)
            }
        }

        func collectionNodeDidLayout(_ collectionNode: ASCollectionNode) {
            let collectionView = collectionNode.view
            let width = max(collectionView.bounds.width, 1)
            if abs(width - lastKnownWidth) >= 1 {
                lastKnownWidth = width
                updateAllPageLayout(in: collectionNode, preserveCurrentPage: didInitialPosition)
            }
            scrollToPendingPage(in: collectionNode)
        }

        private func reset(_ collectionNode: ASCollectionNode, manager: readerManager, signature: String) {
            let collectionView = collectionNode.view
            cancelWork()
            pages = manager.currChapter
            pagesSignature = signature
            chapterIdentity = Self.identity(for: manager)
            recentImageRatios.removeAll()
            lastReportedPage = -1
            loadingPrevious = false
            loadingNext = false
            didInitialPosition = false
            pendingScrollRetryScheduled = false
            lastDisplayTimestamp = nil
            needsDeferredLayoutUpdate = false
            pendingScrollToPage = min(max(manager.index, 0), max(pages.count - 1, 0))

            let width = max(collectionView.bounds.width, lastKnownWidth, UIScreen.main.bounds.width, 1)
            lastKnownWidth = width
            if let layout = collectionView.collectionViewLayout as? WebtoonOffsetPreservingLayout {
                layout.zoomScale = 1
                layout.invalidateLayout()
            }

            ReaderLogger.shared.log(
                "Webtoon texture reset chapter=\(manager.selectedChapter?.chapterNumber ?? "<none>") pages=\(pages.count)",
                type: "ReaderWebtoon"
            )

            Task { @MainActor [weak self, weak collectionNode] in
                guard let self, let collectionNode else { return }
                await collectionNode.reloadData()
                collectionNode.view.layoutIfNeeded()
                self.scrollToPendingPage(in: collectionNode)
            }
        }

        func cancelWork() {
            pendingLayoutWorkItem?.cancel()
            pendingLayoutWorkItem = nil
            needsDeferredLayoutUpdate = false
            reader_manager.flushPendingPagePosition()
            collectionNode?.visibleNodes.compactMap { $0 as? WebtoonTexturePageNode }.forEach { $0.cancelLoad() }
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

            let collectionView = collectionNode?.view
            let offset = Int(collectionView?.contentOffset.y ?? 0)
            let contentHeight = Int(collectionView?.contentSize.height ?? 0)
            let visible = collectionView?.indexPathsForVisibleItems.map(\.item).sorted() ?? []
            ReaderLogger.shared.log(
                "Webtoon frame hitch deltaMs=\(Int(deltaMs)) page=\(lastReportedPage + 1)/\(pages.count) offset=\(offset)/\(contentHeight) visible=\(visible)",
                type: "ReaderPerf"
            )
        }

        func numberOfSections(in collectionNode: ASCollectionNode) -> Int {
            1
        }

        func collectionNode(_ collectionNode: ASCollectionNode, numberOfItemsInSection section: Int) -> Int {
            pages.count
        }

        func collectionNode(_ collectionNode: ASCollectionNode, nodeBlockForItemAt indexPath: IndexPath) -> ASCellNodeBlock {
            guard indexPath.item < pages.count else {
                return { ASCellNode() }
            }
            let page = pages[indexPath.item]
            let index = indexPath.item
            let targetSize = targetImageSize(for: collectionNode)
            let scale = collectionNode.view.window?.screen.scale ?? UIScreen.main.scale
            let estimatedRatio = estimatedImageAspectRatio()
            return { [weak self, weak collectionNode] in
                let node = WebtoonTexturePageNode(
                    page: page,
                    index: index,
                    targetSize: targetSize,
                    scale: scale,
                    estimatedRatio: estimatedRatio
                )
                node.onHeightChanged = { [weak self, weak collectionNode] page, size, index in
                    guard let self, let collectionNode else { return }
                    self.updatePageHeight(page: page, size: size, index: index, collectionView: collectionNode.view)
                }
                return node
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionNode, !pages.isEmpty else { return }
            let collectionView = collectionNode.view
            updateCurrentPage(in: collectionView)
            loadAdjacentChaptersIfNeeded(collectionNode)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate, let collectionView = scrollView as? UICollectionView else { return }
            flushDeferredLayoutUpdate(in: collectionView)
            reader_manager.flushPendingPagePosition()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            flushDeferredLayoutUpdate(in: collectionView)
            reader_manager.flushPendingPagePosition()
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            flushDeferredLayoutUpdate(in: collectionView)
            reader_manager.flushPendingPagePosition()
        }

        private func scrollToPendingPage(in collectionNode: ASCollectionNode) {
            guard let index = pendingScrollToPage,
                  index >= 0,
                  index < pages.count else { return }
            let collectionView = collectionNode.view
            collectionView.layoutIfNeeded()
            let indexPath = IndexPath(item: index, section: 0)

            guard collectionView.numberOfSections > 0 else {
                retryScrollToPendingPage(in: collectionNode)
                return
            }

            guard collectionView.numberOfItems(inSection: 0) > index else {
                retryScrollToPendingPage(in: collectionNode)
                return
            }

            collectionNode.scrollToItem(at: indexPath, at: .top, animated: false)
            pendingScrollRetryScheduled = false
            pendingScrollToPage = nil
            didInitialPosition = true
            updateCurrentPage(in: collectionView, force: true)
        }

        private func retryScrollToPendingPage(in collectionNode: ASCollectionNode) {
            guard !pendingScrollRetryScheduled else { return }
            pendingScrollRetryScheduled = true
            DispatchQueue.main.async { [weak self, weak collectionNode] in
                guard let self, let collectionNode else { return }
                self.pendingScrollRetryScheduled = false
                self.scrollToPendingPage(in: collectionNode)
            }
        }

        private func updateAllPageLayout(in collectionNode: ASCollectionNode, preserveCurrentPage: Bool) {
            let currentPage = preserveCurrentPage ? max(lastReportedPage, 0) : nil
            let collectionView = collectionNode.view
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.layoutIfNeeded()
            if let currentPage, currentPage < pages.count {
                pendingScrollToPage = currentPage
                scrollToPendingPage(in: collectionNode)
            }
        }

        private func updatePageHeight(
            page: PageData,
            size: CGSize?,
            index: Int,
            collectionView: UICollectionView
        ) {
            guard index < pages.count, pages[index].id == page.id else { return }
            if let size, size.width > 0, size.height > 0 {
                let ratio = size.height / size.width
                if ratio.isFinite {
                    recentImageRatios.append(ratio)
                    if recentImageRatios.count > 16 {
                        recentImageRatios.removeFirst(recentImageRatios.count - 16)
                    }
                }
            }

            guard let layout = collectionView.collectionViewLayout as? WebtoonOffsetPreservingLayout else { return }
            let width = max(collectionView.bounds.width, 1)
            let oldFrame = layout.frameForItem(at: index)
            let oldHeight = oldFrame?.height ?? estimatedHeight(for: index, width: width) * layout.zoomScale
            layout.invalidateLayout()
            let newHeight = layout.heightForItem(at: IndexPath(item: index, section: 0), width: width) * layout.zoomScale
            let delta = newHeight - oldHeight
            guard abs(delta) >= 1 else { return }

            let pageFrame = oldFrame ?? CGRect(x: 0, y: 0, width: collectionView.bounds.width * layout.zoomScale, height: oldHeight)
            let viewport = CGRect(
                x: 0,
                y: collectionView.contentOffset.y,
                width: max(collectionView.bounds.width, 1),
                height: collectionView.bounds.height
            )
            let wasAboveViewport = pageFrame.maxY <= collectionView.contentOffset.y + 1
            let isVisible = pageFrame.intersects(viewport)

            guard wasAboveViewport || isVisible else {
                scheduleLayoutUpdate(in: collectionView)
                return
            }

            guard wasAboveViewport || !shouldDeferLayoutUpdate(in: collectionView) else {
                scheduleLayoutUpdate(in: collectionView)
                return
            }

            UIView.performWithoutAnimation {
                layout.invalidateLayout()
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
            guard !shouldDeferLayoutUpdate(in: collectionView) else {
                needsDeferredLayoutUpdate = true
                pendingLayoutWorkItem = nil
                return
            }
            let workItem = DispatchWorkItem { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                UIView.performWithoutAnimation {
                    collectionView.collectionViewLayout.invalidateLayout()
                }
            }
            pendingLayoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        private func flushDeferredLayoutUpdate(in collectionView: UICollectionView) {
            guard needsDeferredLayoutUpdate else { return }
            pendingLayoutWorkItem?.cancel()
            pendingLayoutWorkItem = nil
            needsDeferredLayoutUpdate = false
            UIView.performWithoutAnimation {
                collectionView.collectionViewLayout.invalidateLayout()
            }
        }

        private func shouldDeferLayoutUpdate(in collectionView: UICollectionView) -> Bool {
            collectionView.isTracking || collectionView.isDragging || collectionView.isDecelerating
        }

        fileprivate func estimatedHeight(for index: Int, width: CGFloat) -> CGFloat {
            guard index >= 0, index < pages.count else {
                return max(320, width * Self.defaultImageAspectRatio)
            }
            return estimatedHeight(for: pages[index], width: width)
        }

        private func estimatedHeight(for page: PageData, width: CGFloat) -> CGFloat {
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
            let ratios = recentImageRatios
            guard !ratios.isEmpty else { return Self.defaultImageAspectRatio }

            let sorted = ratios.sorted()
            let median = sorted[sorted.count / 2]
            return min(max(median, 1.6), 6.0)
        }

        private func updateCurrentPage(in collectionView: UICollectionView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let midpoint = CGPoint(
                x: collectionView.contentOffset.x + collectionView.bounds.width * 0.5,
                y: collectionView.contentOffset.y + collectionView.bounds.height * 0.5
            )
            let visibleIndex = collectionView.indexPathForItem(at: midpoint)?.item
                ?? (collectionView.collectionViewLayout as? WebtoonOffsetPreservingLayout)?.indexForY(midpoint.y)
                ?? collectionView.indexPathsForVisibleItems.sorted().first?.item

            guard let visibleIndex, visibleIndex >= 0, visibleIndex < pages.count else { return }
            if force || lastReportedPage != visibleIndex {
                lastReportedPage = visibleIndex
                if force {
                    reader_manager.setIndex(visibleIndex)
                } else {
                    reader_manager.setTransientIndex(visibleIndex)
                }

                let now = Date()
                if force || now.timeIntervalSince(lastScrollLogTime) > 2 {
                    lastScrollLogTime = now
                    ReaderLogger.shared.log("Webtoon current page=\(visibleIndex + 1)/\(pages.count)", type: "ReaderProgress")
                }
            }
        }

        private func targetImageSize(for collectionNode: ASCollectionNode) -> CGSize {
            let collectionView = collectionNode.view
            let zoomScale = (collectionView.collectionViewLayout as? WebtoonOffsetPreservingLayout)?.zoomScale ?? 1
            let viewportWidth = max(collectionView.bounds.width * zoomScale, 1)
            let viewportHeight = max(collectionView.bounds.height, viewportWidth * 1.45)
            return CGSize(width: viewportWidth, height: viewportHeight)
        }

        private func setZoomScale(
            _ scale: CGFloat,
            in collectionView: UICollectionView,
            layout: WebtoonOffsetPreservingLayout,
            anchor: CGPoint
        ) {
            let clamped = min(max(scale, 1), 5)
            guard abs(layout.zoomScale - clamped) >= 0.01 else { return }

            let oldContentSize = collectionView.contentSize
            let normalizedX = (collectionView.contentOffset.x + anchor.x) / max(oldContentSize.width, 1)
            let normalizedY = (collectionView.contentOffset.y + anchor.y) / max(oldContentSize.height, 1)

            layout.zoomScale = clamped
            layout.invalidateLayout()
            collectionView.layoutIfNeeded()

            let maxOffsetX = max(collectionView.contentSize.width - collectionView.bounds.width, 0)
            let maxOffsetY = max(collectionView.contentSize.height - collectionView.bounds.height, 0)
            let nextOffset = CGPoint(
                x: min(max(normalizedX * collectionView.contentSize.width - anchor.x, 0), maxOffsetX),
                y: min(max(normalizedY * collectionView.contentSize.height - anchor.y, 0), maxOffsetY)
            )
            collectionView.setContentOffset(nextOffset, animated: false)
        }

        private func loadAdjacentChaptersIfNeeded(_ collectionNode: ASCollectionNode) {
            let collectionView = collectionNode.view
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

        private static func pagesSignature(for pages: [PageData]) -> String {
            let first = pages.first?.cacheKey ?? ""
            let last = pages.last?.cacheKey ?? ""
            return "\(pages.count)|\(first)|\(last)"
        }
    }
}

final class WebtoonTextureContainerView: UIView {
    let collectionNode: ASCollectionNode
    var onLayout: (() -> Void)?

    init(layout: UICollectionViewLayout) {
        self.collectionNode = ASCollectionNode(collectionViewLayout: layout)
        super.init(frame: .zero)
        backgroundColor = .black
        collectionNode.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(collectionNode.view)
        NSLayoutConstraint.activate([
            collectionNode.view.topAnchor.constraint(equalTo: topAnchor),
            collectionNode.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionNode.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class WebtoonTexturePageNode: ASCellNode {
    private enum RenderState {
        case loading
        case image
        case text
        case failure
    }

    let page: PageData
    let pageIndex: Int
    let targetSize: CGSize
    let scale: CGFloat
    let estimatedRatio: CGFloat
    var onHeightChanged: ((PageData, CGSize?, Int) -> Void)?

    private let imageNode = ASImageNode()
    private let textNode = ASTextNode()
    private let statusNode = ASTextNode()
    private let retryButtonNode = ASButtonNode()
    private var renderState: RenderState = .loading
    private var imageRatio: CGFloat?
    private var didAttemptLoad = false
    private var imageLoadTask: Task<Void, Never>?
    private var imageTask: ImageTask?

    init(
        page: PageData,
        index: Int,
        targetSize: CGSize,
        scale: CGFloat,
        estimatedRatio: CGFloat
    ) {
        self.page = page
        self.pageIndex = index
        self.targetSize = targetSize
        self.scale = scale
        self.estimatedRatio = estimatedRatio
        super.init()
        automaticallyManagesSubnodes = true
        shouldAnimateSizeChanges = false
        backgroundColor = .black

        imageNode.backgroundColor = .black
        imageNode.contentMode = .scaleToFill
        imageNode.isUserInteractionEnabled = false

        textNode.backgroundColor = .black
        textNode.maximumNumberOfLines = 0

        statusNode.attributedText = Self.statusText("Loading...")
        retryButtonNode.setAttributedTitle(Self.buttonText("Retry"), for: .normal)
        retryButtonNode.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        retryButtonNode.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        retryButtonNode.addTarget(self, action: #selector(retryTapped), forControlEvents: .touchUpInside)
    }

    deinit {
        cancelLoad()
    }

    override func didEnterPreloadState() {
        super.didEnterPreloadState()
        loadIfNeeded()
    }

    override func didEnterDisplayState() {
        super.didEnterDisplayState()
        loadIfNeeded()
    }

    override func didExitDisplayState() {
        super.didExitDisplayState()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let ratio = max(imageRatio ?? estimatedRatio, 0.2)
        let child: ASLayoutElement

        switch renderState {
        case .image:
            child = imageNode
        case .text:
            let inset = ASInsetLayoutSpec(
                insets: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24),
                child: textNode
            )
            child = inset
        case .failure:
            child = ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: [],
                child: retryButtonNode
            )
        case .loading:
            child = ASCenterLayoutSpec(
                horizontalPosition: .center,
                verticalPosition: .center,
                sizingOption: [],
                child: statusNode
            )
        }

        return ASRatioLayoutSpec(ratio: ratio, child: child)
    }

    func cancelLoad() {
        imageTask?.cancel()
        imageLoadTask?.cancel()
        imageTask = nil
        imageLoadTask = nil
    }

    private func loadIfNeeded() {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true

        if let text = page.textContent {
            textNode.attributedText = NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.white
                ]
            )
            renderState = .text
            onHeightChanged?(page, nil, pageIndex)
            setNeedsLayout()
            return
        }

        guard page.imageData != nil || page.urlString != nil else {
            renderState = .failure
            onHeightChanged?(page, nil, pageIndex)
            setNeedsLayout()
            return
        }

        imageLoadTask?.cancel()
        imageTask?.cancel()
        renderState = .loading
        setNeedsLayout()

        imageLoadTask = Task { [weak self] in
            guard let self else { return }
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
                    self.imageNode.image = image
                    self.imageRatio = image.size.width > 0 ? image.size.height / image.size.width : self.estimatedRatio
                    self.renderState = .image
                    self.onHeightChanged?(self.page, image.size, self.pageIndex)
                    self.setNeedsLayout()
                }
            } catch {
                await MainActor.run {
                    self.renderState = .failure
                    self.setNeedsLayout()
                }
            }
        }
    }

    @objc private func retryTapped() {
        cancelLoad()
        imageNode.image = nil
        didAttemptLoad = false
        renderState = .loading
        setNeedsLayout()
        loadIfNeeded()
    }

    private static func statusText(_ value: String) -> NSAttributedString {
        NSAttributedString(
            string: value,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .callout),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]
        )
    }

    private static func buttonText(_ value: String) -> NSAttributedString {
        NSAttributedString(
            string: value,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .callout),
                .foregroundColor: UIColor.white
            ]
        )
    }
}

private protocol WebtoonHeightQueryable {
    func webtoonHeight(for width: CGFloat) -> CGFloat
}

extension WebtoonTexturePageNode: WebtoonHeightQueryable {
    func webtoonHeight(for width: CGFloat) -> CGFloat {
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

        let ratio = max(imageRatio ?? estimatedRatio, 0.2)
        return max(1, width * ratio)
    }
}

final class WebtoonCollectionView: UICollectionView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

final class WebtoonOffsetPreservingLayout: UICollectionViewLayout {
    var fallbackHeightProvider: ((IndexPath, CGFloat) -> CGFloat)?
    var zoomScale: CGFloat = 1 {
        didSet {
            zoomScale = min(max(zoomScale, 1), 5)
        }
    }

    private var cachedAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var contentSize: CGSize = .zero
    private var lastPreparedWidth: CGFloat = 0
    private var lastPreparedScale: CGFloat = 1

    override func prepare() {
        guard let collectionView else { return }
        let width = max(collectionView.bounds.width, 1)
        guard cachedAttributes.isEmpty
                || abs(width - lastPreparedWidth) >= 0.5
                || abs(zoomScale - lastPreparedScale) >= 0.01 else { return }

        cachedAttributes.removeAll()
        lastPreparedWidth = width
        lastPreparedScale = zoomScale
        var y: CGFloat = 0
        for section in 0..<collectionView.numberOfSections {
            for item in 0..<collectionView.numberOfItems(inSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
                let height = max(heightForItem(at: indexPath, width: width), 1)
                attributes.frame = CGRect(
                    x: 0,
                    y: y * zoomScale,
                    width: width * zoomScale,
                    height: height * zoomScale
                )
                cachedAttributes[indexPath] = attributes
                y += height
            }
        }
        contentSize = CGSize(width: width * zoomScale, height: y * zoomScale)
    }

    override var collectionViewContentSize: CGSize {
        contentSize
    }

    override func invalidateLayout() {
        cachedAttributes.removeAll()
        contentSize = .zero
        lastPreparedWidth = 0
        super.invalidateLayout()
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        cachedAttributes.values
            .filter { $0.frame.intersects(rect) }
            .sorted {
                if $0.indexPath.section == $1.indexPath.section {
                    return $0.indexPath.item < $1.indexPath.item
                }
                return $0.indexPath.section < $1.indexPath.section
            }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cachedAttributes[indexPath]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return true }
        return abs(collectionView.bounds.width - newBounds.width) >= 0.5
    }

    func frameForItem(at index: Int) -> CGRect? {
        if cachedAttributes.isEmpty {
            prepare()
        }
        return cachedAttributes[IndexPath(item: index, section: 0)]?.frame
    }

    func heightForItem(at indexPath: IndexPath, width: CGFloat) -> CGFloat {
        if let collectionView = collectionView as? ASCollectionView,
           let collectionNode = collectionView.collectionNode,
           let node = collectionNode.nodeForItem(at: indexPath) as? WebtoonHeightQueryable {
            return max(node.webtoonHeight(for: width), 1)
        }
        return max(fallbackHeightProvider?(indexPath, width) ?? width * WebtoonView.Coordinator.defaultImageAspectRatio, 1)
    }

    func indexForY(_ y: CGFloat) -> Int? {
        if cachedAttributes.isEmpty {
            prepare()
        }
        guard !cachedAttributes.isEmpty else { return nil }

        var lower = 0
        var upper = (collectionView?.numberOfItems(inSection: 0) ?? cachedAttributes.count) - 1
        while lower <= upper {
            let middle = (lower + upper) / 2
            guard let frame = frameForItem(at: middle) else {
                break
            }
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
