package dev.soupy.eclipse.android.core.model

import kotlinx.serialization.Serializable

@Serializable
enum class AndroidParityStatus {
    IMPLEMENTED,
    NON_PORTABLE,
    PLATFORM_ONLY,
}

@Serializable
data class AndroidParityChecklistItem(
    val id: String,
    val title: String,
    val iosSource: String,
    val androidOwner: String,
    val status: AndroidParityStatus,
    val requiredBehaviors: List<String>,
    val androidEvidence: List<String>,
    val verification: List<String>,
    val edgeCases: List<String> = emptyList(),
)

object AndroidParityChecklist {
    val items: List<AndroidParityChecklistItem> = listOf(
        implemented(
            id = "media-home-catalogs",
            title = "Home catalogs and ordering",
            iosSource = "Eclipse/HomeViewModel.swift, Eclipse/Models/CatalogModels.swift",
            androidOwner = "HomeRepository, CatalogSettingsStore, BackupCatalog",
            requiredBehaviors = listOf(
                "Use iOS default catalog IDs, ordering, display styles, and enabled state.",
                "Merge restored catalog rows with new defaults without dropping user ordering.",
            ),
            androidEvidence = listOf(
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
                "android/core/model/src/test/kotlin/dev/soupy/eclipse/android/core/model/ParityModelsTest.kt",
            ),
            verification = listOf("catalogMergePreservesSavedRowsAndAddsIosDefaults"),
            edgeCases = listOf("Unknown future catalog IDs remain in restored data until Android can render them."),
        ),
        implemented(
            id = "media-hero-atmosphere",
            title = "Hero and atmosphere settings",
            iosSource = "Eclipse/HomeView.swift, Eclipse/SettingsView.swift",
            androidOwner = "SettingsStore, SettingsScreen, HomeRoute",
            requiredBehaviors = listOf(
                "Persist hero catalog and behavior defaults.",
                "Persist atmosphere style, solid source, and custom color.",
            ),
            androidEvidence = listOf(
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/SettingsStore.kt",
                "android/feature/settings/src/main/kotlin/dev/soupy/eclipse/android/feature/settings/SettingsScreen.kt",
            ),
            verification = listOf("BackupDocumentTest.decodesModernIosBackupShape"),
            edgeCases = listOf("Invalid raw enum values sanitize back to iOS defaults."),
        ),
        implemented(
            id = "media-search-ranking-caps",
            title = "Search ranking, result caps, and filters",
            iosSource = "Eclipse/SearchView.swift, Eclipse/ServicesResultsSheet.swift",
            androidOwner = "SearchRepository, StreamResolutionRepository, SimilarityAlgorithm",
            requiredBehaviors = listOf(
                "Keep bounded search/service result sets so large providers do not overload UI.",
                "Use persisted similarity algorithm, horror filter, quality threshold, and source ordering.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/SearchRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/StreamResolutionRepository.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/ParityModels.kt",
            ),
            verification = listOf("StreamResolutionRepositoryEpisodeMatchingTest"),
            edgeCases = listOf("Services that return too many low-confidence rows are capped after scoring."),
        ),
        implemented(
            id = "media-detail-layout",
            title = "Detail ordering, hidden sections, ratings, notes, and collections",
            iosSource = "Eclipse/MediaDetailView.swift, Eclipse/CollectionModels.swift",
            androidOwner = "DetailRepository, LibraryRepository, SettingsStore, BackupModels",
            requiredBehaviors = listOf(
                "Persist iOS detail element order and hidden element settings.",
                "Round-trip ratings, rating notes, library collection memberships, and progress data.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/DetailRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/LibraryRepository.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
            ),
            verification = listOf("BackupDocumentTest.decodesModernIosBackupShape"),
            edgeCases = listOf("Unknown backup sections are preserved for future iOS/Android versions."),
        ),
        implemented(
            id = "schedule-settings",
            title = "Schedule modes and local time",
            iosSource = "Eclipse/ScheduleView.swift, Eclipse/SettingsView.swift",
            androidOwner = "ScheduleRepository, SettingsStore, SettingsScreen",
            requiredBehaviors = listOf(
                "Persist show schedule tab, local time, classic UI, and default schedule mode.",
                "Sanitize restored schedule mode values to known iOS-compatible modes.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/ScheduleRepository.kt",
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/SettingsStore.kt",
            ),
            verification = listOf("BackupDocumentTest.decodesModernIosBackupShape"),
        ),
        implemented(
            id = "tmdb-language-cache-release",
            title = "TMDB language, cache, and release prompts",
            iosSource = "Eclipse/TMDBClient.swift, Eclipse/CacheManager.swift, Eclipse/GitHubReleaseChecker.swift",
            androidOwner = "SettingsStore, CacheRepository, ReleaseRepository, AndroidSettingsViewModel",
            requiredBehaviors = listOf(
                "Persist TMDB language, cache thresholds, and auto-clear settings.",
                "Persist GitHub release auto-check, latest version, URL, and pending prompt state.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/CacheRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/ReleaseRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/ui/settings/AndroidSettingsViewModel.kt",
            ),
            verification = listOf("gradlew.bat testDebugUnitTest", "emulator settings smoke"),
            edgeCases = listOf("Release prompts are cached so the same version is not repeatedly surfaced."),
        ),
        implemented(
            id = "services-lifecycle",
            title = "Service install, update, enable, order, and sandboxing",
            iosSource = "Eclipse/JSController.swift, Eclipse/ServiceManager.swift",
            androidOwner = "ServicesRepository, SettingsStore, LoggerStore",
            requiredBehaviors = listOf(
                "Install, update, enable, disable, and order services like iOS.",
                "Run service fetches through the sandboxed Android JS/WebView path with tagged logs.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/ServicesRepository.kt",
                "android/core/js/src/main/kotlin/dev/soupy/eclipse/android/core/js/AndroidJsRuntime.kt",
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/LoggerStore.kt",
            ),
            verification = listOf("emulator services smoke", "AppLogSnapshot unit coverage"),
            edgeCases = listOf("Analytics/tracking hosts are blocked during service runtime fetches."),
        ),
        implemented(
            id = "services-progressive-resolution",
            title = "Progressive search, detail, episode, and stream resolution",
            iosSource = "Eclipse/ServiceManager.swift, Eclipse/StreamResolver.swift",
            androidOwner = "StreamResolutionRepository, SourceHealthRepository",
            requiredBehaviors = listOf(
                "Resolve services progressively from search through details, episodes, and streams.",
                "Record source health on playback success/failure and prefer healthy sources.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/StreamResolutionRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/SourceHealthRepository.kt",
            ),
            verification = listOf("StreamResolutionRepositoryEpisodeMatchingTest"),
            edgeCases = listOf("Failures during playback are tagged separately from provider search failures."),
        ),
        implemented(
            id = "stremio-addons",
            title = "Stremio manifest, catalog, Kitsu/anime IDs, and subtitle addons",
            iosSource = "Eclipse/StremioAddonManager.swift, Eclipse/StremioClient.swift",
            androidOwner = "StremioRepository, StreamResolutionRepository, BackupModels",
            requiredBehaviors = listOf(
                "Validate addon manifests and preserve addon lifecycle in backups.",
                "Use anime/Kitsu IDs and catalog fallback scoring for anime stream discovery.",
                "Support subtitle addons and OpenSubtitles fallback settings.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/StremioRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/StreamResolutionRepository.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
            ),
            verification = listOf("Stremio and stream resolution unit tests", "emulator Stremio smoke"),
            edgeCases = listOf("Torrent-only streams are rejected for Android in-app playback."),
        ),
        implemented(
            id = "player-backends",
            title = "MPV default, Media3 fallback, and legacy VLC migration",
            iosSource = "Eclipse/PlayerViewController.swift, Eclipse/MPVNativeRenderer.swift",
            androidOwner = "core:mpv, core:player, SettingsStore, BackupModels",
            requiredBehaviors = listOf(
                "Default embedded Android playback to MPV.",
                "Keep Normal/Media3 as fallback/debug backend.",
                "Decode old VLC settings and backups as MPV without shipping VLC runtime code.",
            ),
            androidEvidence = listOf(
                "android/core/mpv/src/main/kotlin/dev/soupy/eclipse/android/core/mpv/MpvPlayerController.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/PlaybackModels.kt",
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/SettingsStore.kt",
                "android/core/mpv/THIRD_PARTY_MPV_ANDROID.md",
            ),
            verification = listOf("PlayerSourceTest", "no libvlc Gradle/runtime scan"),
            edgeCases = listOf("InAppPlayer.VLC remains only as a deprecated decode alias."),
        ),
        implemented(
            id = "player-stream-transport",
            title = "Headers, redirects, HLS, direct HTTP, and local files",
            iosSource = "Eclipse/MPVHeaderProxy.swift, Eclipse/HLSDownloader.swift",
            androidOwner = "PlayerHeaderProxy, MpvPlayerController, DownloadsRepository",
            requiredBehaviors = listOf(
                "Use a neutral player header proxy for custom headers, cookies, redirects, subtitles, and HLS.",
                "Play direct HTTP(S), HLS master/variant playlists, and app-scoped local downloads.",
            ),
            androidEvidence = listOf(
                "android/core/player/src/main/kotlin/dev/soupy/eclipse/android/core/player/PlayerHeaderProxy.kt",
                "android/core/mpv/src/main/kotlin/dev/soupy/eclipse/android/core/mpv/MpvPlayerController.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/DownloadsRepository.kt",
            ),
            verification = listOf("emulator MPV HLS/header/local-file smoke"),
            edgeCases = listOf("Header proxy is enabled from neutral player settings while reading legacy preference keys."),
        ),
        implemented(
            id = "player-subtitles-tracks-audio",
            title = "Subtitles, track switching, and anime audio defaults",
            iosSource = "Eclipse/PlayerSettings.swift, Eclipse/MPVNativeRenderer.swift",
            androidOwner = "PlaybackSettingsSnapshot, MpvPlayerController, SettingsScreen",
            requiredBehaviors = listOf(
                "Apply ASS, SRT, VTT, external subtitle URLs, and subtitle styling settings.",
                "Expose audio/subtitle track switching and preferred anime audio language.",
            ),
            androidEvidence = listOf(
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/ParityInterfaces.kt",
                "android/core/mpv/src/main/kotlin/dev/soupy/eclipse/android/core/mpv/MpvPlayerController.kt",
                "android/feature/settings/src/main/kotlin/dev/soupy/eclipse/android/feature/settings/SettingsScreen.kt",
            ),
            verification = listOf("emulator MPV subtitle and track smoke"),
            edgeCases = listOf("OpenSubtitles auto-fallback can be disabled independently."),
        ),
        implemented(
            id = "player-progress-skip-next",
            title = "Resume, progress, finish sync, skips, next episode, and episode browser",
            iosSource = "Eclipse/PlayerViewController.swift, Eclipse/AniSkip.swift, Eclipse/TheIntroDB.swift",
            androidOwner = "EclipsePlayerSurface, ProgressRepository, TrackerRepository, SettingsStore",
            requiredBehaviors = listOf(
                "Resume playback, write progress, detect completion, and trigger tracker sync thresholds.",
                "Support AniSkip, IntroDB, TheIntroDB, 85s skip, next episode, and episode browser controls.",
            ),
            androidEvidence = listOf(
                "android/core/player/src/main/kotlin/dev/soupy/eclipse/android/core/player/EclipsePlayerSurface.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/ProgressRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/TrackerRepository.kt",
            ),
            verification = listOf("emulator playback end-of-episode smoke", "tracker threshold unit tests"),
            edgeCases = listOf("Skip controls stay visible only when the matching source/segment evidence exists."),
        ),
        implemented(
            id = "player-platform-controls",
            title = "PiP, rotation, gestures, and screen-awake behavior",
            iosSource = "Eclipse/PlayerViewController.swift, UIKit PiP/idle timer behavior",
            androidOwner = "EclipsePlayerSurface, SettingsScreen, PlaybackSettingsSnapshot",
            requiredBehaviors = listOf(
                "Keep the screen awake only while playback is active.",
                "Support rotation lock, PiP setting, brightness/volume gestures, two-finger play/pause, and double-tap seek.",
            ),
            androidEvidence = listOf(
                "android/core/player/src/main/kotlin/dev/soupy/eclipse/android/core/player/EclipsePlayerSurface.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/ParityInterfaces.kt",
                "android/feature/settings/src/main/kotlin/dev/soupy/eclipse/android/feature/settings/SettingsScreen.kt",
            ),
            verification = listOf("emulator PiP/rotation/gesture smoke"),
            edgeCases = listOf("Android PiP uses platform APIs and is not expected to mirror UIKit implementation details."),
        ),
        implemented(
            id = "media-downloads",
            title = "Media downloads, HLS packaging, and offline restore",
            iosSource = "Eclipse/DownloadManager.swift, Eclipse/HLSDownloader.swift",
            androidOwner = "DownloadsRepository, DownloadWorker, DownloadsScreen",
            requiredBehaviors = listOf(
                "Keep media downloads in app-scoped storage without broad storage permissions.",
                "Support pause, resume, delete, HLS packaging, offline restore, and prefer-downloaded playback.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/DownloadsRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/DownloadWorker.kt",
                "android/feature/downloads/src/main/kotlin/dev/soupy/eclipse/android/feature/downloads/DownloadsScreen.kt",
            ),
            verification = listOf("emulator downloads smoke"),
            edgeCases = listOf("Broken partial downloads can be deleted without leaving orphaned UI state."),
        ),
        implemented(
            id = "trackers",
            title = "Tracker auth, progress, ratings, and tools",
            iosSource = "Eclipse/TrackerManager.swift, Eclipse/TrackersSettingsView.swift",
            androidOwner = "TrackerRepository, AndroidSettingsViewModel, BackupModels",
            requiredBehaviors = listOf(
                "Support AniList, MyAnimeList, and Trakt account state and OAuth/manual connection state.",
                "Sync progress, ratings, notes, thresholds, imports, and fill/port tools.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/TrackerRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/ui/settings/AndroidSettingsViewModel.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
            ),
            verification = listOf("tracker sync unit tests", "emulator tracker settings smoke"),
            edgeCases = listOf("Manga progress sync is separated from media progress sync."),
        ),
        implemented(
            id = "backup-round-trip",
            title = "Backup restore, unknown keys, settings, and legacy player migration",
            iosSource = "Eclipse/BackupManager.swift, Eclipse/BackupManagementView.swift",
            androidOwner = "BackupRepository, BackupModels, SettingsStore",
            requiredBehaviors = listOf(
                "Decode modern iOS backup keys Android supports and preserve unknown keys.",
                "Write neutral MPV/player keys while still writing and reading legacy VLC keys.",
                "Migrate legacy VLC in-app player selections to MPV.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/BackupRepository.kt",
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/SettingsStore.kt",
            ),
            verification = listOf("BackupDocumentTest", "BackupDocument unknown-key round trip"),
            edgeCases = listOf("Unsupported future iOS keys are preserved during export."),
        ),
        implemented(
            id = "reader-portable-sources",
            title = "Portable reader source list, install, update, and health",
            iosSource = "Kanzen module reader, Aidoku source list state",
            androidOwner = "KanzenRepository, SourceHealthRepository, AndroidMangaViewModel, AndroidNovelViewModel",
            requiredBehaviors = listOf(
                "Use portable Kanzen/WebView JS modules for Android reader source execution.",
                "Expose restored source list/install state and source health/log snapshots.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/KanzenRepository.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/ui/manga/AndroidMangaViewModel.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/SourceHealthRepository.kt",
            ),
            verification = listOf("ReaderCacheRepositoryTest", "emulator Kanzen source smoke"),
            edgeCases = listOf("Sources restored from iOS Aidoku state are visible even if they are unavailable on Android."),
        ),
        nonPortable(
            id = "reader-native-aidoku-runner",
            title = "Native AidokuRunner package execution",
            iosSource = "AidokuSourceManager, AidokuRunner Swift packages",
            androidOwner = "BackupAidokuState, restored unavailable source UI",
            requiredBehaviors = listOf(
                "Preserve AidokuRunner source state from iOS backups.",
                "Mark Swift AidokuRunner-only packages unavailable instead of pretending Android can execute them.",
            ),
            androidEvidence = listOf(
                "android/core/model/src/main/kotlin/dev/soupy/eclipse/android/core/model/BackupModels.kt",
                "android/core/model/src/test/kotlin/dev/soupy/eclipse/android/core/model/ParityModelsTest.kt",
            ),
            verification = listOf("restoredAidokuSourcesAreExplicitlyNonPortable"),
            edgeCases = listOf("Portable Kanzen/WebView packages remain executable on Android."),
        ),
        implemented(
            id = "reader-home-search-detail",
            title = "Manga/novel home, search, detail, chapters, and pages",
            iosSource = "Kanzen/MangaHomeViewModel.swift, Kanzen/AidokuMangaDetailView.swift",
            androidOwner = "AndroidMangaViewModel, AndroidNovelViewModel, MangaRepository, NovelRepository",
            requiredBehaviors = listOf(
                "Support manga/novel home, search, details, chapters, page loading, collections, and progress.",
                "Keep Android reader behavior on the shared WebView module runtime.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/ui/manga/AndroidMangaViewModel.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/ui/novel/AndroidNovelViewModel.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/MangaRepository.kt",
            ),
            verification = listOf("emulator manga/novel smoke", "reader progress unit tests"),
            edgeCases = listOf("Source runtime errors are logged and shown without crashing reader screens."),
        ),
        implemented(
            id = "reader-downloads-cache",
            title = "Reader downloads, cache, progress, and offline restore",
            iosSource = "Kanzen/ReaderDownloadManager.swift, Kanzen reader cache",
            androidOwner = "ReaderCacheRepository, AndroidMangaViewModel, BackupRepository",
            requiredBehaviors = listOf(
                "Store reader downloads in app-scoped storage.",
                "Round-trip reader downloads/progress through backup and restore.",
                "Support delete/offline restore flows for manga and novel content.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/ReaderCacheRepository.kt",
                "android/app/src/test/kotlin/dev/soupy/eclipse/android/data/ReaderCacheRepositoryTest.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/BackupRepository.kt",
            ),
            verification = listOf("ReaderCacheRepositoryTest", "emulator reader downloads smoke"),
            edgeCases = listOf("Missing cached page files do not block restoring the rest of the backup."),
        ),
        implemented(
            id = "logs-export-clear",
            title = "Media logs, reader logs, export, and clear",
            iosSource = "Eclipse/Logger.swift, Kanzen reader logger",
            androidOwner = "LoggerStore, LoggerRepository, SettingsScreen",
            requiredBehaviors = listOf(
                "Expose combined media/service/reader logs in settings.",
                "Support refresh, export-through-backup, and clear flows.",
            ),
            androidEvidence = listOf(
                "android/core/storage/src/main/kotlin/dev/soupy/eclipse/android/core/storage/LoggerStore.kt",
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/data/LoggerRepository.kt",
                "android/feature/settings/src/main/kotlin/dev/soupy/eclipse/android/feature/settings/SettingsScreen.kt",
            ),
            verification = listOf("appLogSnapshotPrependsAndCapsExportedRows", "BackupDocumentTest"),
            edgeCases = listOf("Log snapshots are optional in backup so old backups still decode."),
        ),
        platformOnly(
            id = "platform-ios-rendering-apis",
            title = "iOS-only rendering and OS APIs",
            iosSource = "SwiftUI/UIKit rendering, iOS PiP implementation details",
            androidOwner = "Compose, Android WebView, Android PiP",
            requiredBehaviors = listOf(
                "Use Android-native equivalents for UI, PiP, WebView, and emulator/device behavior.",
                "Do not edit iOS runtime code for Android-only parity except test fixtures.",
            ),
            androidEvidence = listOf(
                "android/app/src/main/kotlin/dev/soupy/eclipse/android/EclipseAndroidApp.kt",
                "android/core/player/src/main/kotlin/dev/soupy/eclipse/android/core/player/EclipsePlayerSurface.kt",
            ),
            verification = listOf("emulator acceptance smoke"),
            edgeCases = listOf("UIKit-specific visual effects are not portable requirements on Android."),
        ),
    )

