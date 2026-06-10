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

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        layout.estimatedItemSize = .zero

        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .black
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.prefetchDataSource = context.coordinator
        collectionView.isPagingEnabled = false
        collectionView.isPrefetchingEnabled = true
        collectionView.bounces = false
        collectionView.alwaysBounceVertical = false
        collectionView.scrollsToTop = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.contentInset = .zero
        collectionView.scrollIndicatorInsets = .zero
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        }
        collectionView.register(WebtoonImageCell.self, forCellWithReuseIdentifier: WebtoonImageCell.reuseIdentifier)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        collectionView.addGestureRecognizer(tap)

        context.coordinator.collectionView = collectionView
        context.coordinator.startPerfMonitoring()
        return collectionView
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.reader_manager = reader_manager
        context.coordinator.onTap = onTap

        if reader_manager.currChapter.count > 0,
           context.coordinator.needsReset(for: reader_manager) {
            context.coordinator.reset(to: reader_manager)
            uiView.reloadData()
            uiView.collectionViewLayout.invalidateLayout()
            uiView.layoutIfNeeded()
            context.coordinator.prefetchInitialPages(in: uiView)
        }

        if reader_manager.changeIndex,
           reader_manager.index >= 0,
           reader_manager.index < reader_manager.currChapter.count {
            let indexPath = IndexPath(item: reader_manager.index, section: 0)
            uiView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            reader_manager.changeIndex = false
        }
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
        coordinator.stopPerfMonitoring()
    }

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        var reader_manager: readerManager
        var onTap: () -> Void
        private var pages: [PageData]
        private var chapterIdentity: String
        weak var collectionView: UICollectionView?

        private var imageSizes: [String: CGSize] = [:]
        private var loadingPrevious = false
        private var loadingNext = false
        private var lastReportedPage = -1
        private var lastScrollLogTime = Date.distantPast
        private var activeWarmKeys = Set<String>()
        private var warmedKeys = Set<String>()
        private var lastWarmAnchor = -1
        private var lastBackgroundWarmAnchor = -1
        private var backgroundWarmWorkItem: DispatchWorkItem?
        private var pendingOffsetAdjustment: CGFloat = 0
        private var pendingLayoutWorkItem: DispatchWorkItem?
        private var displayLink: CADisplayLink?
        private var lastDisplayTimestamp: CFTimeInterval?
        private var lastHitchLogTime = Date.distantPast
        private var lastWarmLogTime = Date.distantPast
        private var totalLayoutInvalidations = 0
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

        func needsReset(for manager: readerManager) -> Bool {
            chapterIdentity != Self.identity(for: manager) || pages.map(\.id) != manager.currChapter.map(\.id)
        }

        func reset(to manager: readerManager) {
            pages = manager.currChapter
            chapterIdentity = Self.identity(for: manager)
            loadingPrevious = false
            loadingNext = false
            lastReportedPage = -1
            activeWarmKeys.removeAll()
            warmedKeys.removeAll()
            lastWarmAnchor = -1
            lastBackgroundWarmAnchor = -1
            backgroundWarmWorkItem?.cancel()
            backgroundWarmWorkItem = nil
            pendingOffsetAdjustment = 0
            pendingLayoutWorkItem?.cancel()
            pendingLayoutWorkItem = nil
            lastDisplayTimestamp = nil
            totalLayoutInvalidations = 0
            ReaderLogger.shared.log(
                "Webtoon reset chapter=\(manager.selectedChapter?.chapterNumber ?? "<none>") pages=\(pages.count)",
                type: "ReaderWebtoon"
            )
        }

        deinit {
            displayLink?.invalidate()
            pendingLayoutWorkItem?.cancel()
            backgroundWarmWorkItem?.cancel()
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
            let visibleItems = collectionView?.indexPathsForVisibleItems.map(\.item).sorted() ?? []
            let visibleRange = visibleItems.isEmpty
                ? "none"
                : "\(visibleItems.first ?? 0)-\(visibleItems.last ?? 0)"
            let offset = Int(collectionView?.contentOffset.y ?? 0)
            let contentHeight = Int(collectionView?.contentSize.height ?? 0)
            let dragging = collectionView?.isDragging == true
            let decelerating = collectionView?.isDecelerating == true

            ReaderLogger.shared.log(
                "Webtoon frame hitch deltaMs=\(Int(deltaMs)) page=\(lastReportedPage + 1)/\(pages.count) visible=\(visibleRange) offset=\(offset)/\(contentHeight) dragging=\(dragging) decel=\(decelerating) activeWarm=\(activeWarmKeys.count) pendingLayout=\(pendingLayoutWorkItem != nil)",
                type: "ReaderPerf"
            )
        }

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            1
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            pages.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: WebtoonImageCell.reuseIdentifier,
                for: indexPath
            ) as? WebtoonImageCell else {
                fatalError("Could not dequeue image cell")
            }

            guard indexPath.item < pages.count else {
                cell.setInvalid()
                return cell
            }

            cell.set(page: pages[indexPath.item], coordinator: self, indexPath: indexPath)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            warmPages(at: indexPaths, collectionView: collectionView)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            let width = max(collectionView.bounds.width, 1)
            guard indexPath.item < pages.count else {
                return CGSize(width: width, height: 1)
            }

            return CGSize(
                width: width,
                height: height(for: pages[indexPath.item], width: width)
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView, !pages.isEmpty else { return }
            updateCurrentPage(collectionView)
            loadAdjacentChaptersIfNeeded(collectionView)
        }

        func updateImageSize(for page: PageData, size: CGSize, indexPath: IndexPath, collectionView: UICollectionView) {
            guard size.width > 0, size.height > 0 else { return }

            DispatchQueue.main.async { [weak collectionView] in
                guard let collectionView else { return }
                guard indexPath.item < self.pages.count, self.pages[indexPath.item].id == page.id else { return }
                self.applyImageSizeUpdate(for: page, size: size, indexPath: indexPath, collectionView: collectionView)
            }
        }

        private func applyImageSizeUpdate(
            for page: PageData,
            size: CGSize,
            indexPath: IndexPath,
            collectionView: UICollectionView
        ) {
            if let existing = imageSizes[page.cacheKey],
               abs(existing.width - size.width) < 0.5,
               abs(existing.height - size.height) < 0.5 {
                return
            }

            let oldHeight = height(for: page, width: collectionView.bounds.width)
            imageSizes[page.cacheKey] = size
            let newHeight = height(for: page, width: collectionView.bounds.width)
            let delta = newHeight - oldHeight
            guard abs(delta) >= 1 else { return }

            let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
            if frame.maxY <= collectionView.contentOffset.y + 1 {
                pendingOffsetAdjustment += delta
            }
            scheduleLayoutInvalidation(collectionView)
        }

        private func scheduleLayoutInvalidation(_ collectionView: UICollectionView) {
            guard pendingLayoutWorkItem == nil else { return }

            let workItem = DispatchWorkItem { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                let adjustment = self.pendingOffsetAdjustment
                self.pendingOffsetAdjustment = 0
                self.pendingLayoutWorkItem = nil
                self.totalLayoutInvalidations += 1

                UIView.performWithoutAnimation {
                    collectionView.collectionViewLayout.invalidateLayout()

                    if abs(adjustment) >= 1 {
                        let adjusted = CGPoint(
                            x: collectionView.contentOffset.x,
                            y: max(0, collectionView.contentOffset.y + adjustment)
                        )
                        collectionView.setContentOffset(adjusted, animated: false)
                    }
                }
                if abs(adjustment) >= 8 || self.totalLayoutInvalidations % 10 == 0 {
                    ReaderLogger.shared.log(
                        "Webtoon layout batch count=\(self.totalLayoutInvalidations) offsetAdjust=\(Int(adjustment)) activeWarm=\(self.activeWarmKeys.count) knownSizes=\(self.imageSizes.count)/\(self.pages.count)",
                        type: "ReaderPerf"
                    )
                }
            }
            pendingLayoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        func prefetchInitialPages(in collectionView: UICollectionView) {
            warmWindow(around: max(0, reader_manager.index), collectionView: collectionView, force: true)
            scheduleBackgroundWarm(around: max(0, reader_manager.index), collectionView: collectionView, force: true)
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

        private func updateCurrentPage(_ collectionView: UICollectionView) {
            let point = CGPoint(
                x: collectionView.bounds.midX,
                y: collectionView.contentOffset.y + collectionView.bounds.height * 0.5
            )
            guard let indexPath = collectionView.indexPathForItem(at: point),
                  indexPath.item < pages.count else { return }

            if lastReportedPage != indexPath.item {
                lastReportedPage = indexPath.item
                reader_manager.setIndex(indexPath.item)
                warmWindow(around: indexPath.item, collectionView: collectionView)
                scheduleBackgroundWarm(around: indexPath.item, collectionView: collectionView)
                let now = Date()
                if now.timeIntervalSince(lastScrollLogTime) > 2 {
                    lastScrollLogTime = now
                    ReaderLogger.shared.log("Webtoon current page=\(indexPath.item + 1)/\(pages.count)", type: "ReaderProgress")
                }
            }
        }

        private func warmWindow(around index: Int, collectionView: UICollectionView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let anchor = max(0, (index / 4) * 4)
            guard force || anchor != lastWarmAnchor else { return }
            lastWarmAnchor = anchor

            let lowerBound = max(anchor - 1, 0)
            let upperBound = min(anchor + 18, pages.count - 1)
            guard lowerBound <= upperBound else { return }

            let indexPaths = (lowerBound...upperBound).map { IndexPath(item: $0, section: 0) }
            logWarmPlan(kind: "foreground", range: "\(lowerBound)-\(upperBound)", count: indexPaths.count)
            warmPages(at: indexPaths, collectionView: collectionView)
        }

        private func scheduleBackgroundWarm(around index: Int, collectionView: UICollectionView, force: Bool = false) {
            guard !pages.isEmpty else { return }
            let anchor = max(0, (index / 8) * 8)
            guard force || anchor != lastBackgroundWarmAnchor else { return }
            lastBackgroundWarmAnchor = anchor
            backgroundWarmWorkItem?.cancel()

            let start = min(max(index + 19, 0), pages.count)
            guard start < pages.count else { return }
            let indexPaths = (start..<pages.count).map { IndexPath(item: $0, section: 0) }
            logWarmPlan(kind: "background", range: "\(start)-\(pages.count - 1)", count: indexPaths.count)
            warmBackgroundChunks(indexPaths, collectionView: collectionView, offset: 0)
        }

        private func logWarmPlan(kind: String, range: String, count: Int) {
            let now = Date()
            guard now.timeIntervalSince(lastWarmLogTime) >= 2 else { return }
            lastWarmLogTime = now
            ReaderLogger.shared.log(
                "Webtoon warm plan kind=\(kind) range=\(range) count=\(count) active=\(activeWarmKeys.count) warmed=\(warmedKeys.count)",
                type: "ReaderPerf"
            )
        }

        private func warmBackgroundChunks(
            _ indexPaths: [IndexPath],
            collectionView: UICollectionView,
            offset: Int
        ) {
            guard offset < indexPaths.count else {
                backgroundWarmWorkItem = nil
                return
            }

            let delay: TimeInterval = (collectionView.isDragging || collectionView.isDecelerating) ? 0.7 : 0.35
            let workItem = DispatchWorkItem { [weak self, weak collectionView] in
                guard let self, let collectionView else { return }
                let end = min(offset + 4, indexPaths.count)
                self.warmPages(at: Array(indexPaths[offset..<end]), collectionView: collectionView)
                self.warmBackgroundChunks(indexPaths, collectionView: collectionView, offset: end)
            }
            backgroundWarmWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func warmPages(at indexPaths: [IndexPath], collectionView: UICollectionView) {
            guard !indexPaths.isEmpty, !pages.isEmpty else { return }
            let targetSize = targetImageSize(for: collectionView)
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale

            for indexPath in indexPaths {
                guard indexPath.item >= 0, indexPath.item < pages.count else { continue }
                let page = pages[indexPath.item]

                if let data = page.imageData, let image = UIImage(data: data) {
                    updateImageSize(for: page, size: image.size, indexPath: indexPath, collectionView: collectionView)
                    continue
                }

                guard let value = page.urlString,
                      let url = URL(string: value) else { continue }

                let warmKey = "\(page.cacheKey)|\(Int(targetSize.width))x\(Int(targetSize.height))"
                guard !activeWarmKeys.contains(warmKey), !warmedKeys.contains(warmKey) else { continue }
                activeWarmKeys.insert(warmKey)
                let startedAt = CACurrentMediaTime()

                KingfisherManager.shared.retrieveImage(
                    with: url,
                    options: ReaderPageImageOptions.options(for: page, targetSize: targetSize, scaleFactor: scale)
                ) { [weak self, weak collectionView] result in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.activeWarmKeys.remove(warmKey)

                        guard indexPath.item < self.pages.count,
                              self.pages[indexPath.item].id == page.id else { return }

                        switch result {
                        case .success(let value):
                            self.warmedKeys.insert(warmKey)
                            let elapsedMs = Int((CACurrentMediaTime() - startedAt) * 1000)
                            if elapsedMs >= 180 || value.cacheType == .none {
                                ReaderLogger.shared.log(
                                    "Webtoon warm image page=\(indexPath.item + 1)/\(self.pages.count) elapsedMs=\(elapsedMs) cache=\(Self.cacheTypeName(value.cacheType)) active=\(self.activeWarmKeys.count)",
                                    type: "ReaderPerf"
                                )
                            }
                            if let collectionView {
                                self.updateImageSize(
                                    for: page,
                                    size: value.image.size,
                                    indexPath: indexPath,
                                    collectionView: collectionView
                                )
                            }
                        case .failure(let error):
                            ReaderLogger.shared.log(
                                "Webtoon warm failed page=\(indexPath.item + 1)/\(self.pages.count) elapsedMs=\(Int((CACurrentMediaTime() - startedAt) * 1000)) error=\(error.localizedDescription)",
                                type: "ReaderPerf"
                            )
                        }
                    }
                }
            }
        }

        static func cacheTypeName(_ cacheType: CacheType) -> String {
            switch cacheType {
            case .none:
                return "none"
            case .memory:
                return "memory"
            case .disk:
                return "disk"
            @unknown default:
                return "unknown"
            }
        }

        private func targetImageSize(for collectionView: UICollectionView) -> CGSize {
            let scale = collectionView.window?.screen.scale ?? UIScreen.main.scale
            let viewportWidth = max(collectionView.bounds.width, 1)
            let viewportHeight = max(collectionView.bounds.height, viewportWidth * 1.45)
            let targetWidth = max(viewportWidth * scale, 900)
            let targetHeight = max(viewportHeight * scale * 3, targetWidth * 4)
            return CGSize(width: targetWidth, height: targetHeight)
        }

        private func loadAdjacentChaptersIfNeeded(_ collectionView: UICollectionView) {
            let threshold = max(collectionView.bounds.height * 1.25, 420)
            let topDistance = collectionView.contentOffset.y
            let bottomDistance = collectionView.contentSize.height - (collectionView.contentOffset.y + collectionView.bounds.height)

            if topDistance < threshold {
                prependPreviousChapterIfNeeded(collectionView)
            }

            if bottomDistance < threshold {
                appendNextChapterIfNeeded(collectionView)
            }
        }

        private func prependPreviousChapterIfNeeded(_ collectionView: UICollectionView) {
            guard !loadingPrevious else { return }
            guard (reader_manager.selectedChapter?.idx ?? 0) > 0 else { return }
            guard reader_manager.prevChapter.isEmpty else { return }

            loadingPrevious = true
            ReaderLogger.shared.log("Webtoon prefetch previous boundary", type: "ReaderWebtoon")
            reader_manager.fetchTask(bool: false) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loadingPrevious = false
                }
            }
        }

        private func appendNextChapterIfNeeded(_ collectionView: UICollectionView) {
            guard !loadingNext else { return }
            guard let selectedChapter = reader_manager.selectedChapter,
                  let allChapters = reader_manager.chapters,
                  selectedChapter.idx < allChapters.count - 1 else { return }
            guard reader_manager.nextChapter.isEmpty else { return }

            loadingNext = true
            ReaderLogger.shared.log("Webtoon prefetch next boundary", type: "ReaderWebtoon")
            reader_manager.fetchTask(bool: true) { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.loadingNext = false
                }
            }
        }

        private static func identity(for manager: readerManager) -> String {
            "\(manager.selectedChapter?.idx ?? -1):\(manager.selectedChapter?.chapterNumber ?? "")"
        }
    }
}

