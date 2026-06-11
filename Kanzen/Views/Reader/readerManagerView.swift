//
//  readerManagerView.swift
//  Kanzen
//
//  UIKit-owned reader bridge. The lowercase type name is kept so every
//  existing Detail/Library/History entry point can keep launching the reader.
//

import SwiftUI
import UIKit

#if !os(tvOS)
typealias KanzenReaderChildViewController = UIViewController & KanzenReaderChildControlling

protocol KanzenReaderChildControlling: AnyObject {
    var readerDelegate: KanzenReaderChildDelegate? { get set }
    func setPages(_ pages: [KanzenReaderPage], startPage: Int)
    func applyReaderSettings(reloadCurrentPages: Bool)
    func moveToPage(_ page: Int, animated: Bool)
    func moveLeft()
    func moveRight()
}

protocol KanzenReaderChildDelegate: AnyObject {
    func readerChildDidRequestOverlayToggle()
    func readerChildDidChangePage(_ page: Int, totalPages: Int)
    func readerChildDidReachEnd()
    func readerChildDidRequestNextChapter() -> Bool
}

private func kanzenReaderCanvasColor(for style: UIUserInterfaceStyle) -> UIColor {
    switch UserDefaults.standard.string(forKey: "Reader.backgroundColor") {
    case "white":
        return .white
    case "system":
        return .systemBackground
    case "auto":
        return style == .dark ? .black : .white
    default:
        return .black
    }
}

struct readerManagerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let chapters: [Chapter]?
    let selectedChapter: Chapter?
    let kanzen: KanzenEngine
    let mangaId: Int
    let mangaTitle: String
    let mangaCoverURL: String
    let mangaRoute: MangaContentRoute?
    let mangaFormat: String?
    let totalChapters: Int?
    let latestChapterNumbers: [String]?
    let trackerAniListId: Int?
    let trackerMALId: Int?

    init(
        chapters: [Chapter]?,
        selectedChapter: Chapter?,
        kanzen: KanzenEngine,
        mangaId: Int = 0,
        mangaTitle: String = "",
        mangaCoverURL: String = "",
        mangaRoute: MangaContentRoute? = nil,
        mangaFormat: String? = nil,
        totalChapters: Int? = nil,
        latestChapterNumbers: [String]? = nil,
        trackerAniListId: Int? = nil,
        trackerMALId: Int? = nil
    ) {
        self.chapters = chapters
        self.selectedChapter = selectedChapter
        self.kanzen = kanzen
        self.mangaId = mangaId
        self.mangaTitle = mangaTitle
        self.mangaCoverURL = mangaCoverURL
        self.mangaRoute = mangaRoute
        self.mangaFormat = mangaFormat
        self.totalChapters = totalChapters
        self.latestChapterNumbers = latestChapterNumbers
        self.trackerAniListId = trackerAniListId
        self.trackerMALId = trackerMALId
    }

    func makeUIViewController(context: Context) -> KanzenReaderViewController {
        let session = KanzenReaderSession(
            kanzen: kanzen,
            chapters: chapters,
            selectedChapter: selectedChapter,
            mangaId: mangaId,
            mangaTitle: mangaTitle,
            mangaCoverURL: mangaCoverURL,
            mangaRoute: mangaRoute,
            mangaFormat: mangaFormat,
            totalChapters: totalChapters,
            latestChapterNumbers: latestChapterNumbers,
            trackerAniListId: trackerAniListId,
            trackerMALId: trackerMALId
        )
        let controller = KanzenReaderViewController(session: session)
        controller.onClose = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: KanzenReaderViewController, context: Context) {
        uiViewController.onClose = { dismiss() }
    }
}

final class KanzenReaderViewController: UIViewController, KanzenReaderChildDelegate {
    let session: KanzenReaderSession
    var onClose: (() -> Void)?

    private let overlayView = KanzenReaderOverlayView()
    private let loadingView = UIActivityIndicatorView(style: .large)
    private let errorContainer = UIStackView()
    private let errorLabel = UILabel()
    private var activeReader: KanzenReaderChildViewController?
    private var loadTask: Task<Void, Never>?
    private var barsVisible = true
    private var didRequestClose = false

