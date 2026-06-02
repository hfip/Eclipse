package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.DetailTarget
import dev.soupy.eclipse.android.core.model.EpisodePlaybackContext
import dev.soupy.eclipse.android.core.model.TrackerAccountSnapshot
import dev.soupy.eclipse.android.core.network.EclipseHttpClient
import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.network.NetworkResult
import java.time.Instant
import kotlin.math.roundToInt
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

data class TrackerPlaybackProgressDraft(
    val target: DetailTarget,
    val title: String,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val anilistMediaId: Int? = null,
    val progressPercent: Double,
    val isFinished: Boolean = false,
    val playbackContext: EpisodePlaybackContext? = null,
    val isAnime: Boolean = false,
    val forceTraktSync: Boolean = false,
)

data class TrackerSyncSummary(
    val state: dev.soupy.eclipse.android.core.model.TrackerStateSnapshot,
    val attemptedAccounts: Int = 0,
    val attemptedItems: Int = 0,
    val syncedItems: Int = 0,
    val skippedItems: Int = 0,
    val failures: List<String> = emptyList(),
) {
    val statusMessage: String
        get() = when {
            attemptedAccounts == 0 -> "No connected tracker accounts are ready to sync."
            attemptedItems == 0 -> "No watched local progress is ready to sync yet."
            failures.isNotEmpty() && syncedItems == 0 -> "Tracker sync failed: ${failures.first()}"
            failures.isNotEmpty() -> "Synced $syncedItems tracker item${syncedItems.s()} with ${failures.size} issue${failures.size.s()}."
            syncedItems > 0 -> "Synced $syncedItems tracker item${syncedItems.s()}."
            else -> "Tracker sync skipped $skippedItems item${skippedItems.s()} with no eligible remote updates."
        }
}

internal data class TrackerSyncItem(
    val target: DetailTarget,
    val title: String,
    val seasonNumber: Int? = null,
    val episodeNumber: Int? = null,
    val anilistMediaId: Int? = null,
    val anilistEpisodeNumber: Int? = episodeNumber,
    val progressPercent: Double,
    val isFinished: Boolean = false,
    val isAnime: Boolean = false,
    val forceTraktSync: Boolean = false,
) {
    val isWatchedEnough: Boolean
        get() = isFinished || progressPercent >= TrackerWatchedThreshold
}

internal data class TrackerItemSyncResult(
    val synced: Boolean = false,
    val skipped: Boolean = false,
    val message: String? = null,
)

