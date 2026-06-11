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
    val notes: String,
)

object AndroidParityChecklist {
    val items: List<AndroidParityChecklistItem> = listOf(
        AndroidParityChecklistItem(
            id = "media-home-search-detail",
            title = "Media home, search, detail, ratings, collections, and schedule",
            iosSource = "Luna HomeViewModel/SearchView/MediaDetailView/SettingsView",
            androidOwner = "HomeRepository/SearchRepository/DetailRepository/feature screens",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android owns matching repositories, persisted catalog/detail layout settings, ratings, notes, filters, and schedule settings.",
        ),
        AndroidParityChecklistItem(
            id = "services-stremio-stream-resolution",
            title = "Services, Stremio, source health, stream scoring, and direct HTTP safety",
            iosSource = "JSController, ServiceManager, StremioAddonManager, StremioClient",
            androidOwner = "ServicesRepository/StreamResolutionRepository/StremioService/SourceHealthRepository",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android preserves service/addon lifecycle, sandboxed JS runtime, Kitsu/anime IDs, catalog fallback, subtitle fallback, and torrent rejection.",
        ),
        AndroidParityChecklistItem(
            id = "mpv-playback",
            title = "Embedded playback",
            iosSource = "PlayerViewController/MPVNativeRenderer/MPVHeaderProxy",
            androidOwner = "core:mpv/core:player",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android defaults to vendored MPV, keeps Media3 Normal fallback, maps legacy VLC settings to MPV, and uses PlayerHeaderProxy.",
        ),
        AndroidParityChecklistItem(
            id = "media-downloads",
            title = "Media downloads and offline playback",
            iosSource = "DownloadManager/HLSDownloader/DownloadsView",
            androidOwner = "DownloadsRepository/DownloadWorker/feature:downloads",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android uses app-scoped downloads, HLS packaging tests, pause/resume/delete state, and backup-safe progress.",
        ),
        AndroidParityChecklistItem(
            id = "trackers",
            title = "Trackers, auth, progress sync, ratings, and fill/port tools",
            iosSource = "TrackerManager/TrackerModels/TrackersSettingsView",
            androidOwner = "TrackerRepository/TrackerSyncClient/AndroidSettingsViewModel",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android exposes AniList, MAL, Trakt state, sync thresholds, rating sync flags, and local fill/port tools.",
        ),
        AndroidParityChecklistItem(
            id = "backup-restore",
            title = "Backup and restore",
            iosSource = "BackupManager/BackupManagementView",
            androidOwner = "BackupRepository/BackupModels/SettingsStore",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android decodes iOS backups, preserves unknown keys, restores supported sections, and re-exports supported plus preserved data.",
        ),
        AndroidParityChecklistItem(
            id = "portable-reader",
            title = "Portable manga and novel reader",
            iosSource = "Kanzen module reader, MangaHomeViewModel, ReaderDownloadManager",
            androidOwner = "MangaRepository/AndroidMangaViewModel/AndroidNovelViewModel/Kanzen WebView runtime",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android supports portable Kanzen JS modules, reader settings, progress, cache, chapters, pages, and visible restored source state.",
        ),
        AndroidParityChecklistItem(
            id = "native-aidoku-runner",
            title = "Native AidokuRunner source execution",
            iosSource = "AidokuSourceManager/AidokuRunner",
            androidOwner = "BackupModels/MangaLibrarySnapshot restored Aidoku state",
            status = AndroidParityStatus.NON_PORTABLE,
            notes = "iOS AidokuRunner packages are preserved and shown as restored unavailable Android sources; Android does not execute Swift AidokuRunner.",
        ),
        AndroidParityChecklistItem(
            id = "logs-release-cache",
            title = "Logs, release checks, cache, and settings",
            iosSource = "Logger/ReaderLogger/GitHubReleaseChecker/CacheManager/Settings",
            androidOwner = "LoggerRepository/ReleaseRepository/CacheRepository/SettingsStore",
            status = AndroidParityStatus.IMPLEMENTED,
            notes = "Android exposes media logs, cache metrics, GitHub release prompt state, and persisted settings defaults.",
        ),
        AndroidParityChecklistItem(
            id = "ios-rendering-only",
            title = "iOS-only rendering and OS APIs",
            iosSource = "UIKit/SwiftUI-only view effects, iOS PiP implementation details",
            androidOwner = "Compose/Android platform equivalents",
            status = AndroidParityStatus.PLATFORM_ONLY,
            notes = "Android uses platform-native Compose, Android PiP, WebView, and emulator/device behavior instead of iOS APIs.",
        ),
    )

    val uncheckedItems: List<AndroidParityChecklistItem>
        get() = items.filterNot {
            it.status == AndroidParityStatus.IMPLEMENTED ||
                it.status == AndroidParityStatus.NON_PORTABLE ||
                it.status == AndroidParityStatus.PLATFORM_ONLY
        }
}