private final class WebtoonImageCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    static let reuseIdentifier = "WebtoonImageCell"

    private let imageView = UIImageView()
    private let textLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    private lazy var panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

    private weak var coordinator: WebtoonView.Coordinator?
    private var page: PageData?
    private var indexPath: IndexPath?
    private var currentTaskId: UUID?
    private var zoomScale: CGFloat = 1
    private var zoomTranslation: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        resetZoom(animated: false)
        currentTaskId = nil
        coordinator = nil
        page = nil
        indexPath = nil
        showLoading()
    }

    func set(page: PageData, coordinator: WebtoonView.Coordinator, indexPath: IndexPath) {
        self.page = page
        self.coordinator = coordinator
        self.indexPath = indexPath
        loadImage()
    }

    func setInvalid() {
        showFailure()
    }

    private func setup() {
        contentView.backgroundColor = .black
        contentView.clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        contentView.addSubview(imageView)

        pinchGesture.delegate = self
        panGesture.delegate = self
        panGesture.minimumNumberOfTouches = 2
        panGesture.maximumNumberOfTouches = 2
        contentView.addGestureRecognizer(pinchGesture)
        contentView.addGestureRecognizer(panGesture)

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.numberOfLines = 0
        textLabel.font = .preferredFont(forTextStyle: .body)
        textLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        textLabel.backgroundColor = .black
        contentView.addSubview(textLabel)

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.color = .white
        contentView.addSubview(activityIndicator)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("Retry", for: .normal)
        retryButton.tintColor = .white
        retryButton.backgroundColor = UIColor.white.withAlphaComponent(0.14)
        retryButton.layer.cornerRadius = 12
        retryButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        contentView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            textLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            textLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),
            textLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            textLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        showLoading()
    }

    private func loadImage() {
        guard let page else {
            showFailure()
            return
        }

        if let text = page.textContent {
            textLabel.text = text
            showText()
            return
        }

        if let data = page.imageData {
            let startedAt = CACurrentMediaTime()
            guard let image = UIImage(data: data) else {
                showFailure()
                return
            }
            let elapsedMs = Int((CACurrentMediaTime() - startedAt) * 1000)
            if elapsedMs >= 45 {
                ReaderLogger.shared.log(
                    "Webtoon visible data decode page=\((indexPath?.item ?? 0) + 1) elapsedMs=\(elapsedMs) bytes=\(data.count)",
                    type: "ReaderPerf"
                )
            }
            imageView.image = image
            showImage()
            if let coordinator, let indexPath, let collectionView = findCollectionView(),
               collectionView.indexPath(for: self) == indexPath {
                coordinator.updateImageSize(for: page, size: image.size, indexPath: indexPath, collectionView: collectionView)
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
        let startedAt = CACurrentMediaTime()

        let collectionBounds = findCollectionView()?.bounds ?? contentView.bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let viewportWidth = max(collectionBounds.width, contentView.bounds.width, 1)
        let viewportHeight = max(collectionBounds.height, contentView.bounds.height, viewportWidth * 1.45)
        let targetWidth = max(viewportWidth * scale, 900)
        let targetHeight = max(viewportHeight * scale * 3, targetWidth * 4)

        let options = ReaderPageImageOptions.options(
            for: page,
            targetSize: CGSize(width: targetWidth, height: targetHeight),
            scaleFactor: scale
        )

        imageView.kf.setImage(
            with: url,
            options: options
        ) { [weak self] result in
            guard let self,
                  self.currentTaskId == taskId,
                  let coordinator = self.coordinator,
                  let page = self.page,
                  let indexPath = self.indexPath else { return }

            switch result {
            case .success(let value):
                let elapsedMs = Int((CACurrentMediaTime() - startedAt) * 1000)
                if elapsedMs >= 120 || value.cacheType == .none {
                    ReaderLogger.shared.log(
                        "Webtoon visible image page=\(indexPath.item + 1) elapsedMs=\(elapsedMs) cache=\(WebtoonView.Coordinator.cacheTypeName(value.cacheType)) size=\(Int(value.image.size.width))x\(Int(value.image.size.height))",
                        type: "ReaderPerf"
                    )
                }
                self.showImage()
                if let collectionView = self.findCollectionView(),
                   collectionView.indexPath(for: self) == indexPath {
                    coordinator.updateImageSize(
                        for: page,
                        size: value.image.size,
                        indexPath: indexPath,
                        collectionView: collectionView
                    )
                }
            case .failure(let error):
                ReaderLogger.shared.log(
                    "Webtoon visible image failed page=\(indexPath.item + 1) elapsedMs=\(Int((CACurrentMediaTime() - startedAt) * 1000)) error=\(error.localizedDescription)",
                    type: "ReaderPerf"
                )
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

    @objc private func retryTapped() {
        loadImage()
    }

    private func findCollectionView() -> UICollectionView? {
        var view = superview
        while let current = view {
            if let collectionView = current as? UICollectionView {
                return collectionView
            }
            view = current.superview
        }
        return nil
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
        let delta = gesture.translation(in: contentView)
        zoomTranslation.x += delta.x
        zoomTranslation.y += delta.y
        gesture.setTranslation(.zero, in: contentView)
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
        let maxX = contentView.bounds.width * (zoomScale - 1) * 0.5
        let maxY = contentView.bounds.height * (zoomScale - 1) * 0.5
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