class TrackerSyncClient(
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
    private val traktClientId: String = "",
) {
    private val aniListToMalAnimeIdCache = mutableMapOf<Int, Int>()
    private val traktMediaIdCache = mutableMapOf<String, Int>()
    private val recentTraktPlaybackSyncAt = mutableMapOf<String, Long>()

    internal suspend fun sync(
        account: TrackerAccountSnapshot,
        item: TrackerSyncItem,
    ): TrackerItemSyncResult {
        if (!account.isConnected || account.accessToken.isBlank()) {
            return TrackerItemSyncResult(skipped = true, message = "${account.service} is not connected.")
        }
        return when (account.service.normalizedTrackerService()) {
            "anilist" -> syncAniList(account, item)
            "trakt" -> syncTrakt(account, item)
            "myanimelist",
            "mal" -> syncMyAnimeList(account, item)
            else -> TrackerItemSyncResult(skipped = true, message = "Unsupported tracker ${account.service}.")
        }
    }

    private suspend fun syncAniList(
        account: TrackerAccountSnapshot,
        item: TrackerSyncItem,
    ): TrackerItemSyncResult {
        if (!item.hasAnimeTrackerEvidence) {
            return TrackerItemSyncResult(skipped = true, message = "AniList anime sync needs anime playback evidence.")
        }
        if (!item.isWatchedEnough) {
            return TrackerItemSyncResult(skipped = true, message = "AniList waits until 85% watched.")
        }
        val mediaId = item.anilistMediaId
            ?: return TrackerItemSyncResult(skipped = true, message = "AniList sync needs an AniList media id.")
        val episodeNumber = item.anilistEpisodeNumber
            ?: return TrackerItemSyncResult(skipped = true, message = "AniList sync needs an episode number.")

        val body = EclipseJson.encodeToString(
            buildJsonObject {
                put("query", aniListSaveMediaListMutation(mediaId, episodeNumber))
            },
        )
        return when (
            val result = httpClient.postJson(
                url = "https://graphql.anilist.co",
                body = body,
                headers = mapOf("Authorization" to "Bearer ${account.accessToken}"),
            )
        ) {
            is NetworkResult.Success -> {
                val error = result.value.graphQlErrorMessage()
                if (error == null) {
                    TrackerItemSyncResult(synced = true)
                } else {
                    TrackerItemSyncResult(message = "AniList: $error")
                }
            }
            is NetworkResult.Failure.Http -> TrackerItemSyncResult(message = "AniList HTTP ${result.code}: ${result.body.orEmpty()}")
            is NetworkResult.Failure.Connectivity -> TrackerItemSyncResult(message = "AniList connectivity: ${result.throwable.message}")
            is NetworkResult.Failure.Serialization -> TrackerItemSyncResult(message = "AniList serialization: ${result.throwable.message}")
        }
    }

    private suspend fun syncTrakt(
        account: TrackerAccountSnapshot,
        item: TrackerSyncItem,
    ): TrackerItemSyncResult {
        val configuredTraktClientId = traktClientId.trim()
        if (configuredTraktClientId.isBlank()) {
            return TrackerItemSyncResult(skipped = true, message = "Trakt sync needs TRAKT_CLIENT_ID.")
        }
        if (!item.isWatchedEnough) {
            return scrobbleTraktPause(account, item)
        }
        val payload = item.toTraktHistoryPayload(Instant.now().toString())
            ?: return TrackerItemSyncResult(skipped = true, message = "Trakt sync needs TMDB movie or episode metadata.")
        return when (
            val result = httpClient.postJson(
                url = "https://api.trakt.tv/sync/history",
                body = EclipseJson.encodeToString(payload),
                headers = mapOf(
                    "Authorization" to "Bearer ${account.accessToken}",
                    "trakt-api-key" to configuredTraktClientId,
                    "trakt-api-version" to "2",
                ),
            )
        ) {
            is NetworkResult.Success -> TrackerItemSyncResult(synced = true)
            is NetworkResult.Failure.Http -> TrackerItemSyncResult(message = "Trakt HTTP ${result.code}: ${result.body.orEmpty()}")
            is NetworkResult.Failure.Connectivity -> TrackerItemSyncResult(message = "Trakt connectivity: ${result.throwable.message}")
            is NetworkResult.Failure.Serialization -> TrackerItemSyncResult(message = "Trakt serialization: ${result.throwable.message}")
        }
    }

    private suspend fun scrobbleTraktPause(
        account: TrackerAccountSnapshot,
        item: TrackerSyncItem,
    ): TrackerItemSyncResult {
        val key = item.traktPlaybackSyncKey()
            ?: return TrackerItemSyncResult(skipped = true, message = "Trakt scrobble needs TMDB movie or episode metadata.")
        if (!shouldStartTraktPlaybackSync(key, item.forceTraktSync)) {
            return TrackerItemSyncResult(skipped = true)
        }

        val payload = when (val target = item.target) {
            is DetailTarget.TmdbMovie -> {
                val movie = resolveTraktMedia(target.id, "movie")
                    ?: return TrackerItemSyncResult(skipped = true, message = "Trakt could not map TMDB movie ${target.id}.")
                buildJsonObject {
                    put("progress", item.normalizedTraktScrobbleProgress())
                    put(
                        "movie",
                        buildJsonObject {
                            movie.title?.let { put("title", it) }
                            movie.year?.let { put("year", it) }
                            put("ids", buildJsonObject { put("trakt", movie.traktId) })
                        },
                    )
                }
            }
            is DetailTarget.TmdbShow -> {
                val season = item.seasonNumber
                    ?: return TrackerItemSyncResult(skipped = true, message = "Trakt scrobble needs a TMDB season.")
                val episode = item.episodeNumber
                    ?: return TrackerItemSyncResult(skipped = true, message = "Trakt scrobble needs a TMDB episode.")
                val show = resolveTraktMedia(target.id, "show")
                    ?: return TrackerItemSyncResult(skipped = true, message = "Trakt could not map TMDB show ${target.id}.")
                val traktEpisodeId = resolveTraktEpisodeId(account, show.traktId, season, episode)
                    ?: return TrackerItemSyncResult(skipped = true, message = "Trakt could not map S${season}E${episode}.")
                buildJsonObject {
                    put("progress", item.normalizedTraktScrobbleProgress())
                    put(
                        "episode",
                        buildJsonObject {
                            put("ids", buildJsonObject { put("trakt", traktEpisodeId) })
                        },
                    )
                }
            }
            is DetailTarget.AniListMediaTarget,
            is DetailTarget.ServiceMedia ->
                return TrackerItemSyncResult(skipped = true, message = "Trakt scrobble needs a mapped TMDB item.")
        }
        return when (
            val result = httpClient.postJson(
                url = "https://api.trakt.tv/scrobble/pause",
                body = EclipseJson.encodeToString(payload),
                headers = account.traktHeaders(),
            )
        ) {
            is NetworkResult.Success -> TrackerItemSyncResult(synced = true)
            is NetworkResult.Failure.Http -> TrackerItemSyncResult(message = "Trakt HTTP ${result.code}: ${result.body.orEmpty()}")
            is NetworkResult.Failure.Connectivity -> TrackerItemSyncResult(message = "Trakt connectivity: ${result.throwable.message}")
            is NetworkResult.Failure.Serialization -> TrackerItemSyncResult(message = "Trakt serialization: ${result.throwable.message}")
        }
    }

    private suspend fun resolveTraktMedia(tmdbId: Int, type: String): TraktMediaLookup? {
        val key = "$type|$tmdbId"
        traktMediaIdCache[key]?.let { return TraktMediaLookup(traktId = it) }
        return when (
            val result = httpClient.get(
                url = "https://api.trakt.tv/search/tmdb/$tmdbId?type=$type",
                headers = traktHeaders(),
            )
        ) {
            is NetworkResult.Success -> runCatching {
                val media = EclipseJson.parseToJsonElement(result.value)
                    .jsonArray
                    .firstOrNull()
                    ?.jsonObject
                    ?.get(type)
                    ?.jsonObject
                    ?: return@runCatching null
                val traktId = media["ids"]
                    ?.jsonObject
                    ?.get("trakt")
                    ?.jsonPrimitive
                    ?.intOrNull
                    ?: return@runCatching null
                traktMediaIdCache[key] = traktId
                TraktMediaLookup(
                    traktId = traktId,
                    title = media["title"]?.jsonPrimitive?.contentOrNull,
                    year = media["year"]?.jsonPrimitive?.intOrNull,
                )
            }.getOrNull()
            is NetworkResult.Failure -> null
        }
    }

    private suspend fun resolveTraktEpisodeId(
        account: TrackerAccountSnapshot,
        traktShowId: Int,
        seasonNumber: Int,
        episodeNumber: Int,
    ): Int? {
        val key = "episode|$traktShowId|$seasonNumber|$episodeNumber"
        traktMediaIdCache[key]?.let { return it }
        return when (
            val result = httpClient.get(
                url = "https://api.trakt.tv/shows/$traktShowId/seasons/$seasonNumber/episodes/$episodeNumber",
                headers = account.traktHeaders(),
            )
        ) {
            is NetworkResult.Success -> runCatching {
                EclipseJson.parseToJsonElement(result.value)
                    .jsonObject["ids"]
                    ?.jsonObject
                    ?.get("trakt")
                    ?.jsonPrimitive
                    ?.intOrNull
                    ?.also { traktMediaIdCache[key] = it }
            }.getOrNull()
            is NetworkResult.Failure -> null
        }
    }

    private fun shouldStartTraktPlaybackSync(key: String, force: Boolean): Boolean {
        val now = System.currentTimeMillis()
        recentTraktPlaybackSyncAt.entries.removeAll { (_, syncedAt) ->
            now - syncedAt >= TraktPlaybackSyncIntervalMillis * 10
        }
        val lastSyncAt = recentTraktPlaybackSyncAt[key]
        if (!force && lastSyncAt != null && now - lastSyncAt < TraktPlaybackSyncIntervalMillis) {
            return false
        }
        recentTraktPlaybackSyncAt[key] = now
        return true
    }

    private fun traktHeaders(): Map<String, String> = mapOf(
        "trakt-api-key" to traktClientId.trim(),
        "trakt-api-version" to "2",
    )

    private fun TrackerAccountSnapshot.traktHeaders(): Map<String, String> =
        traktHeaders() + ("Authorization" to "Bearer $accessToken")

    private suspend fun syncMyAnimeList(
        account: TrackerAccountSnapshot,
        item: TrackerSyncItem,
    ): TrackerItemSyncResult {
        if (!item.hasAnimeTrackerEvidence) {
            return TrackerItemSyncResult(skipped = true, message = "MAL anime sync needs anime playback evidence.")
        }
        if (!item.isWatchedEnough) {
            return TrackerItemSyncResult(skipped = true, message = "MAL anime sync waits until 85% watched.")
        }
        val mediaId = item.anilistMediaId
            ?: return TrackerItemSyncResult(skipped = true, message = "MAL anime sync needs an AniList media id.")
        val episodeNumber = item.anilistEpisodeNumber
            ?: return TrackerItemSyncResult(skipped = true, message = "MAL anime sync needs an episode number.")
        val malId = resolveMyAnimeListAnimeId(mediaId)
            ?: return TrackerItemSyncResult(skipped = true, message = "MAL anime sync could not map AniList $mediaId.")
        val status = if (item.isFinished) "completed" else "watching"
        return when (
            val result = httpClient.patchForm(
                url = "https://api.myanimelist.net/v2/anime/$malId/my_list_status",
                fields = mapOf(
                    "status" to status,
                    "num_watched_episodes" to episodeNumber.coerceAtLeast(0).toString(),
                ),
                headers = mapOf("Authorization" to "Bearer ${account.accessToken}"),
            )
        ) {
            is NetworkResult.Success -> TrackerItemSyncResult(synced = true)
            is NetworkResult.Failure.Http -> TrackerItemSyncResult(message = "MAL HTTP ${result.code}: ${result.body.orEmpty()}")
            is NetworkResult.Failure.Connectivity -> TrackerItemSyncResult(message = "MAL connectivity: ${result.throwable.message}")
            is NetworkResult.Failure.Serialization -> TrackerItemSyncResult(message = "MAL serialization: ${result.throwable.message}")
        }
    }

    private suspend fun resolveMyAnimeListAnimeId(anilistId: Int): Int? {
        aniListToMalAnimeIdCache[anilistId]?.let { return it }
        val body = EclipseJson.encodeToString(
            buildJsonObject {
                put(
                    "query",
                    """
                    query {
                        Media(id: $anilistId, type: ANIME) {
                            idMal
                        }
                    }
                    """.trimIndent(),
                )
            },
        )
        return when (
            val result = httpClient.postJson(
                url = "https://graphql.anilist.co",
                body = body,
            )
        ) {
            is NetworkResult.Success -> {
                val malId = EclipseJson.parseToJsonElement(result.value)
                    .jsonObject["data"]
                    ?.jsonObject
                    ?.get("Media")
                    ?.jsonObject
                    ?.get("idMal")
                    ?.jsonPrimitive
                    ?.intOrNull
                malId?.also { aniListToMalAnimeIdCache[anilistId] = it }
            }
            is NetworkResult.Failure -> null
        }
    }
}

