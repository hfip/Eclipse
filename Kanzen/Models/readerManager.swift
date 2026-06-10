//
//  readerManager.swift
//  Luna
//
//  Created by Dawud Osman on 17/11/2025.
//

import SwiftUI
import Kingfisher



class readerManager: ObservableObject {
    @Published  var chapters: [Chapter]?
    @Published var selectedChapter: Chapter?
    @Published var index: Int
    @Published var currChapter: [PageData]
    @Published var prevChapter: [PageData]
    @Published var nextChapter: [PageData]
    @Published var isLoadingCurrentChapter = false
    @Published var currentErrorMessage: String?
    @AppStorage("readingMode") var readingModeRaw: Int = ReadingMode.WEBTOON.rawValue
    var pagePrefetchers: [ImagePrefetcher] = []
    var backgroundPagePrefetchers: [ImagePrefetcher] = []
    private var lastAdjacentPrefetchSignature: String?
    private var lastBackgroundPrefetchSignature: String?
    var readingMode: ReadingMode {
        let mode = ReadingMode(rawValue: readingModeRaw) ?? .WEBTOON
        return mode == .VERTICAL ? .WEBTOON : mode
    }
    var changeIndex: Bool = false

     var kanzen : KanzenEngine
    var mangaId: Int = 0
    var mangaTitle: String = ""
    var mangaCoverURL: String = ""
    var mangaRoute: MangaContentRoute?
    var mangaFormat: String?
    var totalChapters: Int?
    var latestChapterNumbers: [String]?
    var trackerAniListId: Int?
    var trackerMALId: Int?
    // Cached controllers - only recreated when data changes
 var currControllers: [UIViewController]?
  var prevControllers: [UIViewController]?
var nextControllers: [UIViewController]?
    
    // task
    private var currTask: Task<Void, Never>?
    
    // Task storage for loadPages operations
    private var loadPagesTasks: [ChapterPosition: Task<Void, Never>] = [:]
    

    
    var currRange: ClosedRange<CGFloat> {
        if currChapter.count > 0 {
           return 0...CGFloat(currChapter.count - 1)
        } else {
           return  0...CGFloat(0)
        }
    }
    