    val uncheckedItems: List<AndroidParityChecklistItem>
        get() = items.filterNot {
            it.status == AndroidParityStatus.IMPLEMENTED ||
                it.status == AndroidParityStatus.NON_PORTABLE ||
                it.status == AndroidParityStatus.PLATFORM_ONLY
        }

    val implementedItems: List<AndroidParityChecklistItem>
        get() = items.filter { it.status == AndroidParityStatus.IMPLEMENTED }

    val nonPortableItems: List<AndroidParityChecklistItem>
        get() = items.filter { it.status == AndroidParityStatus.NON_PORTABLE }

    private fun implemented(
        id: String,
        title: String,
        iosSource: String,
        androidOwner: String,
        requiredBehaviors: List<String>,
        androidEvidence: List<String>,
        verification: List<String>,
        edgeCases: List<String> = emptyList(),
    ) = AndroidParityChecklistItem(
        id = id,
        title = title,
        iosSource = iosSource,
        androidOwner = androidOwner,
        status = AndroidParityStatus.IMPLEMENTED,
        requiredBehaviors = requiredBehaviors,
        androidEvidence = androidEvidence,
        verification = verification,
        edgeCases = edgeCases,
    )

    private fun nonPortable(
        id: String,
        title: String,
        iosSource: String,
        androidOwner: String,
        requiredBehaviors: List<String>,
        androidEvidence: List<String>,
        verification: List<String>,
        edgeCases: List<String> = emptyList(),
    ) = AndroidParityChecklistItem(
        id = id,
        title = title,
        iosSource = iosSource,
        androidOwner = androidOwner,
        status = AndroidParityStatus.NON_PORTABLE,
        requiredBehaviors = requiredBehaviors,
        androidEvidence = androidEvidence,
        verification = verification,
        edgeCases = edgeCases,
    )

    private fun platformOnly(
        id: String,
        title: String,
        iosSource: String,
        androidOwner: String,
        requiredBehaviors: List<String>,
        androidEvidence: List<String>,
        verification: List<String>,
        edgeCases: List<String> = emptyList(),
    ) = AndroidParityChecklistItem(
        id = id,
        title = title,
        iosSource = iosSource,
        androidOwner = androidOwner,
        status = AndroidParityStatus.PLATFORM_ONLY,
        requiredBehaviors = requiredBehaviors,
        androidEvidence = androidEvidence,
        verification = verification,
        edgeCases = edgeCases,
    )
}
