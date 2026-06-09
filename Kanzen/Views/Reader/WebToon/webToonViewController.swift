//
//  WebtoonView.swift
//  Kanzen
//
//  Created by Dawud Osman on 01/09/2025.
//

import SwiftUI
import Kingfisher

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
        collectionView.isPagingEnabled = false
        collectionView.isPrefetchingEnabled = false
        collectionView.alwaysBounceVertical = true
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
        }

        if reader_manager.changeIndex,
           reader_manager.index >= 0,
           reader_manager.index < reader_manager.currChapter.count {
            let indexPath = IndexPath(item: reader_manager.index, section: 0)
            uiView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
            reader_manager.changeIndex = false
        }
    }

    class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
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
            ReaderLogger.shared.log(
                "Webtoon reset chapter=\(manager.selectedChapter?.chapterNumber ?? "<none>") pages=\(pages.count)",
                type: "ReaderWebtoon"
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

            let oldHeight = height(for: page, width: collectionView.bounds.width)
            imageSizes[page.cacheKey] = size
            let newHeight = height(for: page, width: collectionView.bounds.width)
            let delta = newHeight - oldHeight

            DispatchQueue.main.async { [weak collectionView] in
                guard let collectionView else { return }
                guard indexPath.item < self.pages.count, self.pages[indexPath.item].id == page.id else { return }
                let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame ?? .zero
                UIView.performWithoutAnimation {
                    collectionView.collectionViewLayout.invalidateLayout()
                    collectionView.layoutIfNeeded()

                    if delta != 0, frame.maxY <= collectionView.contentOffset.y + 1 {
                        let adjusted = CGPoint(
                            x: collectionView.contentOffset.x,
                            y: max(0, collectionView.contentOffset.y + delta)
                        )
                        collectionView.setContentOffset(adjusted, animated: false)
                    }
                }
                ReaderLogger.shared.log("Webtoon image size updated page=\(indexPath.item) h=\(Int(newHeight))", type: "ReaderWebtoon")
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
            return max(360, width * 1.45)
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
                reader_manager.preloadAdjacentPages()
                let now = Date()
                if now.timeIntervalSince(lastScrollLogTime) > 2 {
                    lastScrollLogTime = now
                    ReaderLogger.shared.log("Webtoon current page=\(indexPath.item + 1)/\(pages.count)", type: "ReaderProgress")
                }
            }
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

private final class WebtoonImageCell: UICollectionViewCell {
    static let reuseIdentifier = "WebtoonImageCell"

    private let imageView = UIImageView()
    private let textLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)

    private weak var coordinator: WebtoonView.Coordinator?
    private var page: PageData?
    private var indexPath: IndexPath?
    private var currentTaskId: UUID?

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

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)

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
            guard let image = UIImage(data: data) else {
                showFailure()
                return
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

        let collectionBounds = findCollectionView()?.bounds ?? contentView.bounds
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let viewportWidth = max(collectionBounds.width, contentView.bounds.width, 1)
        let viewportHeight = max(collectionBounds.height, contentView.bounds.height, viewportWidth * 1.45)
        let targetWidth = max(viewportWidth * scale, 900)
        let targetHeight = max(viewportHeight * scale * 3, targetWidth * 4)
        let processor = DownsamplingImageProcessor(size: CGSize(width: targetWidth, height: targetHeight))

        var options: KingfisherOptionsInfo = [
            .processor(processor),
            .cacheOriginalImage,
            .transition(.none)
        ]
        if let modifier = page.requestModifier {
            options.append(.requestModifier(modifier))
        }

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
}
