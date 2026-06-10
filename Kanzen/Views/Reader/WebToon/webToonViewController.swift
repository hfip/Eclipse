//
//  WebtoonView.swift
//  Kanzen
//
//  Created by Dawud Osman on 01/09/2025.
//

import SwiftUI
import Kingfisher
import QuartzCore

struct WebtoonView: UIViewRepresentable {
    @ObservedObject var reader_manager: readerManager
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(reader_manager: reader_manager, onTap: onTap)
    }

    func makeUIView(context: Context) -> WebtoonScrollContainerView {
        let container = WebtoonScrollContainerView()
        container.scrollView.delegate = context.coordinator
        container.onLayout = { [weak coordinator = context.coordinator, weak container] in
            guard let container else { return }
            coordinator?.containerDidLayout(container)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        container.scrollView.addGestureRecognizer(tap)

        context.coordinator.container = container
        context.coordinator.startPerfMonitoring()
        return container
    }

    func updateUIView(_ uiView: WebtoonScrollContainerView, context: Context) {
        context.coordinator.reader_manager = reader_manager
        context.coordinator.onTap = onTap
        context.coordinator.configure(uiView, manager: reader_manager)
    }

    static func dismantleUIView(_ uiView: WebtoonScrollContainerView, coordinator: Coordinator) {
        coordinator.stopPerfMonitoring()
        coordinator.cancelWork()
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var reader_manager: readerManager
        var onTap: () -> Void
        weak var container: WebtoonScrollContainerView?

        private var pages: [PageData]
        private var pageViews: [WebtoonPageView] = []
        private var pageHeights: [String: CGFloat] = [:]
        private var imageSizes: [String: CGSize] = [:]
        private var chapterIdentity: String
        private var lastKnownWidth: CGFloat = 0
        private var loadingPrevious = false
        private var loadingNext = false
        private var lastReportedPage = -1
        private var lastLoadedAnchor = -1
        private var lastWarmAnchor = -1
        private var activeWarmKeys = Set<String>()
        private var warmedKeys = Set<String>()
        private var backgroundWarmWorkItem: DispatchWorkItem?
        private var pendingScrollToPage: Int?
        private var didInitialPosition = false
        private var displayLink: CADisplayLink?
        private var lastDisplayTimestamp: CFTimeInterval?
        private var lastHitchLogTime = Date.distantPast
        private var lastScrollLogTime = Date.distantPast

        private static let defaultImageAspectRatio: CGFloat = 1.435

        init(reader_manager: readerManager, onTap: @escaping () -> Void) {
            self.reader_manager = reader_manager
            self.onTap = onTap
            self.pages = reader_manager.currChapter
            self.chapterIdentity = Self.identity(for: reader_manager)
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

        func configure(_ container: WebtoonScrollContainerView, manager: readerManager) {
            let identity = Self.identity(for: manager)
            if identity != chapterIdentity || pages.map(\.id) != manager.currChapter.map(\.id) {
                reset(container, manager: manager)
            }

            if manager.changeIndex,
               manager.index >= 0,
               manager.index < pages.count {
                pendingScrollToPage = manager.index
                manager.changeIndex = false
                scrollToPendingPage(in: container)
            } else if !didInitialPosition, !pages.isEmpty {
                pendingScrollToPage = min(max(manager.index, 0), pages.count - 1)
                scrollToPendingPage(in: container)
            }
        }

        func containerDidLayout(_ container: WebtoonScrollContainerView) {
            let width = max(container.scrollView.bounds.width, 1)
            if abs(width - lastKnownWidth) >= 1 {
                lastKnownWidth = width
                updateAllPageHeights(in: container, preserveCurrentPage: didInitialPosition)
            }
            scrollToPendingPage(in: container)
        }

        private func reset(_ container: WebtoonScrollContainerView, manager: readerManager) {
            cancelWork()
            pages = manager.currChapter
            chapterIdentity = Self.identity(for: manager)
            pageHeights.removeAll()
            imageSizes.removeAll()
            activeWarmKeys.removeAll()
            warmedKeys.removeAll()
            pageViews.removeAll()
            lastLoadedAnchor = -1
            lastWarmAnchor = -1
            lastReportedPage = -1
            loadingPrevious = false
            loadingNext = false
            didInitialPosition = false
            lastDisplayTimestamp = nil
            pendingScrollToPage = min(max(manager.index, 0), max(pages.count - 1, 0))

            container.removeAllPages()
            guard !pages.isEmpty else { return }

            let width = max(container.scrollView.bounds.width, lastKnownWidth, UIScreen.main.bounds.width, 1)
            lastKnownWidth = width
            for (index, page) in pages.enumerated() {
                let pageView = WebtoonPageView()
                pageView.configure(page: page, index: index)
                pageView.onImageSize = { [weak self, weak container, weak pageView] page, size, index in
                    guard let self, let container, let pageView else { return }
                    self.updateImageSize(page: page, size: size, index: index, pageView: pageView, container: container)
                }
                pageView.onRetry = { [weak self, weak container] index in
                    guard let self, let container else { return }
                    self.loadPagesAround(index, in: container, force: true)
                }
                let height = height(for: page, width: width)
                pageHeights[page.cacheKey] = height
                pageView.setHeight(height)
                container.addPageView(pageView)
                pageViews.append(pageView)
            }

            ReaderLogger.shared.log(
                "Webtoon stack reset chapter=\(manager.selectedChapter?.chapterNumber ?? "<none>") pages=\(pages.count)",
                type: "ReaderWebtoon"
            )

            DispatchQueue.main.async { [weak self, weak container] in
                guard let self, let container else { return }
                container.layoutIfNeeded()
                self.scrollToPendingPage(in: container)
                self.loadPagesAround(max(0, self.reader_manager.index), in: container, force: true)
                self.scheduleBackgroundWarm(around: max(0, self.reader_manager.index), in: container, force: true)
            }
        }

        func cancelWork() {
            backgroundWarmWorkItem?.cancel()
            backgroundWarmWorkItem = nil
            for view in pageViews {
                view.cancelLoad()
            }
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

            let scrollView = container?.scrollView
            let offset = Int(scrollView?.contentOffset.y ?? 0)
            let contentHeight = Int(scrollView?.contentSize.height ?? 0)
            let dragging = scrollView?.isDragging == true
            let decelerating = scrollView?.isDecelerating == true

            ReaderLogger.shared.log(
                "Webtoon frame hitch deltaMs=\(Int(deltaMs)) page=\(lastReportedPage + 1)/\(pages.count) offset=\(offset)/\(contentHeight) dragging=\(dragging) decel=\(decelerating) activeWarm=\(activeWarmKeys.count)",
                type: "ReaderPerf"
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let container, !pages.isEmpty else { return }
            updateCurrentPage(in: container)
            loadAdjacentChaptersIfNeeded(container)
        }

        private func scrollToPendingPage(in container: WebtoonScrollContainerView) {
            guard let index = pendingScrollToPage,
                  index >= 0,
                  index < pageViews.count else { return }
            container.layoutIfNeeded()
            let frame = pageViews[index].frame
            guard frame.height > 0 || pageViews.count == 1 else { return }
            let maxOffset = max(0, container.scrollView.contentSize.height - container.scrollView.bounds.height)
            let offsetY = min(max(frame.minY, 0), maxOffset)
            container.scrollView.setContentOffset(CGPoint(x: 0, y: offsetY), animated: false)
            pendingScrollToPage = nil
            didInitialPosition = true
            updateCurrentPage(in: container, force: true)
            loadPagesAround(index, in: container, force: true)
            scheduleBackgroundWarm(around: index, in: container, force: true)
        }

        private func updateAllPageHeights(in container: WebtoonScrollContainerView, preserveCurrentPage: Bool) {
            let currentPage = preserveCurrentPage ? max(lastReportedPage, 0) : nil
            for (index, page) in pages.enumerated() where index < pageViews.count {
                let height = height(for: page, width: max(container.scrollView.bounds.width, 1))
                pageHeights[page.cacheKey] = height
                pageViews[index].setHeight(height)
            }
            container.layoutIfNeeded()
            if let currentPage, currentPage < pageViews.count {
                pendingScrollToPage = currentPage
                scrollToPendingPage(in: container)
            }
        }

        private func updateImageSize(
            page: PageData,
            size: CGSize,
            index: Int,
            pageView: WebtoonPageView,
            container: WebtoonScrollContainerView
        ) {
            guard size.width > 0, size.height > 0, index < pages.count, pages[index].id == page.id else { return }
            if let existing = imageSizes[page.cacheKey],
               abs(existing.width - size.width) < 0.5,
               abs(existing.height - size.height) < 0.5 {
                return
            }

            let oldHeight = pageHeights[page.cacheKey] ?? pageView.bounds.height
            imageSizes[page.cacheKey] = size
            let newHeight = height(for: page, width: max(container.scrollView.bounds.width, 1))
            pageHeights[page.cacheKey] = newHeight
            let delta = newHeight - oldHeight
            guard abs(delta) >= 1 else { return }

            let wasAboveViewport = pageView.frame.maxY <= container.scrollView.contentOffset.y + 1
            UIView.performWithoutAnimation {
                pageView.setHeight(newHeight)
                container.layoutIfNeeded()
                if wasAboveViewport {
                    let adjusted = CGPoint(
                        x: container.scrollView.contentOffset.x,
                        y: max(0, container.scrollView.contentOffset.y + delta)
                    )
                    container.scrollView.setContentOffset(adjusted, animated: false)
                }
            }
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
            return min(max(median, 1.35), 6.0)
        }

        private func updateCurrentPage(in container: WebtoonScrollContainerView, force: Bool = false) {
            guard !pageViews.isEmpty else { return }
            let y = container.scrollView.contentOffset.y + container.scrollView.bounds.height * 0.5
            let visibleIndex = pageViews.firstIndex { view in
                view.frame.minY <= y && view.frame.maxY >= y
            } ?? nearestPageIndex(to: y)

            guard let visibleIndex else { return }
            if force || lastReportedPage != visibleIndex {
                lastReportedPage = visibleIndex
                reader_manager.setIndex(visibleIndex)
                loadPagesAround(visibleIndex, in: container)
                scheduleBackgroundWarm(around: visibleIndex, in: container)

                let now = Date()
                if force || now.timeIntervalSince(lastScrollLogTime) > 2 {
                    lastScrollLogTime = now
                    ReaderLogger.shared.log("Webtoon current page=\(visibleIndex + 1)/\(pages.count)", type: "ReaderProgress")
                }
            }
        }

        private func nearestPageIndex(to y: CGFloat) -> Int? {
            guard !pageViews.isEmpty else { return nil }
            return pageViews.enumerated().min { lhs, rhs in
                abs(lhs.element.frame.midY - y) < abs(rhs.element.frame.midY - y)
            }?.offset
        }

        private func loadPagesAround(_ index: Int, in container: WebtoonScrollContainerView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let anchor = max(0, (index / 3) * 3)
            guard force || anchor != lastLoadedAnchor else { return }
            lastLoadedAnchor = anchor

            let lower = max(anchor - 2, 0)
            let upper = min(anchor + 10, pages.count - 1)
            guard lower <= upper else { return }

            let targetSize = targetImageSize(for: container)
            let scale = container.window?.screen.scale ?? UIScreen.main.scale
            for pageIndex in lower...upper where pageIndex < pageViews.count {
                pageViews[pageIndex].loadIfNeeded(
                    targetSize: targetSize,
                    scale: scale
                )
            }
        }

        private func scheduleBackgroundWarm(around index: Int, in container: WebtoonScrollContainerView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let anchor = max(0, (index / 4) * 4)
            guard force || anchor != lastWarmAnchor else { return }
            lastWarmAnchor = anchor
            backgroundWarmWorkItem?.cancel()

            let start = min(max(index + 8, 0), pages.count)
            guard start < pages.count else { return }
            let pageIndexes = Array(start..<pages.count)
            warmBackgroundChunks(pageIndexes, container: container, offset: 0)
        }

        private func warmBackgroundChunks(_ indexes: [Int], container: WebtoonScrollContainerView, offset: Int) {
            guard offset < indexes.count else {
                backgroundWarmWorkItem = nil
                return
            }

            let delay: TimeInterval = (container.scrollView.isDragging || container.scrollView.isDecelerating) ? 0.45 : 0.15
            let workItem = DispatchWorkItem { [weak self, weak container] in
                guard let self, let container else { return }
                let end = min(offset + 4, indexes.count)
                self.warmPages(Array(indexes[offset..<end]), container: container)
                self.warmBackgroundChunks(indexes, container: container, offset: end)
            }
            backgroundWarmWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func warmPages(_ indexes: [Int], container: WebtoonScrollContainerView) {
            let targetSize = targetImageSize(for: container)
            let scale = container.window?.screen.scale ?? UIScreen.main.scale

            for index in indexes {
                guard index >= 0, index < pages.count else { continue }
                let page = pages[index]
                if page.textContent != nil { continue }
                if let data = page.imageData {
                    DispatchQueue.global(qos: .utility).async { [weak self, weak container] in
                        guard let image = UIImage(data: data) else { return }
                        DispatchQueue.main.async {
                            guard let self, let container, index < self.pageViews.count else { return }
                            self.updateImageSize(page: page, size: image.size, index: index, pageView: self.pageViews[index], container: container)
                        }
                    }
                    continue
                }
                guard let urlString = page.urlString, let url = URL(string: urlString) else { continue }

                let warmKey = "\(page.cacheKey)|\(Int(targetSize.width))x\(Int(targetSize.height))"
                guard !activeWarmKeys.contains(warmKey), !warmedKeys.contains(warmKey) else { continue }
                activeWarmKeys.insert(warmKey)

                KingfisherManager.shared.retrieveImage(
                    with: url,
                    options: ReaderPageImageOptions.options(for: page, targetSize: targetSize, scaleFactor: scale)
                ) { [weak self, weak container] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.activeWarmKeys.remove(warmKey)
                        guard index < self.pages.count, self.pages[index].id == page.id else { return }
                        if case .success(let value) = result {
                            self.warmedKeys.insert(warmKey)
                            if let container, index < self.pageViews.count {
                                self.updateImageSize(
                                    page: page,
                                    size: value.image.size,
                                    index: index,
                                    pageView: self.pageViews[index],
                                    container: container
                                )
                            }
                        }
                    }
                }
            }
        }

        private func targetImageSize(for container: WebtoonScrollContainerView) -> CGSize {
            let scale = container.window?.screen.scale ?? UIScreen.main.scale
            let viewportWidth = max(container.scrollView.bounds.width, 1)
            let viewportHeight = max(container.scrollView.bounds.height, viewportWidth * 1.45)
            let targetWidth = max(viewportWidth * scale, 900)
            let targetHeight = max(viewportHeight * scale * 3, targetWidth * 4)
            return CGSize(width: targetWidth, height: targetHeight)
        }

        private func loadAdjacentChaptersIfNeeded(_ container: WebtoonScrollContainerView) {
            let threshold = max(container.scrollView.bounds.height * 1.25, 420)
            let topDistance = container.scrollView.contentOffset.y
            let bottomDistance = container.scrollView.contentSize.height - (container.scrollView.contentOffset.y + container.scrollView.bounds.height)

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

final class WebtoonScrollContainerView: UIView {
    let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    func addPageView(_ view: WebtoonPageView) {
        stackView.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor).isActive = true
    }

    func removeAllPages() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func setup() {
        backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .black
        scrollView.isPagingEnabled = false
        scrollView.bounces = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.scrollsToTop = false
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        if #available(iOS 11.0, *) {
            scrollView.contentInsetAdjustmentBehavior = .never
        }
        addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.backgroundColor = .black
        scrollView.addSubview(contentView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.spacing = 0
        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
    }
}

final class WebtoonPageView: UIView, UIGestureRecognizerDelegate {
    private let imageView = UIImageView()
    private let textLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
    private var heightConstraint: NSLayoutConstraint?

    private var page: PageData?
    private var pageIndex = 0
    private var currentTaskId: UUID?
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
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        textLabel.text = nil
        resetZoom(animated: false)
        showPlaceholder()
    }

    func setHeight(_ value: CGFloat) {
        let safeHeight = max(value, 1)
        if let heightConstraint {
            heightConstraint.constant = safeHeight
        } else {
            let constraint = heightAnchor.constraint(equalToConstant: safeHeight)
            constraint.priority = .required
            constraint.isActive = true
            heightConstraint = constraint
        }
    }

    func cancelLoad() {
        imageView.kf.cancelDownloadTask()
        currentTaskId = nil
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

        if let data = page.imageData {
            let taskId = UUID()
            currentTaskId = taskId
            showLoading()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let image = UIImage(data: data)
                DispatchQueue.main.async {
                    guard let self,
                          self.currentTaskId == taskId,
                          let page = self.page else { return }
                    guard let image else {
                        self.showFailure()
                        return
                    }
                    self.imageView.image = image
                    self.didLoadSuccessfully = true
                    self.showImage()
                    self.onImageSize?(page, image.size, self.pageIndex)
                }
            }
            return
        }

        guard let urlString = page.urlString, let url = URL(string: urlString) else {
            showFailure()
            return
        }

        let taskId = UUID()
        currentTaskId = taskId
        showLoading()

        imageView.kf.setImage(
            with: url,
            options: ReaderPageImageOptions.options(for: page, targetSize: targetSize, scaleFactor: scale)
        ) { [weak self] result in
            guard let self,
                  self.currentTaskId == taskId,
                  let page = self.page else { return }

            switch result {
            case .success(let value):
                self.didLoadSuccessfully = true
                self.showImage()
                self.onImageSize?(page, value.image.size, self.pageIndex)
            case .failure:
                self.showFailure()
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
        didAttemptLoad = false
        didLoadSuccessfully = false
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