internal fun TrackerPlaybackProgressDraft.toTrackerSyncItem(): TrackerSyncItem {
    val context = playbackContext
    val traktNumbers = if (context == null) {
        seasonNumber?.let { season -> episodeNumber?.let { episode -> season to episode } }
    } else {
        context.traktEpisodeNumbersOrNull()
    }
    return TrackerSyncItem(
        target = target,
        title = title,
        seasonNumber = traktNumbers?.first,
        episodeNumber = traktNumbers?.second,
        anilistMediaId = anilistMediaId ?: context?.anilistMediaId,
        anilistEpisodeNumber = context?.localEpisodeNumber ?: episodeNumber,
        progressPercent = progressPercent,
        isFinished = isFinished,
        isAnime = isAnime || target is DetailTarget.AniListMediaTarget || context?.anilistMediaId != null,
        forceTraktSync = forceTraktSync,
    )
}

private data class TraktMediaLookup(
    val traktId: Int,
    val title: String? = null,
    val year: Int? = null,
)

private fun TrackerSyncItem.traktPlaybackSyncKey(): String? = when (val detailTarget = target) {
    is DetailTarget.TmdbMovie -> "movie|${detailTarget.id}"
    is DetailTarget.TmdbShow -> {
        val season = seasonNumber ?: return null
        val episode = episodeNumber ?: return null
        "episode|${detailTarget.id}|$season|$episode"
    }
    is DetailTarget.AniListMediaTarget,
    is DetailTarget.ServiceMedia -> null
}

