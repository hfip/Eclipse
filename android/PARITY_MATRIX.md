# Android iOS Parity Matrix

Last updated: 2026-05-27

Scope: Android should match the iOS app's user-visible behavior except embedded mpv and iOS-only platform APIs. Rows marked "Runtime smoke pending" are implemented in code and covered by build or unit checks where possible, but still need a device or emulator pass.

| Area | iOS behavior | Android status | Proof |
| --- | --- | --- | --- |
| Source resolution | Stremio and custom JS services participate in detail Play and Download flows. | Implemented, runtime smoke pending. | `StreamResolutionRepository` resolves enabled Stremio addons and custom service sources through one candidate pipeline. |
| Auto Mode source order | Auto Mode limits and orders selected sources. | Implemented. | Android filters Stremio addons and custom services by `autoModeSourceIds` and `autoModeSourceOrderIds`. |
| Auto Mode quality | Ask, Auto, Highest, 2160p, 1080p, 720p, 480p, Lowest. | Implemented. | `ServicesAutoModeQualityPreference` stores iOS raw values and drives candidate sorting/selection. |
| Manual source picking | Non Auto Mode and Ask should keep source selection visible. | Implemented, runtime smoke pending. | Manual paths leave `selectedSource` empty when multiple playable candidates exist and surface stream cards. |
| Bundled anime seasons | Auto Mode can infer absolute episodes for services that bundle seasons, manual mode still asks. | Implemented and unit-tested. | Stremio meta matching and custom service episode matching are gated by Auto Mode. |
| Stremio catalog/meta fallback | Search catalog/meta when direct stream IDs miss, including anime-local AniList/Kitsu episode IDs. | Implemented. | Android keeps direct stream lookup first, merges direct ID hits, enriches Kitsu IDs when needed, then uses catalog/meta fallback. |
| Torrent safety | Direct HTTP(S) playback only. | Implemented and unit-tested. | Torrent/magnet results are rejected and reported. |
| Header proxy | iOS VLC proxy handles HLS playlists, range requests, redirects, cookies, tokens, subtitles, and keys. | Implemented and unit-tested, runtime smoke pending. | Android VLC proxy has focused tests for playlist rewriting and header forwarding. |
| OpenSubtitles fallback | VLC can fetch subtitle fallback when provider tracks miss. | Implemented. | Stream resolution adds OpenSubtitles tracks for VLC when enabled. |
| Player episode browser | VLC player can show an episode browser button gated by setting. | Implemented, runtime smoke pending. | `showVlcEpisodeBrowserButton` flows from settings into Media3/VLC surfaces. |
| Next episode controls | Button, poster setting, threshold, and next episode switching. | Implemented and unit-tested for selection logic. | Player state passes next episode labels/posters and resolves the next episode. |
| Skip providers | AniSkip first, then TheIntroDB, then introdb.app fallback. | Implemented and unit-tested for introdb.app parsing. | `AndroidDetailViewModel` falls back after earlier providers return no segments. |
| Prefer Downloads | Play can use a completed local download when online sources are unavailable or when downloads are preferred. | Implemented, runtime smoke pending. | Detail playback checks exact completed downloads first, then latest completed show download. |
| WorkManager downloads | Queue, pause, resume, cancel, retry, and offline playback. | Implemented, runtime smoke pending. | Build passes; device validation still required for worker lifecycle. |
| Downloaded show detail | Grouped episodes, local playback, progress, delete/retry, and queue actions. | Implemented, runtime smoke pending. | Download repository and detail state expose completed local sources and actions. |
| Backup export/import | iOS backup fields should round trip without corrupting iOS backups. | Implemented and unit-tested. | New settings fields are exported/restored; unsupported mpv fields remain data-compatible no-ops. |
| Detail section customization | iOS media detail element order and hidden sections. | Implemented. | Settings persist order/hidden rows and detail rendering follows them. |
| Hero banner selection | Catalog selection plus Static, Carousel, and Launch behavior. | Implemented. | Home repository selects hero candidates from configured catalog and behavior. |
| Atmosphere visuals | Gradient/solid/custom color style controls where Android has equivalents. | Implemented. | Background consumes atmosphere style/source/color settings. |
| Tracker auth and sync | OAuth/manual tokens, refresh, imports, deep links, preview/sync flows. | Implemented, runtime smoke pending. | Unit tests cover token request/refresh body behavior; AniList library imports now use chunked `MediaListCollection`; deep links need device validation. |
| Progress and resume | Movies, shows, episodes, downloads, service-backed playback. | Implemented, runtime smoke pending. | Progress repository and player callbacks persist episode/movie progress. |
| Kanzen modules | Add/update/toggle modules, resolve details, backup-compatible records. | Implemented, runtime smoke pending. | Manga/novel repositories load modules through the runtime and preserve backup records. |
| Kanzen reader | Webtoon/paged/novel display, gestures, chapter navigation, settings, cache/preload, offline reuse. | Implemented baseline, polish and runtime smoke pending. | Reader panels include settings, next/previous, cache, preload, orientation, zoom, and auto-scroll controls. |
| Embedded mpv | iOS MPVKit playback and mpv-specific PiP. | Out of scope by request. | Android keeps mpv as external app handoff only. |
| iOS-only APIs | iOS-specific system integrations. | Platform-only. | Android uses native equivalents where available. |

## Acceptance Checklist

- `.\gradlew.bat testDebugUnitTest assembleDebug --no-daemon` passes from `android/`.
- Debug APK exists at `android/app/build/outputs/apk/debug/app-debug.apk`.
- A connected device or configured AVD still needs to smoke-test Home, Search, Detail, Stremio, custom JS services, Auto Mode, manual mode, VLC/Media3 playback, subtitles, header proxy, downloads, trackers, backup restore, and Kanzen readers.