    private var orientationLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "readerOrientationLockEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "readerOrientationLockEnabled") }
    }

    private var orientationLockMaskRaw: String {
        get { UserDefaults.standard.string(forKey: "readerOrientationLockMask") ?? "all" }
        set { UserDefaults.standard.set(newValue, forKey: "readerOrientationLockMask") }
    }

    init(session: KanzenReaderSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { !barsVisible }
    override var prefersHomeIndicatorAutoHidden: Bool { !barsVisible }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = readerBackgroundColor()
        configureLoadingView()
        configureErrorView()
        configureOverlay()
        ReaderLogger.shared.log("Reader controller opened title=\(mangaLogTitle) chapter=\(session.selectedChapter.chapterNumber) mode=\(session.mode.rawValue)", type: "Reader")
        loadCurrentChapter()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyPersistedOrientationLockIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session.saveCurrentProgress(force: true)
        releaseActiveOrientationLock()
    }

    deinit {
        loadTask?.cancel()
    }

    private func configureLoadingView() {
        loadingView.color = .white
        loadingView.hidesWhenStopped = true
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureErrorView() {
        errorContainer.axis = .vertical
        errorContainer.alignment = .center
        errorContainer.spacing = 12
        errorContainer.isHidden = true
        errorContainer.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.72)
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true

        errorLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        errorLabel.font = .preferredFont(forTextStyle: .subheadline)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center

        let retry = UIButton(type: .system)
        retry.setTitle("Retry", for: .normal)
        retry.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        errorContainer.addArrangedSubview(icon)
        errorContainer.addArrangedSubview(errorLabel)
        errorContainer.addArrangedSubview(retry)
        view.addSubview(errorContainer)
        NSLayoutConstraint.activate([
            errorContainer.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            errorContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            errorContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            errorContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func configureOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.onClose = { [weak self] in self?.closeReader() }
        overlayView.onSettings = { [weak self] in self?.presentSettings() }
        overlayView.onChapterList = { [weak self] in self?.presentChapterList() }
        overlayView.onPreviousChapter = { [weak self] in self?.goToPreviousChapter() }
        overlayView.onNextChapter = { [weak self] in self?.goToNextChapter() }
        overlayView.onOrientationLock = { [weak self] in self?.toggleOrientationLock() }
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateOverlay(page: 0, totalPages: 1)
    }

    private func loadCurrentChapter() {
        loadTask?.cancel()
        loadingView.startAnimating()
        errorContainer.isHidden = true
        activeReader?.view.isHidden = true
        ReaderLogger.shared.log("Reader chapter load start chapter=\(session.selectedChapter.chapterNumber) mode=\(session.mode.rawValue)", type: "Reader")

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let pages = try await self.session.loadSelectedChapter()
                try Task.checkCancellation()
                await MainActor.run {
                    self.loadingView.stopAnimating()
                    self.installReader(for: pages)
                }
            } catch is CancellationError {
                await MainActor.run { self.loadingView.stopAnimating() }
            } catch {
                await MainActor.run {
                    self.loadingView.stopAnimating()
                    self.showError(error.localizedDescription)
                }
                ReaderLogger.shared.log("Reader load failed: \(error.localizedDescription)", type: "ReaderError")
            }
        }
    }

    private func installReader(for pages: [KanzenReaderPage]) {
        let nextReader: KanzenReaderChildViewController
        if pages.allSatisfy(\.isText) {
            nextReader = KanzenTextReaderViewController()
        } else if session.mode == .webtoon {
            nextReader = KanzenWebtoonReaderViewController()
        } else {
            nextReader = KanzenPagedReaderViewController(mode: session.mode)
        }

        let needsNewReader: Bool
        if let activeReader {
            needsNewReader = ObjectIdentifier(type(of: activeReader)) != ObjectIdentifier(type(of: nextReader))
        } else {
            needsNewReader = true
        }

        if needsNewReader {
            activeReader?.willMove(toParent: nil)
            activeReader?.view.removeFromSuperview()
            activeReader?.removeFromParent()

            nextReader.readerDelegate = self
            addChild(nextReader)
            nextReader.view.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(nextReader.view, belowSubview: overlayView)
            NSLayoutConstraint.activate([
                nextReader.view.topAnchor.constraint(equalTo: view.topAnchor),
                nextReader.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                nextReader.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                nextReader.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            nextReader.didMove(toParent: self)
            activeReader = nextReader
        } else {
            activeReader?.readerDelegate = self
            activeReader?.view.isHidden = false
        }

        view.backgroundColor = readerBackgroundColor()
        activeReader?.setPages(pages, startPage: session.currentPage)
        activeReader?.applyReaderSettings(reloadCurrentPages: false)
        updateOverlay(page: session.currentPage, totalPages: pages.count)
        let rendererName = activeReader.map { String(describing: type(of: $0)) } ?? "unknown"
        ReaderLogger.shared.log("Reader installed renderer=\(rendererName) chapter=\(session.selectedChapter.chapterNumber) pages=\(pages.count) startPage=\(session.currentPage)", type: "Reader")
    }

    private func showError(_ message: String) {
        activeReader?.view.isHidden = true
        errorLabel.text = message
        errorContainer.isHidden = false
    }

    @objc private func retryTapped() {
        loadCurrentChapter()
    }

    private func updateOverlay(page: Int, totalPages: Int) {
        overlayView.update(
            title: session.mangaTitle,
            chapter: session.selectedChapter.chapterNumber,
            page: page,
            totalPages: totalPages,
            canPrevious: session.canMovePreviousChapter,
            canNext: session.canMoveNextChapter,
            orientationLocked: orientationLockEnabled
        )
    }

    func readerChildDidRequestOverlayToggle() {
        setBarsVisible(!barsVisible, animated: true)
    }

    func readerChildDidChangePage(_ page: Int, totalPages: Int) {
        session.setCurrentPage(page, totalPages: totalPages)
        updateOverlay(page: page, totalPages: totalPages)
    }

    func readerChildDidReachEnd() {
        session.markCurrentChapterRead()
    }

    func readerChildDidRequestNextChapter() -> Bool {
        guard session.canMoveNextChapter else { return false }
        goToNextChapter()
        return true
    }

    private func setBarsVisible(_ visible: Bool, animated: Bool) {
        barsVisible = visible
        setNeedsStatusBarAppearanceUpdate()
        let changes = {
            self.overlayView.alpha = visible ? 1 : 0
        }
        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        } else {
            changes()
        }
    }

    private func closeReader() {
        guard !didRequestClose else { return }
        didRequestClose = true
        onClose?()
    }

    private func goToPreviousChapter() {
        guard session.movePreviousChapter() else { return }
        loadCurrentChapter()
    }

    private func goToNextChapter() {
        guard session.moveNextChapter(markCurrentRead: true) else { return }
        loadCurrentChapter()
    }

    private func presentChapterList() {
        let view = KanzenReaderChapterListView(
            chapters: session.chapters,
            selectedChapter: session.selectedChapter,
            mangaId: session.mangaId
        ) { [weak self] chapter in
            self?.dismiss(animated: true)
            self?.session.selectChapter(chapter)
            self?.loadCurrentChapter()
        }
        present(UIHostingController(rootView: NavigationView { view }), animated: true)
    }

    private func presentSettings() {
        ReaderLogger.shared.log("Reader settings opened chapter=\(session.selectedChapter.chapterNumber) mode=\(session.mode.rawValue)", type: "ReaderSettings")
        let view = KanzenAidokuStyleReaderSettingsView(
            titleKey: session.mangaRoute?.stableKey ?? "\(session.mangaId)",
            onModeChanged: { [weak self] mode in
                guard let self else { return }
                self.session.mode = mode
                UserDefaults.standard.set(mode.rawValue, forKey: "kanzenReaderMode")
                ReaderLogger.shared.log("Reader mode changed mode=\(mode.rawValue)", type: "ReaderSettings")
                self.loadCurrentChapter()
            },
            onSettingsChanged: { [weak self] requiresReload, key in
                self?.applyReaderSettings(reloadPages: requiresReload, changedKey: key)
            }
        )
        present(UIHostingController(rootView: NavigationView { view }), animated: true)
    }

    private func applyReaderSettings(reloadPages: Bool, changedKey: String) {
        view.backgroundColor = readerBackgroundColor()
        ReaderLogger.shared.log("Reader setting changed key=\(changedKey) reload=\(reloadPages)", type: "ReaderSettings")

        if reloadPages {
            activeReader?.setPages(session.pages, startPage: session.currentPage)
        }
        activeReader?.applyReaderSettings(reloadCurrentPages: false)
        updateOverlay(page: session.currentPage, totalPages: max(session.pages.count, 1))
    }

    private func toggleOrientationLock() {
        if orientationLockEnabled {
            orientationLockEnabled = false
            orientationLockMaskRaw = "all"
            applyOrientationMask(.all)
        } else {
            let mask = currentExactOrientationMask()
            orientationLockEnabled = true
            orientationLockMaskRaw = rawValue(for: mask)
            applyOrientationMask(mask)
        }
        updateOverlay(page: session.currentPage, totalPages: max(session.pages.count, 1))
    }

    private func applyPersistedOrientationLockIfNeeded() {
        guard orientationLockEnabled else { return }
        applyOrientationMask(mask(for: orientationLockMaskRaw))
    }

    private func releaseActiveOrientationLock() {
        AppDelegate.orientationLock = .all
        if #available(iOS 16.0, *) {
            activeWindowScene?.windows.first { $0.isKeyWindow }?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private func currentExactOrientationMask() -> UIInterfaceOrientationMask {
        guard let orientation = activeWindowScene?.interfaceOrientation else { return .portrait }
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return orientation.isLandscape ? .landscape : .portrait
        }
    }

    private func applyOrientationMask(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        if #available(iOS 16.0, *) {
            activeWindowScene?.windows.first { $0.isKeyWindow }?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private func rawValue(for mask: UIInterfaceOrientationMask) -> String {
        switch mask {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .landscape: return "landscape"
        default: return "all"
        }
    }

    private func mask(for rawValue: String) -> UIInterfaceOrientationMask {
        switch rawValue {
        case "portrait": return .portrait
        case "portraitUpsideDown": return .portraitUpsideDown
        case "landscapeLeft": return .landscapeLeft
        case "landscapeRight": return .landscapeRight
        case "landscape": return .landscape
        default: return .all
        }
    }

    private func readerBackgroundColor() -> UIColor {
        kanzenReaderCanvasColor(for: traitCollection.userInterfaceStyle)
    }

    private var mangaLogTitle: String {
        session.mangaTitle.isEmpty ? "<untitled>" : session.mangaTitle
    }
}

private final class KanzenReaderOverlayView: UIView {
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onChapterList: (() -> Void)?
    var onPreviousChapter: (() -> Void)?
    var onNextChapter: (() -> Void)?
    var onOrientationLock: (() -> Void)?

    private let topPanel = UIStackView()
    private let bottomPanel = UIStackView()
    private let titleLabel = UILabel()
    private let chapterLabel = UILabel()
    private let pageLabel = UILabel()
    private let previousButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let lockButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        configureTopPanel()
        configureBottomPanel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    func update(
        title: String,
        chapter: String,
        page: Int,
        totalPages: Int,
        canPrevious: Bool,
        canNext: Bool,
        orientationLocked: Bool
    ) {
        titleLabel.text = title.isEmpty ? "Reader" : title
        chapterLabel.text = chapter
        pageLabel.text = "\(min(max(page + 1, 1), max(totalPages, 1))) of \(max(totalPages, 1))"
        previousButton.isEnabled = canPrevious
        nextButton.isEnabled = canNext
        previousButton.tintColor = canPrevious ? .white : UIColor.white.withAlphaComponent(0.3)
        nextButton.tintColor = canNext ? .white : UIColor.white.withAlphaComponent(0.3)
        lockButton.setImage(UIImage(systemName: orientationLocked ? "lock.fill" : "lock.open"), for: .normal)
    }

    private func configureTopPanel() {
        topPanel.axis = .horizontal
        topPanel.alignment = .center
        topPanel.spacing = 12
        topPanel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        topPanel.layer.cornerRadius = 22
        topPanel.isLayoutMarginsRelativeArrangement = true
        topPanel.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        topPanel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.textColor = .white
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail

        chapterLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        chapterLabel.font = .preferredFont(forTextStyle: .subheadline)
        chapterLabel.adjustsFontForContentSizeCategory = true
        chapterLabel.lineBreakMode = .byTruncatingTail

        let labels = UIStackView(arrangedSubviews: [titleLabel, chapterLabel])
        labels.axis = .vertical
        labels.spacing = 2

        let close = iconButton("xmark", action: #selector(closeTapped))
        topPanel.addArrangedSubview(labels)
        topPanel.addArrangedSubview(close)
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(topPanel)
        let preferredWidth = topPanel.widthAnchor.constraint(equalTo: widthAnchor, constant: -72)
        preferredWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            topPanel.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            topPanel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            topPanel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            topPanel.centerXAnchor.constraint(equalTo: centerXAnchor),
            preferredWidth,
            topPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 720)
        ])
    }

    private func configureBottomPanel() {
        bottomPanel.axis = .horizontal
        bottomPanel.alignment = .center
        bottomPanel.spacing = 16
        bottomPanel.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        bottomPanel.layer.cornerRadius = 22
        bottomPanel.isLayoutMarginsRelativeArrangement = true
        bottomPanel.layoutMargins = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false

        lockButton.tintColor = .white
        lockButton.addTarget(self, action: #selector(lockTapped), for: .touchUpInside)
        constrainIcon(lockButton)

        let settings = iconButton("gearshape.fill", action: #selector(settingsTapped))
        let list = iconButton("list.bullet", action: #selector(listTapped))
        let spacer = UIView()

        previousButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        previousButton.addTarget(self, action: #selector(previousTapped), for: .touchUpInside)
        constrainIcon(previousButton, width: 28)

        pageLabel.textColor = .white
        pageLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .medium)
        pageLabel.textAlignment = .center
        pageLabel.adjustsFontSizeToFitWidth = true
        pageLabel.minimumScaleFactor = 0.78
        pageLabel.widthAnchor.constraint(equalToConstant: 82).isActive = true

        nextButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        constrainIcon(nextButton, width: 28)

        let pager = UIStackView(arrangedSubviews: [previousButton, pageLabel, nextButton])
        pager.axis = .horizontal
        pager.alignment = .center
        pager.spacing = 8
        pager.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        pager.layer.cornerRadius = 18
        pager.isLayoutMarginsRelativeArrangement = true
        pager.layoutMargins = UIEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)

        [lockButton, settings, list, spacer, pager].forEach { bottomPanel.addArrangedSubview($0) }
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(bottomPanel)
        let preferredWidth = bottomPanel.widthAnchor.constraint(equalTo: widthAnchor, constant: -72)
        preferredWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            bottomPanel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            bottomPanel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            bottomPanel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            bottomPanel.centerXAnchor.constraint(equalTo: centerXAnchor),
            topPanel.widthAnchor.constraint(equalTo: bottomPanel.widthAnchor),
            preferredWidth,
            bottomPanel.widthAnchor.constraint(lessThanOrEqualToConstant: 720)
        ])
    }

    private func iconButton(_ systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.addTarget(self, action: action, for: .touchUpInside)
        constrainIcon(button)
        return button
    }

    private func constrainIcon(_ button: UIButton, width: CGFloat = 36) {
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func settingsTapped() { onSettings?() }
    @objc private func listTapped() { onChapterList?() }
    @objc private func previousTapped() { onPreviousChapter?() }
    @objc private func nextTapped() { onNextChapter?() }
    @objc private func lockTapped() { onOrientationLock?() }
}