private fun TrackerSyncItem.normalizedTraktScrobbleProgress(): Int =
    (progressPercent * 100.0)
        .roundToInt()
        .coerceIn(0, 100)

internal fun EpisodePlaybackContext.traktEpisodeNumbersOrNull(): Pair<Int, Int>? {
    if (tmdbSeasonNumber != null && (tmdbEpisodeNumber != null || tmdbEpisodeOffset != null)) {
        return resolvedTMDBSeasonNumber to resolvedTMDBEpisodeNumber
    }
    if (isSpecial || hasAnimeMediaId) return null
    return localSeasonNumber to localEpisodeNumber
}

private val TrackerSyncItem.hasAnimeTrackerEvidence: Boolean
    get() = isAnime || target is DetailTarget.AniListMediaTarget

internal fun TrackerSyncItem.toTraktHistoryPayload(watchedAt: String): JsonObject? = when (val detailTarget = target) {
    is DetailTarget.TmdbMovie -> buildJsonObject {
        put(
            "movies",
            buildJsonArray {
                add(
                    buildJsonObject {
                        put("ids", buildJsonObject { put("tmdb", detailTarget.id) })
                        put("watched_at", watchedAt)
                    },
                )
            },
        )
    }
    is DetailTarget.TmdbShow -> {
        val season = seasonNumber ?: return null
        val episode = episodeNumber ?: return null
        buildJsonObject {
            put(
                "shows",
                buildJsonArray {
                    add(
                        buildJsonObject {
                            put("ids", buildJsonObject { put("tmdb", detailTarget.id) })
                            put(
                                "seasons",
                                buildJsonArray {
                                    add(
                                        buildJsonObject {
                                            put("number", season)
                                            put(
                                                "episodes",
                                                buildJsonArray {
                                                    add(
                                                        buildJsonObject {
                                                            put("number", episode)
                                                            put("watched_at", watchedAt)
                                                        },
                                                    )
                                                },
                                            )
                                        },
                                    )
                                },
                            )
                        },
                    )
                },
            )
        }
    }
    is DetailTarget.AniListMediaTarget,
    is DetailTarget.ServiceMedia -> null
}

internal fun aniListSaveMediaListMutation(
    mediaId: Int,
    progress: Int,
): String = """
    mutation {
        SaveMediaListEntry(
            mediaId: $mediaId,
            progress: $progress,
            status: CURRENT
        ) {
            id
            progress
            status
        }
    }
""".trimIndent()

internal fun String.normalizedTrackerService(): String =
    trim()
        .lowercase()
        .replace(" ", "")
        .replace("-", "")

private fun String.graphQlErrorMessage(): String? =
    runCatching {
        val root = EclipseJson.parseToJsonElement(this).jsonObject
        root["errors"]?.jsonArray?.firstOrNull()?.jsonObject?.get("message")?.toString()?.trim('"')
    }.getOrNull()

private fun Int.s(): String = if (this == 1) "" else "s"

internal const val TrackerWatchedThreshold = 0.85
private const val TraktPlaybackSyncIntervalMillis = 30_000L