    init(index: Int = 0, currChapter: [PageData] = [], prevChapter: [PageData] = [], nextChapter: [PageData] = [], shiftChapterLeft: @escaping () -> Void = {}, shiftChapterRight: @escaping () -> Void = {}, fetchPrev: @escaping () -> Void = {}, fetchNext: @escaping () -> Void = {}, kanzen: KanzenEngine,chapters: [Chapter]?, selectedChapter: Chapter?, mangaId: Int = 0, mangaTitle: String = "", mangaCoverURL: String = "", mangaRoute: MangaContentRoute? = nil, mangaFormat: String? = nil, totalChapters: Int? = nil, latestChapterNumbers: [String]? = nil, trackerAniListId: Int? = nil, trackerMALId: Int? = nil) {
        self.index = index
        self.currChapter = currChapter
        self.prevChapter = prevChapter
        self.nextChapter = nextChapter
        self.kanzen = kanzen
        self.chapters = chapters
        self.selectedChapter = selectedChapter
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
    func initChapters(){
        // resetState
        resetState()

    }
    func resetState()
    {
        cancelAllLoadPagesTasks()
        index = 0
        isLoadingCurrentChapter = true
        currentErrorMessage = nil
        prevChapter = []
        currChapter = []
        nextChapter = []
        currControllers = nil
        prevControllers = nil
        nextControllers = nil
        if let selectedChapter = selectedChapter, let chapters = chapters
        {
            var didStartCurrentLoad = false
            if let currSources = selectedChapter.chapterData, currSources.count > 0,
                let currParams = currSources[0].params
            {
                didStartCurrentLoad = true
                loadPages(chapter: selectedChapter, params: currParams, position: .curr)
            }
            let idx = selectedChapter.idx
            // fetch Prev Images
            
            if idx > 0
            {
                let prevChapter = chapters[idx - 1]
                if let prevSources = prevChapter.chapterData, prevSources.count > 0,
                    let prevParams = prevSources[0].params
                {
                    loadPages(chapter: prevChapter, params: prevParams, position: .prev)
                    
                }
                
            }
            if idx < chapters.count - 1
            {
                let nextChapters = chapters[idx + 1]
                if let nextSources = nextChapters.chapterData, nextSources.count > 0,
                    let nextParams = nextSources[0].params
                {

                    loadPages(chapter: nextChapters, params: nextParams, position: .next)
                }
            }

            if !didStartCurrentLoad {
                isLoadingCurrentChapter = false
                currentErrorMessage = "No page source found for this chapter."
            }

                    
        }
        else {
            isLoadingCurrentChapter = false
            currentErrorMessage = "No chapter selected."
        }
    }
    // Cancel all loadPages tasks
    private func cancelAllLoadPagesTasks() {
        for (_, task) in loadPagesTasks {
            task.cancel()
        }
        loadPagesTasks.removeAll()
        ReaderPageImageOptions.stop(&pagePrefetchers)
        ReaderPageImageOptions.stop(&backgroundPagePrefetchers)
        lastAdjacentPrefetchSignature = nil
        lastBackgroundPrefetchSignature = nil
    }
    
    // Cancel specific loadPages task
    private func cancelLoadPagesTask(for position: ChapterPosition) {
        
        loadPagesTasks[position]?.cancel()
        loadPagesTasks.removeValue(forKey: position)
    }
    
    // Setter Functions
    func setIndex(_ index: Int) {
        self.index = index
        persistCurrentPagePosition(page: index)
    }

    func setCurrChapter(_ currChapter: [PageData]) {
        isLoadingCurrentChapter = false
        currentErrorMessage = nil
        self.currChapter = currChapter
        generateCurrControllers()
        // Restore saved page position
        if mangaId != 0, let chapter = selectedChapter {
            let saved = MangaReadingProgressManager.shared.pagePosition(
                mangaId: mangaId,
                chapterNumber: chapter.chapterNumber
            )
            if saved > 0, saved < currChapter.count {
                self.index = saved
                self.changeIndex = true
                ReaderLogger.shared.log(
                    "Restoring reader page=\(saved + 1)/\(currChapter.count) chapter=\(chapter.chapterNumber)",
                    type: "ReaderProgress"
                )
            }
            persistCurrentPagePosition(page: self.index)
        }
        if readingMode == .WEBTOON {
            ReaderPageImageOptions.stop(&pagePrefetchers)
            ReaderPageImageOptions.stop(&backgroundPagePrefetchers)
            lastAdjacentPrefetchSignature = nil
            lastBackgroundPrefetchSignature = nil
        } else {
            preloadAdjacentPages()
            preloadRemainingCurrentChapterPages()
        }
    }
    
    func setPrevChapter(_ prevChapter: [PageData]) {
        self.prevChapter = prevChapter
        generatePrevControllers()
    }
    
    func setNextChapter(_ nextChapter: [PageData]) {
        self.nextChapter = nextChapter
        generateNextControllers()
    }
    func generateCurrControllers()
    {
        currControllers = currChapter.map { page in
            if !page.isTransition, (page.urlString != nil || page.imageData != nil) {
                return UIHostingController(rootView: AnyView(ZoomablePageView(page: page)))
            }
            return UIHostingController(rootView: AnyView(page.body))
        }
        if let selectedChapter = selectedChapter{
            let transistionView: any View = chapterView(page: PageData(content: "CHAPTER_END"), index: selectedChapter.chapterNumber)
            currControllers = currControllers! + [UIHostingController(rootView: AnyView( transistionView))]
        }
       
    }
    func generatePrevControllers()
    {
        prevControllers = prevChapter.map { page in
            if !page.isTransition, (page.urlString != nil || page.imageData != nil) {
                return UIHostingController(rootView: AnyView(ZoomablePageView(page: page)))
            }
            return UIHostingController(rootView: AnyView(page.body))
        }
        if let selectedChapter = selectedChapter, let chapters = chapters, selectedChapter.idx > 0 {
            let transistionView: any View = chapterView(page: PageData(content: "CHAPTER_END"), index: chapters[selectedChapter.idx-1].chapterNumber)
            prevControllers = prevControllers! + [UIHostingController(rootView: AnyView( transistionView))]
            
        }
    }
    func generateNextControllers()
    {
        nextControllers = nextChapter.map { page in
            if !page.isTransition, (page.urlString != nil || page.imageData != nil) {
                return UIHostingController(rootView: AnyView(ZoomablePageView(page: page)))
            }
            return UIHostingController(rootView: AnyView(page.body))
        }
        if let selectedChapter = selectedChapter, let chapters = chapters, selectedChapter.idx < chapters.count - 1 {
            let transistionView: any View = chapterView(page: PageData(content: "CHAPTER_END"), index: chapters[selectedChapter.idx + 1].chapterNumber)
            nextControllers = nextControllers! + [UIHostingController(rootView: AnyView( transistionView))]
            
        }
    }
    func shiftLeft() {
        // Cancel next chapter loading since it's no longer needed
        cancelLoadPagesTask(for: .next)
        if let currChapter = selectedChapter, currChapter.idx == 0
        {
            ReaderLogger.shared.log("No previous chapter available", type: "ReaderDebug")
            return
        }
        
        // Mark the chapter we're leaving as read
        if let chapter = selectedChapter, mangaId != 0 {
            markChapterRead(chapter)
        }
        
        //shift Controllers
        nextControllers = currControllers
        currControllers = prevControllers
        prevControllers = nil
        
        // Shift chapters (this will trigger didSet and invalidate controllers)
        nextChapter = currChapter
        currChapter = prevChapter
        prevChapter = []
        
        // Now shift the controllers to maintain references
        // What was "current" becomes "next"
        // What was "previous" becomes "current"
        // "Previous" becomes empty
        shiftChapterLeft()
        index = currChapter.count - 1
        ReaderLogger.shared.log("Shifted left; controllers moved", type: "ReaderProgress")
    }
    
    func shiftRight() {
        // Cancel prev chapter loading since it's no longer needed
        cancelLoadPagesTask(for: .prev)
        if let currChapter = selectedChapter,
            let chapters = chapters,
            currChapter.idx == chapters.count - 1
        {
            ReaderLogger.shared.log("No next chapter available", type: "ReaderDebug")
            return
        }
        
        // Mark the chapter we're leaving as read
        if let chapter = selectedChapter, mangaId != 0 {
            markChapterRead(chapter)
        }
        
        prevControllers = currControllers
        currControllers = nextControllers
        nextControllers = nil
        // Shift chapters (this will trigger didSet and invalidate controllers)
        prevChapter = currChapter
        currChapter = nextChapter
        nextChapter = []
        
        
        // What was "current" becomes "previous"
        // What was "next" becomes "current"
        // "Next" becomes empty

        index = 0
        shiftChapterRight()

        ReaderLogger.shared.log("Shifted right; controllers moved", type: "ReaderProgress")
    }

    private func persistCurrentPagePosition(page: Int) {
        guard mangaId != 0, let chapter = selectedChapter else { return }
        MangaReadingProgressManager.shared.savePagePosition(
            mangaId: mangaId,
            chapterNumber: chapter.chapterNumber,
            page: page,
            pageCount: currChapter.count,
            mangaTitle: mangaTitle,
            coverURL: mangaCoverURL,
            format: mangaFormat,
            totalChapters: totalChapters,
            latestChapterNumbers: latestChapterNumbers,
            route: mangaRoute,
            trackerAniListId: trackerAniListId,
            trackerMALId: trackerMALId,
            readThreshold: readerReadThreshold
        )
    }

    private var readerReadThreshold: Double {
        let raw = UserDefaults.standard.object(forKey: "readerReadThresholdPercent") as? Double ?? 80
        return max(50, min(raw, 100)) / 100
    }

    private func markChapterRead(_ chapter: Chapter) {
        MangaReadingProgressManager.shared.markChapterRead(
            mangaId: mangaId,
            chapterNumber: chapter.chapterNumber,
            mangaTitle: mangaTitle,
            coverURL: mangaCoverURL,
            format: mangaFormat,
            totalChapters: totalChapters,
            latestChapterNumbers: latestChapterNumbers,
            route: mangaRoute,
            trackerAniListId: trackerAniListId,
            trackerMALId: trackerMALId
        )
    }
    
    func getIndex() -> Int {
        return index
    }
    
    func findControllers(currView: UIViewController) -> Bool {
        if let currControllers = currControllers, currControllers.contains(currView) {
            return true
        }
        if let prevControllers = prevControllers, prevControllers.contains(currView) {
            return true
        }
        if let nextControllers = nextControllers, nextControllers.contains(currView) {
            return true
        }
        return false
    }
    func fetchTask(bool: Bool, completion: @escaping (() -> Void ) = {})
    {
        currTask?.cancel()
        if bool {
            // Also cancel the actual loading task for next
            cancelLoadPagesTask(for: .next)
            currTask = Task
            {
                 fetchNext(completion: completion)
            }

            
        }
        else
        {            // Also cancel the actual loading task for prev
            cancelLoadPagesTask(for: .prev)
            currTask = Task
            {
                fetchPrev(completion: completion)
            }


        }
    }
  
    
    func loadPages(chapter: Chapter? = nil, params: Any, position: ChapterPosition, completion: @escaping () -> Void = {}){
        // Cancel any existing task for this position
        cancelLoadPagesTask(for: position)
        
        // Create new task and store it
        loadPagesTasks[position] = Task { @MainActor in
            do {
                // Check for cancellation before starting
                try Task.checkCancellation()
                
                ReaderLogger.shared.log("Loading chapter position=\(position)", type: "Reader")
                let loadStartedAt = Date()

                let pages: [PageData]
                let loadSource: String
                if let route = self.mangaRoute,
                   let chapter,
                   let localPages = ReaderDownloadManager.shared.pages(for: route, chapterNumber: chapter.chapterNumber) {
                    pages = localPages
                    loadSource = "download"
                    ReaderLogger.shared.log("Loaded downloaded chapter position=\(position) pages=\(localPages.count)", type: "ReaderDownload")
                } else if let payload = params as? ReaderDownloadedChapterPayload {
                    if let localPages = ReaderDownloadManager.shared.pages(for: payload.route, chapterNumber: payload.chapterNumber) {
                        pages = localPages
                        loadSource = "downloadPayload"
                        ReaderLogger.shared.log("Loaded downloaded chapter payload position=\(position) pages=\(localPages.count)", type: "ReaderDownload")
                    } else {
                        throw NSError(domain: "ReaderDownload", code: 404, userInfo: [NSLocalizedDescriptionKey: "Downloaded chapter files are missing."])
                    }
                } else if let payload = params as? AidokuChapterPayload {
                    loadSource = "aidoku"
                    pages = try await AidokuSourceManager.shared.pageList(
                        sourceId: payload.sourceId,
                        manga: payload.manga,
                        chapter: payload.chapter
                    )
                } else {
                    loadSource = "legacy"
                    let result = await withCheckedContinuation { continuation in
                        self.kanzen.extractImages(params: params) { result in
                            continuation.resume(returning: result)
                        }
                    } ?? []
                    pages = result.map { PageData(content: $0) }
                }
                
                // Check for cancellation after network call
                try Task.checkCancellation()
                let loadElapsedMs = Int(Date().timeIntervalSince(loadStartedAt) * 1000)
                let urlCount = pages.filter { $0.urlString != nil }.count
                let dataCount = pages.filter { $0.imageData != nil }.count
                let textCount = pages.filter { $0.textContent != nil }.count
                if position == .curr || loadElapsedMs >= 500 {
                    ReaderLogger.shared.log(
                        "Chapter pages loaded position=\(position) source=\(loadSource) elapsedMs=\(loadElapsedMs) pages=\(pages.count) url=\(urlCount) data=\(dataCount) text=\(textCount)",
                        type: "ReaderPerf"
                    )
                }
                
       
                
                if !pages.isEmpty {
                    // Check for cancellation before updating UI
                    try Task.checkCancellation()
                    
                    // Update UI on main thread (already on MainActor)
                    switch position
                    {
                    case .prev:
                        self.setPrevChapter(pages)
                        
                    case .next:
                        self.setNextChapter(pages)
                        
                        
                    case .curr:
                        self.setCurrChapter(pages)


                    }
                    ReaderLogger.shared.log("Loaded chapter position=\(position) pages=\(pages.count)", type: "Reader")
                    completion()
                } else if position == .curr {
                    self.isLoadingCurrentChapter = false
                    self.currentErrorMessage = "No pages found for this chapter."
                    completion()
                } else {
                    completion()
                }
                
                // Remove completed task from storage
                self.loadPagesTasks.removeValue(forKey: position)
                
            } catch {
                if error is CancellationError {
                    ReaderLogger.shared.log("Loading chapter position=\(position) cancelled", type: "ReaderDebug")
                } else {
                    ReaderLogger.shared.log("Error loading chapter position=\(position): \(error.localizedDescription)", type: "Error")
                    if position == .curr {
                        self.isLoadingCurrentChapter = false
                        self.currentErrorMessage = error.localizedDescription
                    }
                }
                // Remove failed/cancelled task from storage
                self.loadPagesTasks.removeValue(forKey: position)
            }
        }
    }
    // shiftCurrChapter
    func shiftChapterLeft()
    {
        if let currChapter = selectedChapter, let chapters = chapters
        {
            let idx = currChapter.idx
            if idx > 0
            {
                selectedChapter = chapters[idx - 1]
                ReaderLogger.shared.log("Shifted to previous chapter", type: "ReaderProgress")
            }
        }
    }
    func shiftChapterRight()
    {
        if let currChapter = selectedChapter, let chapters = chapters
        {
            let idx = currChapter.idx
            if idx < chapters.count - 1
            {
                selectedChapter = chapters[idx + 1]
                ReaderLogger.shared.log("Shifted to next chapter", type: "ReaderProgress")
            }
        }
    }

    func goToPreviousChapter() {
        guard let chapter = selectedChapter, chapter.idx > 0 else { return }
        if mangaId != 0 {
            markChapterRead(chapter)
        }
        selectedChapter = chapters?[chapter.idx - 1]
        resetState()
    }

    func goToNextChapter() {
        guard let chapter = selectedChapter, let chapters = chapters, chapter.idx < chapters.count - 1 else { return }
        if mangaId != 0 {
            markChapterRead(chapter)
        }
        selectedChapter = chapters[chapter.idx + 1]
        resetState()
    }

    func fetchPrev(completion: @escaping () -> Void = {})
    {
        ReaderLogger.shared.log("Prefetch previous chapter requested", type: "ReaderDebug")
        if let selectedChapter = selectedChapter, let chapters = chapters {
            let idx = selectedChapter.idx
            if idx > 0 {
                let prevChapter = chapters[idx - 1]
                if let prevSources = prevChapter.chapterData, prevSources.count > 0,
                    let prevParams = prevSources[0].params
                {
                    loadPages(chapter: prevChapter, params: prevParams, position: .prev,completion: completion)
                    
                }
                
            }
        }
    }
    func fetchNext(completion: @escaping () -> Void = {})
    {        if let selectedChapter = selectedChapter, let chapters = chapters {
        let idx = selectedChapter.idx
        if idx < chapters.count - 1 {
            let nextChapters = chapters[idx + 1]
            if let nextSources = nextChapters.chapterData, nextSources.count > 0,
                let nextParams = nextSources[0].params
            {
                loadPages(chapter: nextChapters, params: nextParams, position: .next,completion: completion)
            }
            
        }
    }
        
    }
    
    func preloadAdjacentPages()
    {
        guard !currChapter.isEmpty else { return }

        let anchor = max(0, (index / 4) * 4)
        let lowerBound = max(anchor - 2, 0)
        let upperBound = min(anchor + 12, currChapter.count - 1)
        var pagesToPrefetch: [PageData] = []

        for pageIndex in lowerBound...upperBound where pageIndex != index {
            pagesToPrefetch.append(currChapter[pageIndex])
        }

        if index >= currChapter.count - 3 {
            for page in nextChapter.prefix(4) {
                pagesToPrefetch.append(page)
            }
        }

        if index <= 2 {
            for page in prevChapter.suffix(4) {
                pagesToPrefetch.append(page)
            }
        }

        let signature = pagesToPrefetch.map(\.cacheKey).joined(separator: "|")
        guard signature != lastAdjacentPrefetchSignature else { return }
        lastAdjacentPrefetchSignature = signature

        ReaderPageImageOptions.stop(&pagePrefetchers)
        pagePrefetchers = ReaderPageImageOptions.makePrefetchers(for: pagesToPrefetch)
        ReaderPageImageOptions.start(pagePrefetchers)
        
    }

    func preloadRemainingCurrentChapterPages() {
        let signature = currChapter.map(\.cacheKey).joined(separator: "|")
        guard signature != lastBackgroundPrefetchSignature else { return }
        lastBackgroundPrefetchSignature = signature

        ReaderPageImageOptions.stop(&backgroundPagePrefetchers)
        backgroundPagePrefetchers = ReaderPageImageOptions.makePrefetchers(for: currChapter)
        ReaderPageImageOptions.start(backgroundPagePrefetchers)
        ReaderLogger.shared.log("Background prefetching \(backgroundPagePrefetchers.count) reader page groups", type: "ReaderProgress")
    }
    func getNextChapterIdx() -> String{
        if let idx = selectedChapter?.idx, let currChapters = chapters, idx + 1 < currChapters.count  {
            return currChapters[idx+1].chapterNumber
            
        }
        return "0"
        
    }
    func getPrevChapterIdx() -> String
    {
        if let idx = selectedChapter?.idx, let currChapters = chapters, idx - 1  >= 0 {
            return currChapters[idx - 1].chapterNumber
            
        }
        return "0"
    }
}
