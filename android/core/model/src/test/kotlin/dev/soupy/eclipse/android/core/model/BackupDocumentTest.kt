package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject

class BackupDocumentTest {
    private val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Test
    fun preservesUnknownKeysAcrossDecodeAndEncode() {
        val raw = """
            {
              "version": 1,
              "createdDate": "2026-04-23T00:00:00Z",
              "accentColor": "#6D8CFF",
              "futureAndroidField": {
                "enabled": true
              }
            }
        """.trimIndent()

        val document = BackupDocument.decode(json, raw)
        val encoded = document.encode(json)

        assertEquals("#6D8CFF", document.payload.accentColor)
        assertTrue("futureAndroidField" in document.unknownKeys)
        assertTrue(encoded.contains("futureAndroidField"))
    }

    @Test
    fun decodesModernIosBackupShape() {
        val raw = """
            {
              "version": "1.0",
              "createdDate": "2026-04-23T00:00:00Z",
              "tmdbLanguage": "en-US",
              "settingsGradientColor": "#401F73",
              "selectedAppearance": "dark",
              "enableSubtitlesByDefault": true,
              "defaultSubtitleLanguage": "eng",
              "playerSubtitleAppearanceEnabled": false,
              "preferredAnimeAudioLanguage": "jpn",
              "inAppPlayer": "VLC",
              "useClassicScheduleUI": true,
              "defaultPlaybackSpeed": 1.25,
              "holdSpeedPlayer": 2.0,
              "externalPlayer": "org.videolan.vlc",
              "alwaysLandscape": true,
              "aniSkipEnabled": false,
              "introDBEnabled": false,
              "skip85sAlwaysVisible": true,
              "playerHeaderProxyEnabled": true,
              "vlcHeaderProxyEnabled": false,
              "showEpisodeBrowserButton": true,
              "playerBrightnessGestureEnabled": true,
              "playerVolumeGestureEnabled": true,
              "playerTwoFingerTapPlayPauseEnabled": false,
              "playerDoubleTapSeekEnabled": false,
              "playerDoubleTapSeekSeconds": 20.0,
              "vlcDoubleTapSeekEnabled": true,
              "vlcDoubleTapSeekSeconds": 15.0,
              "playerPictureInPictureEnabled": true,
              "vlcPiPEnabled": false,
              "playerOpenSubtitlesEnabled": false,
              "playerOpenSubtitlesAutoFallbackEnabled": true,
              "vlcOpenSubtitlesEnabled": true,
              "vlcOpenSubtitlesAutoFallbackEnabled": false,
              "playerPerformanceOverlayEnabled": true,
              "mpvForegroundFPS": 60,
              "mpvRenderBackend": "metal",
              "mpvMetalQualityProfile": "sharp",
              "mpvAppExitPictureInPictureEnabled": true,
              "skip85sEnabled": true,
              "showVLCEpisodeBrowserButton": false,
              "nextEpisodeThreshold": 0.9,
              "subtitleForegroundColor": "#FFFFFF",
              "subtitleStrokeColor": "#111111",
              "subtitleStrokeWidth": 2.5,
              "subtitleFontSize": 34.0,
              "subtitleVerticalOffset": -8.0,
              "showKanzen": true,
              "servicesAutoModeEnabled": false,
              "servicesAutoModeSourceIds": ["service:first", "stremio:https://addon.example"],
              "servicesAutoModeSourceOrderIds": ["stremio:https://addon.example", "service:first"],
              "servicesAutoModeQualityPreference": "1080p",
              "mediaDetailElementOrder": "actions,overview,details,cast,ratingNotes,episodes",
              "mediaDetailHiddenElements": "cast",
              "readerDetailElementOrder": "chapters,overview,tags,ratingNotes",
              "readerDetailHiddenElements": "tags",
              "heroBannerCatalogId": "popularAnime",
              "heroBannerBehavior": "carousel",
              "atmosphereStyle": "solid",
              "atmosphereSolidColorSource": "custom",
              "atmosphereSolidColor": "#224466",
              "readerFontFamily": "Georgia",
              "readerReadThresholdPercent": 75.0,
              "collections": [
                {
                  "id": "8F5C2E48-77FB-430F-B904-AB0FEEA420A8",
                  "name": "Bookmarks",
                  "items": [
                    {
                      "id": "movie-1",
                      "searchResult": {
                        "id": 1,
                        "title": "Example"
                      }
                    }
                  ],
                  "description": "Saved items"
                }
              ],
              "progressData": {
                "movieProgress": [
                  {
                    "id": 1,
                    "title": "Example",
                    "currentTime": 42.0,
                    "totalDuration": 100.0,
                    "isWatched": false
                  }
                ],
                "episodeProgress": [],
                "showMetadata": {}
              },
              "trackerState": {
                "accounts": [
                  {
                    "service": "anilist",
                    "username": "viewer",
                    "accessToken": "token",
                    "userId": "123",
                    "isConnected": true
                  }
                ],
                "syncEnabled": true
              },
              "catalogs": [
                {
                  "id": "trending",
                  "name": "Trending This Week",
                  "source": "TMDB",
                  "isEnabled": true,
                  "order": 2,
                  "displayStyle": "standard"
                }
              ],
              "services": [
                {
                  "id": "3C357FD9-AE8B-42D3-A201-1734B56D2804",
                  "url": "https://example.test/service.json",
                  "jsonMetadata": "{\"name\":\"Example\"}",
                  "jsScript": "async function searchResults() { return [] }",
                  "isActive": true,
                  "sortIndex": 4
                }
              ],
              "stremioAddons": [
                {
                  "id": "org.example",
                  "configuredURL": "https://addon.example",
                  "manifestJSON": "{\"id\":\"org.example\",\"name\":\"Example\"}",
                  "isActive": true,
                  "sortIndex": 1
                }
              ],
              "mangaReadingProgress": {
                "123": {
                  "readChapterNumbers": ["1", "2"],
                  "lastReadChapter": "2",
                  "pagePositions": {
                    "2": 5
                  },
                  "title": "Manga"
                }
              },
              "aidokuState": {
                "sourceLists": [
                  {
                    "url": "https://aidoku.example/sources.json",
                    "name": "Example Sources",
                    "sourceCount": 1,
                    "lastRefresh": "2026-04-23T00:00:00Z"
                  }
                ],
                "installedSources": [
                  {
                    "id": "example.en",
                    "name": "Example Aidoku",
                    "version": 3,
                    "languages": ["en"],
                    "externalIconURL": "https://aidoku.example/icon.png",
                    "contentRatingRawValue": 0,
                    "sourceListURL": "https://aidoku.example/sources.json",
                    "packageURL": "https://aidoku.example/example.aix",
                    "isEnabled": true,
                    "order": 2,
                    "lastUpdated": "2026-04-24T00:00:00Z",
                    "payloadArchiveData": "YWJj"
                  }
                ],
                "showMatureSources": true,
                "autoUpdateSources": false,
                "lastAutoUpdate": "2026-04-25T00:00:00Z"
              },
              "readerDownloads": [
                {
                  "id": "download-1",
                  "routeKey": "aidoku:example.en:manga-key",
                  "title": "Example Aidoku",
                  "chapterNumber": "4",
                  "status": "completed",
                  "progress": 1.0,
                  "downloadedBytes": 42
                }
              ],
              "sourceHealth": {
                "records": {
                  "service:first": {
                    "sourceId": "service:first",
                    "sourceName": "Example",
                    "endpointStatus": "HEALTHY",
                    "lastEndpointCheckedAt": 1770000000000,
                    "lastPlaybackSuccessAt": 1770000001000
                  }
                },
                "lastDailyCheckAt": 1770000002000
              },
              "appLogs": {
                "entries": [
                  {
                    "id": "log-1",
                    "timestamp": 1770000003000,
                    "tag": "ServiceRuntime",
                    "message": "Resolved stream",
                    "level": "info"
                  }
                ]
              },
              "recommendationCache": [
                {
                  "id": 99,
                  "title": "Recommended"
                }
              ],
              "userRatings": {
                "99": 7.5
              },
              "userRatingNotes": {
                "99": "rewatch with friends"
              },
              "futureIosOnlySection": {
                "still": "preserved"
              }
            }
        """.trimIndent()

        val document = BackupDocument.decode(json, raw)
        val encoded = document.encode(json)

        assertEquals("1.0", document.payload.version)
        assertEquals("#401F73", document.payload.settingsGradientColor)
        assertEquals(InAppPlayer.MPV, document.payload.resolvedInAppPlayer)
        assertEquals(true, document.payload.useClassicScheduleUI)
        assertEquals(1.25, document.payload.defaultPlaybackSpeed)
        assertEquals(90, document.payload.nextEpisodeThresholdPercent())
        assertEquals(true, document.payload.enableSubtitlesByDefault)
        assertEquals(false, document.payload.resolvedPlayerSubtitleAppearanceEnabled)
        assertEquals("org.videolan.vlc", document.payload.externalPlayer)
        assertEquals(true, document.payload.alwaysLandscape)
        assertEquals(false, document.payload.aniSkipEnabled)
        assertEquals(false, document.payload.introDBEnabled)
        assertEquals(true, document.payload.skip85sAlwaysVisible)
        assertEquals(false, document.payload.vlcHeaderProxyEnabled)
        assertEquals(true, document.payload.resolvedPlayerHeaderProxyEnabled)
        assertEquals(false, document.payload.playerTwoFingerTapPlayPauseEnabled)
        assertEquals(true, document.payload.vlcDoubleTapSeekEnabled)
        assertEquals(15.0, document.payload.vlcDoubleTapSeekSeconds)
        assertEquals(true, document.payload.vlcOpenSubtitlesEnabled)
        assertEquals(false, document.payload.vlcOpenSubtitlesAutoFallbackEnabled)
        assertEquals(true, document.payload.resolvedShowEpisodeBrowserButton)
        assertEquals(true, document.payload.resolvedPlayerBrightnessGestureEnabled)
        assertEquals(true, document.payload.resolvedPlayerVolumeGestureEnabled)
        assertEquals(false, document.payload.resolvedPlayerDoubleTapSeekEnabled)
        assertEquals(20.0, document.payload.resolvedPlayerDoubleTapSeekSeconds)
        assertEquals(true, document.payload.resolvedPlayerPictureInPictureEnabled)
        assertEquals(false, document.payload.resolvedPlayerOpenSubtitlesEnabled)
        assertEquals(true, document.payload.resolvedPlayerOpenSubtitlesAutoFallbackEnabled)
        assertEquals(true, document.payload.playerPerformanceOverlayEnabled)
        assertEquals(60, document.payload.mpvForegroundFPS)
        assertEquals("metal", document.payload.mpvRenderBackend)
        assertEquals("sharp", document.payload.mpvMetalQualityProfile)
        assertEquals(true, document.payload.mpvAppExitPictureInPictureEnabled)
        assertEquals(true, document.payload.skip85sEnabled)
        assertEquals(false, document.payload.showVLCEpisodeBrowserButton)
        assertEquals("#FFFFFF", document.payload.subtitleForegroundColor)
        assertEquals("#111111", document.payload.subtitleStrokeColor)
        assertEquals(2.5, document.payload.subtitleStrokeWidth)
        assertEquals(34.0, document.payload.subtitleFontSize)
        assertEquals(-8.0, document.payload.subtitleVerticalOffset)
        assertEquals(false, document.payload.autoModeEnabled)
        assertEquals(listOf("service:first", "stremio:https://addon.example"), document.payload.autoModeSourceIds)
        assertEquals(listOf("stremio:https://addon.example", "service:first"), document.payload.autoModeSourceOrderIds)
        assertEquals("1080p", document.payload.servicesAutoModeQualityPreference)
        assertEquals("actions,overview,details,cast,ratingNotes,episodes", document.payload.mediaDetailElementOrder)
        assertEquals("cast", document.payload.mediaDetailHiddenElements)
        assertEquals("chapters,overview,tags,ratingNotes", document.payload.readerDetailElementOrder)
        assertEquals("tags", document.payload.readerDetailHiddenElements)
        assertEquals("popularAnime", document.payload.heroBannerCatalogId)
        assertEquals("carousel", document.payload.heroBannerBehavior)
        assertEquals("solid", document.payload.atmosphereStyle)
        assertEquals("custom", document.payload.atmosphereSolidColorSource)
        assertEquals("#224466", document.payload.atmosphereSolidColor)
        assertEquals("Georgia", document.payload.readerFontFamily)
        assertEquals(75.0, document.payload.readerReadThresholdPercent)
        assertEquals(1, document.payload.collections.single().items.size)
        assertTrue(document.payload.progressData.jsonObject.containsKey("movieProgress"))
        assertEquals("viewer", document.payload.trackerState.accounts.single().username)
        assertEquals("Trending This Week", document.payload.catalogs.single().displayName)
        assertEquals("https://example.test/service.json", document.payload.services.single().resolvedScriptUrl)
        val stremioAddons = assertNotNull(document.payload.stremioAddons)
        assertEquals("https://addon.example", stremioAddons.single().resolvedTransportUrl)
        assertEquals("2", document.payload.mangaReadingProgress.getValue("123").lastReadChapter)
        val aidokuState = assertNotNull(document.payload.aidokuState)
        assertEquals("Example Sources", aidokuState.sourceLists.single().name)
        assertEquals("Example Aidoku", aidokuState.installedSources.single().displayName)
        assertEquals("YWJj", aidokuState.installedSources.single().payloadArchiveData)
        assertEquals(true, aidokuState.showMatureSources)
        assertEquals(false, aidokuState.autoUpdateSources)
        assertEquals("download-1", document.payload.readerDownloads.single().id)
        val sourceHealth = assertNotNull(document.payload.sourceHealth)
        assertEquals(SourceHealthStatus.HEALTHY, sourceHealth.records.getValue("service:first").endpointStatus)
        assertEquals(1770000002000, sourceHealth.lastDailyCheckAt)
        val appLogs = assertNotNull(document.payload.appLogs)
        assertEquals("ServiceRuntime", appLogs.entries.single().tag)
        assertEquals(7.5, document.payload.userRatings.getValue("99"))
        assertEquals("rewatch with friends", document.payload.userRatingNotes.getValue("99"))
        assertTrue("futureIosOnlySection" in document.unknownKeys)
        assertTrue(encoded.contains("futureIosOnlySection"))
        assertTrue(encoded.contains("manifestJSON"))
        assertTrue(encoded.contains("userRatingNotes"))
        assertTrue(encoded.contains("aidokuState"))
        assertTrue(encoded.contains("readerDownloads"))
        assertTrue(encoded.contains("sourceHealth"))
        assertTrue(encoded.contains("appLogs"))
        assertTrue(encoded.contains("heroBannerCatalogId"))
        assertTrue(encoded.contains("atmosphereSolidColor"))
        assertTrue(encoded.contains("showEpisodeBrowserButton"))
        assertTrue(encoded.contains("playerSubtitleAppearanceEnabled"))
        assertTrue(encoded.contains("playerDoubleTapSeekEnabled"))
        assertTrue(encoded.contains("readerDetailElementOrder"))
    }

    @Test
    fun decodesBackupColorsFromHexAndBase64TextData() {
        val raw = """
            {
              "version": "1.0",
              "accentColor": "I2ZmY2M4OA==",
              "settingsGradientColor": "0x112233",
              "subtitleForegroundColor": "ffffff",
              "subtitleStrokeColor": "#80112233"
            }
        """.trimIndent()

        val document = BackupDocument.decode(json, raw)
        val encoded = document.encode(json)

        assertEquals("#FFCC88", document.payload.accentColor)
        assertEquals("#112233", document.payload.settingsGradientColor)
        assertEquals("#FFFFFF", document.payload.subtitleForegroundColor)
        assertEquals("#80112233", document.payload.subtitleStrokeColor)
        assertTrue(encoded.contains("#FFCC88"))
        assertTrue(encoded.contains("#80112233"))
    }

    @Test
    fun nextEpisodeThresholdMatchesIosRange() {
        assertEquals(50, BackupData(nextEpisodeThreshold = 0.50).nextEpisodeThresholdPercent())
        assertEquals(99, BackupData(nextEpisodeThreshold = 0.99).nextEpisodeThresholdPercent())
    }
}