private struct KanzenReaderChapterListView: View {
    let chapters: [Chapter]
    let selectedChapter: Chapter
    let mangaId: Int
    let onSelect: (Chapter) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reversed = false

    private var displayedChapters: [Chapter] {
        reversed ? chapters.reversed() : chapters
    }

    var body: some View {
        List {
            Section {
                ForEach(displayedChapters) { chapter in
                    Button {
                        dismiss()
                        onSelect(chapter)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chapter.chapterNumber)
                                    .foregroundColor(.primary)
                                    .fontWeight(ChapterIdentityNormalizer.key(for: chapter.chapterNumber) == ChapterIdentityNormalizer.key(for: selectedChapter.chapterNumber) ? .bold : .regular)
                                if let group = chapter.chapterData?.first?.scanlationGroup, !group.isEmpty {
                                    Text(group)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if mangaId != 0, MangaReadingProgressManager.shared.isChapterRead(mangaId: mangaId, chapterNumber: chapter.chapterNumber) {
                                Text("Read")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(chapters.count) Chapters")
                    Spacer()
                    Button {
                        reversed.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
            }
        }
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

private struct KanzenAidokuStyleReaderSettingsView: View {
    let titleKey: String
    let onModeChanged: (KanzenReaderMode) -> Void
    let onSettingsChanged: (_ requiresReload: Bool, _ key: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("kanzenReaderMode") private var modeRaw = KanzenReaderMode.currentDefault().rawValue
    @AppStorage("Reader.downsampleImages") private var downsampleImages = true
    @AppStorage("Reader.disableDoubleTap") private var disableDoubleTap = false
    @AppStorage("Reader.hideBarsOnSwipe") private var hideBarsOnSwipe = false
    @AppStorage("Reader.backgroundColor") private var backgroundColor = "black"
    @AppStorage("Reader.pagesToPreload") private var pagesToPreload = 3
    @AppStorage("Reader.pagedPageLayout") private var pagedLayout = "single"
    @AppStorage("Reader.verticalInfiniteScroll") private var infiniteScroll = true
    @AppStorage("Reader.pillarbox") private var pillarbox = false
    @AppStorage("Reader.pillarboxAmount") private var pillarboxAmount = 15.0
    @AppStorage("readerFontSize") private var textFontSize = 16.0
    @AppStorage("readerLineSpacing") private var textLineSpacing = 1.6
    @AppStorage("readerMargin") private var textHorizontalPadding = 4.0

    var body: some View {
        Form {
            Section("General") {
                Picker("Reading Mode", selection: Binding(
                    get: { KanzenReaderMode(rawValue: modeRaw) ?? .webtoon },
                    set: {
                        modeRaw = $0.rawValue
                        onModeChanged($0)
                    }
                )) {
                    ForEach(KanzenReaderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Toggle("Downsample Images", isOn: $downsampleImages)
                Toggle("Disable Double Tap Zoom", isOn: $disableDoubleTap)
                Toggle("Hide Bars On Swipe", isOn: $hideBarsOnSwipe)
                Picker("Background", selection: $backgroundColor) {
                    Text("Black").tag("black")
                    Text("White").tag("white")
                    Text("System").tag("system")
                    Text("Auto").tag("auto")
                }
                .pickerStyle(.menu)
            }

            Section("Paged") {
                Stepper("Pages To Preload: \(pagesToPreload)", value: $pagesToPreload, in: 1...10)
                Picker("Page Layout", selection: $pagedLayout) {
                    Text("Single").tag("single")
                    Text("Double").tag("double")
                    Text("Auto").tag("auto")
                }
                .pickerStyle(.menu)
            }

            Section("Webtoon") {
                Toggle("Infinite Vertical Scroll", isOn: $infiniteScroll)
                Toggle("Pillarbox", isOn: $pillarbox)
                Stepper("Pillarbox Amount: \(Int(pillarboxAmount))%", value: $pillarboxAmount, in: 5...95, step: 5)
                    .disabled(!pillarbox)
            }

            Section("Text") {
                Stepper("Font Size: \(Int(textFontSize))", value: $textFontSize, in: 12...32, step: 1)
                Stepper("Line Spacing: \(String(format: "%.1f", textLineSpacing))", value: $textLineSpacing, in: 1...3, step: 0.1)
                Stepper("Margin: \(Int(textHorizontalPadding))", value: $textHorizontalPadding, in: 0...30, step: 1)
            }
        }
        .navigationTitle("Reader Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onChange(of: downsampleImages) { _ in onSettingsChanged(true, "Reader.downsampleImages") }
        .onChange(of: disableDoubleTap) { _ in onSettingsChanged(false, "Reader.disableDoubleTap") }
        .onChange(of: hideBarsOnSwipe) { _ in onSettingsChanged(false, "Reader.hideBarsOnSwipe") }
        .onChange(of: backgroundColor) { _ in onSettingsChanged(false, "Reader.backgroundColor") }
        .onChange(of: pagesToPreload) { _ in onSettingsChanged(false, "Reader.pagesToPreload") }
        .onChange(of: pagedLayout) { _ in onSettingsChanged(true, "Reader.pagedPageLayout") }
        .onChange(of: infiniteScroll) { _ in onSettingsChanged(false, "Reader.verticalInfiniteScroll") }
        .onChange(of: pillarbox) { _ in onSettingsChanged(true, "Reader.pillarbox") }
        .onChange(of: pillarboxAmount) { _ in onSettingsChanged(true, "Reader.pillarboxAmount") }
        .onChange(of: textFontSize) { _ in onSettingsChanged(true, "readerFontSize") }
        .onChange(of: textLineSpacing) { _ in onSettingsChanged(true, "readerLineSpacing") }
        .onChange(of: textHorizontalPadding) { _ in onSettingsChanged(true, "readerMargin") }
    }
}
#endif
