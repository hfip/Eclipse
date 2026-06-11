package dev.soupy.eclipse.android.core.model

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class ParityModelsTest {
    @Test
    fun androidParityChecklistHasNoUncheckedItems() {
        assertTrue(AndroidParityChecklist.items.isNotEmpty())
        assertEquals(AndroidParityChecklist.items.size, AndroidParityChecklist.items.map { it.id }.toSet().size)
        assertEquals(emptyList(), AndroidParityChecklist.uncheckedItems)
        assertTrue(AndroidParityChecklist.items.any { it.status == AndroidParityStatus.NON_PORTABLE })
        assertTrue(AndroidParityChecklist.items.any { it.id == "reader-native-aidoku-runner" })
        AndroidParityChecklist.items.forEach { item ->
            assertTrue(item.requiredBehaviors.isNotEmpty(), "Missing required behaviors for ${item.id}")
            assertTrue(item.androidEvidence.isNotEmpty(), "Missing Android evidence for ${item.id}")
            assertTrue(item.verification.isNotEmpty(), "Missing verification for ${item.id}")
        }
        AndroidParityChecklist.implementedItems.forEach { item ->
            assertTrue(
                item.androidEvidence.any { evidence -> evidence.startsWith("android/") },
                "Implemented parity item ${item.id} needs at least one repository evidence path",
            )
        }
    }

    @Test
    fun restoredAidokuSourcesAreExplicitlyNonPortable() {
        val source = BackupAidokuInstalledSource(
            id = "example",
            name = "Example Aidoku",
            languages = listOf("en"),
            packageURL = "https://source.example/pkg.aix",
        )

        assertFalse(source.isPortableOnAndroid)
        assertEquals("Example Aidoku", source.displayName)
        assertTrue(source.unavailableReason.contains("Android uses portable Kanzen/WebView sources"))
    }

    @Test
    fun catalogMergePreservesSavedRowsAndAddsIosDefaults() {
        val saved = listOf(
            BackupCatalog(
                id = "popularMovies",
                name = "My Movies",
                source = "TMDB",
                isEnabled = false,
                order = 0,
            ),
            BackupCatalog(
                id = "forYou",
                name = "Just For You",
                source = "Local",
                isEnabled = true,
                order = 1,
            ),
        )

        val merged = saved.mergedWithDefaultCatalogs()

        assertEquals(DefaultCatalogs.size, merged.size)
        assertEquals("popularMovies", merged[0].id)
        assertEquals("My Movies", merged[0].displayName)
        assertFalse(merged[0].isEnabled)
        assertTrue(merged.any { it.id == "bestAnime" && it.displayStyle == "ranked" })
        assertEquals(merged.indices.toList(), merged.map { it.order })
    }

    @Test
    fun progressEntriesApplyIosWatchedThreshold() {
        val movie = MovieProgressBackup(
            id = 1,
            currentTime = 85.0,
            totalDuration = 100.0,
        ).withWatchedThreshold()
        val episode = EpisodeProgressBackup(
            id = "ep_2_s1_e1",
            showId = 2,
            seasonNumber = 1,
            episodeNumber = 1,
            currentTime = 84.0,
            totalDuration = 100.0,
        ).withWatchedThreshold()

        assertTrue(movie.isWatched)
        assertFalse(episode.isWatched)
        assertEquals(0.84, episode.progressPercent)
    }

    @Test
    fun episodeProgressPreservesExplicitAnimeEvidence() {
        val json = Json.encodeToString(
            EpisodeProgressBackup(
                id = "ep_2_s1_e1",
                showId = 2,
                seasonNumber = 1,
                episodeNumber = 1,
                anilistMediaId = 123,
                isAnime = true,
            ),
        )
        val decoded = Json.decodeFromString<EpisodeProgressBackup>(json)
        val legacy = Json.decodeFromString<EpisodeProgressBackup>(
            """{"id":"ep_3_s1_e1","showId":3,"seasonNumber":1,"episodeNumber":1,"anilistMediaId":456}""",
        )

        assertTrue(decoded.isAnime)
        assertFalse(legacy.isAnime)
    }

    @Test
    fun backupPreservesNextEpisodePosterButtonSetting() {
        val json = Json.encodeToString(BackupData(showNextEpisodePosterButton = true))
        val decoded = Json.decodeFromString<BackupData>(json)
        val legacy = Json.decodeFromString<BackupData>("{}")

        assertTrue(decoded.showNextEpisodePosterButton)
        assertFalse(legacy.showNextEpisodePosterButton)
    }

    @Test
    fun appLogSnapshotPrependsAndCapsExportedRows() {
        val snapshot = (1..5).fold(AppLogSnapshot()) { current, index ->
            current.append(
                AppLogEntry(
                    id = "log-$index",
                    timestamp = index.toLong(),
                    tag = "reader",
                    message = "message $index",
                ),
                maxEntries = 3,
            )
        }

        assertEquals(listOf("log-5", "log-4", "log-3"), snapshot.entries.map(AppLogEntry::id))
        assertTrue(snapshot.hasUserData)
    }

    @Test
    fun backupPreservesIosDetailLayoutAndAutoModeQualityFields() {
        val json = Json.encodeToString(
            BackupData(
                showVLCEpisodeBrowserButton = false,
                mediaDetailElementOrder = "actions,overview,episodes",
                mediaDetailHiddenElements = "cast,ratingNotes",
                servicesAutoModeQualityPreference = "720p",
            ),
        )
        val decoded = Json.decodeFromString<BackupData>(json)

        assertFalse(decoded.showVLCEpisodeBrowserButton)
        assertEquals("actions,overview,episodes", decoded.mediaDetailElementOrder)
        assertEquals("cast,ratingNotes", decoded.mediaDetailHiddenElements)
        assertEquals("720p", decoded.servicesAutoModeQualityPreference)
    }

    @Test
    fun mediaDetailElementSanitizesOrderAndHiddenValuesLikeIos() {
        val order = MediaDetailElement.sanitizedOrderRawValue("actions,overview,actions,unknown")
        val hidden = MediaDetailElement.sanitizedHiddenRawValue("ratingNotes,unknown,cast")

        assertEquals("actions,overview,details,cast,ratingNotes,episodes", order)
        assertEquals("cast,ratingNotes", hidden)
    }

    @Test
    fun autoModeQualityPreferenceUsesIosRawValues() {
        assertEquals(ServicesAutoModeQualityPreference.MANUAL, ServicesAutoModeQualityPreference.fromRawValue("manual"))
        assertEquals(ServicesAutoModeQualityPreference.QUALITY_1080, ServicesAutoModeQualityPreference.fromRawValue("1080p"))
        assertEquals("auto", ServicesAutoModeQualityPreference.sanitizedRawValue("nonsense"))
        assertFalse(ServicesAutoModeQualityPreference.MANUAL.usesAutomaticSelection)
        assertTrue(ServicesAutoModeQualityPreference.QUALITY_720.usesAutomaticSelection)
    }

    @Test
    fun ratingsSnapshotClampsBackupValues() {
        val snapshot = RatingsSnapshot(
            ratings = mapOf(
                "1" to 0.0,
                "2" to 3.25,
                "3" to 12.0,
            ),
            notes = mapOf("2" to "  keep  ", "3" to "   "),
        ).normalized

        assertEquals(0.5, snapshot.ratings.getValue("1"))
        assertEquals(3.5, snapshot.ratings.getValue("2"))
        assertEquals(10.0, snapshot.ratings.getValue("3"))
        assertEquals("keep", snapshot.notes.getValue("2"))
        assertEquals(false, snapshot.notes.containsKey("3"))
    }

    @Test
    fun ratingsSnapshotDecodesLegacyIntegerRatings() {
        val snapshot = Json.decodeFromString<RatingsSnapshot>("""{"ratings":{"42":7}}""").normalized

        assertEquals(7.0, snapshot.ratings.getValue("42"))
    }

    @Test
    fun trackerSnapshotPreservesAutoRatingSyncFlag() {
        val json = Json.encodeToString(TrackerStateSnapshot(autoSyncRatings = true))
        val decoded = Json.decodeFromString<TrackerStateSnapshot>(json)
        val legacyDecoded = Json.decodeFromString<TrackerStateSnapshot>("{}")

        assertTrue(decoded.autoSyncRatings)
        assertFalse(legacyDecoded.autoSyncRatings)
    }

    @Test
    fun tmdbRatingsPreferUsCertificationAndContentRating() {
        val releaseDates = TMDBReleaseDatesResponse(
            results = listOf(
                TMDBReleaseDateCountry(
                    countryCode = "CA",
                    releaseDates = listOf(TMDBReleaseDateEntry(certification = "14A")),
                ),
                TMDBReleaseDateCountry(
                    countryCode = "US",
                    releaseDates = listOf(
                        TMDBReleaseDateEntry(certification = ""),
                        TMDBReleaseDateEntry(certification = "PG-13"),
                    ),
                ),
            ),
        )
        val contentRatings = TMDBContentRatingsResponse(
            results = listOf(
                TMDBContentRating(countryCode = "GB", rating = "15"),
                TMDBContentRating(countryCode = "US", rating = "TV-MA"),
            ),
        )

        assertEquals("PG-13", releaseDates.usCertification)
        assertEquals("TV-MA", contentRatings.usRating)
    }

    @Test
    fun tmdbRatingsFallBackLikeIosWhenUsIsMissing() {
        val releaseDates = TMDBReleaseDatesResponse(
            results = listOf(
                TMDBReleaseDateCountry(
                    countryCode = "CA",
                    releaseDates = listOf(TMDBReleaseDateEntry(certification = "14A")),
                ),
                TMDBReleaseDateCountry(
                    countryCode = "US",
                    releaseDates = listOf(TMDBReleaseDateEntry(certification = "")),
                ),
            ),
        )
        val contentRatings = TMDBContentRatingsResponse(
            results = listOf(
                TMDBContentRating(countryCode = "US", rating = ""),
                TMDBContentRating(countryCode = "GB", rating = "15"),
            ),
        )

        assertEquals("14A", releaseDates.usCertification)
        assertEquals("15", contentRatings.usRating)
    }

    @Test
    fun tmdbMultiSearchOnlyTreatsMovieAndTvMediaTypesAsOpenable() {
        val movie = TMDBSearchResult(id = 1, mediaType = "movie", title = "Movie")
        val show = TMDBSearchResult(id = 2, mediaType = "tv", name = "Show")
        val person = TMDBSearchResult(id = 3, mediaType = "person", name = "Actor")
        val discoverMovie = TMDBSearchResult(id = 4, title = "Discover Movie")
        val discoverShow = TMDBSearchResult(id = 5, name = "Discover Show")

        assertTrue(movie.isMovie)
        assertTrue(show.isTVShow)
        assertFalse(person.isMovie)
        assertFalse(person.isTVShow)
        assertTrue(discoverMovie.isMovie)
        assertTrue(discoverShow.isTVShow)
    }

    @Test
    fun tmdbLogoSelectionMatchesIosLanguagePreference() {
        val images = TMDBImagesResponse(
            logos = listOf(
                TMDBImage(filePath = "/fallback.png", languageCode = null),
                TMDBImage(filePath = "/english.png", languageCode = "en"),
                TMDBImage(filePath = "/spanish.png", languageCode = "es"),
            ),
        )

        assertEquals("https://image.tmdb.org/t/p/original/spanish.png", images.bestLogoUrl("es-MX"))
        assertEquals("https://image.tmdb.org/t/p/original/english.png", images.bestLogoUrl("fr-FR"))
        assertEquals(null, TMDBImagesResponse(logos = null).bestLogoUrl("en-US"))
    }

    @Test
    fun searchHistoryMovesRepeatedQueriesToFront() {
        val history = SearchHistorySnapshot(listOf("Dune", "Alien"))
            .remember("alien")
            .remember("Severance")

        assertEquals(listOf("Severance", "alien", "Dune"), history.queries)
    }
}
