package dev.soupy.eclipse.android.core.network

import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.min
import dev.soupy.eclipse.android.core.model.AniListAiringScheduleEntry
import dev.soupy.eclipse.android.core.model.AniListMedia
import dev.soupy.eclipse.android.core.model.AniListPageInfo
import dev.soupy.eclipse.android.core.model.AniListPageResponse
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement

class AniListService(
    private val baseUrl: String = "https://graphql.anilist.co",
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    private val aniMapSpecialCacheByTmdbShowId = mutableMapOf<Int, List<AniMapSpecialMapping>>()

    data class HomeCatalogs(
        val trending: List<AniListMedia> = emptyList(),
        val popular: List<AniListMedia> = emptyList(),
        val topRated: List<AniListMedia> = emptyList(),
        val airing: List<AniListMedia> = emptyList(),
        val upcoming: List<AniListMedia> = emptyList(),
    )

    data class MangaCatalogs(
        val trending: List<AniListMedia> = emptyList(),
        val popular: List<AniListMedia> = emptyList(),
        val topRated: List<AniListMedia> = emptyList(),
        val recentlyUpdated: List<AniListMedia> = emptyList(),
    )

    data class LibraryEntry(
        val media: AniListMedia,
        val status: String? = null,
        val progress: Int = 0,
        val progressVolumes: Int = 0,
        val score: Double = 0.0,
        val updatedAtEpochSeconds: Long? = null,
    )

    @Serializable
    data class AniMapSpecialMapping(
        @SerialName("anilist_id") val anilistId: Int? = null,
        @SerialName("tmdb_show_id") val tmdbShowId: Int? = null,
        @SerialName("tmdb_movie_id") val tmdbMovieId: Int? = null,
        @SerialName("tmdb_season") val tmdbSeason: Int? = null,
        @SerialName("tvdb_season") val tvdbSeason: Int? = null,
        @SerialName("tvdb_epoffset") val tvdbEpisodeOffset: Int? = null,
        @SerialName("imdb_id") val imdbId: String? = null,
        @SerialName("media_type") val mediaType: String? = null,
    )

    suspend fun searchAnime(
        query: String,
        page: Int = 1,
        perPage: Int = 20,
    ): NetworkResult<AniListPageResponse> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = SEARCH_QUERY,
                variables = AniListVariables(search = query, page = page, perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(AniListEnvelope.serializer(), result.value)
                NetworkResult.Success(response.data.page)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun searchManga(
        query: String,
        page: Int = 1,
        perPage: Int = 20,
    ): NetworkResult<AniListPageResponse> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = MANGA_SEARCH_QUERY,
                variables = AniListVariables(search = query, page = page, perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(AniListEnvelope.serializer(), result.value)
                NetworkResult.Success(response.data.page)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun searchNovels(
        query: String,
        page: Int = 1,
        perPage: Int = 20,
    ): NetworkResult<AniListPageResponse> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = NOVEL_SEARCH_QUERY,
                variables = AniListVariables(search = query, page = page, perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(AniListEnvelope.serializer(), result.value)
                NetworkResult.Success(response.data.page)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun mediaById(mediaId: Int): NetworkResult<AniListMedia> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = MEDIA_QUERY,
                variables = AniListVariables(id = mediaId),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(AniListMediaEnvelope.serializer(), result.value)
                NetworkResult.Success(response.data.media)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun mediaByMalIds(
        malIds: List<Int>,
        mediaType: String,
    ): NetworkResult<Map<Int, AniListMedia>> {
        val uniqueIds = malIds.filter { it > 0 }.distinct()
        if (uniqueIds.isEmpty()) return NetworkResult.Success(emptyMap())

        val resolved = mutableMapOf<Int, AniListMedia>()
        uniqueIds.chunked(50).forEach { chunk ->
            val query = mediaByMalIdsQuery(
                malIds = chunk,
                mediaType = mediaType.safeAniListMediaType(),
            )
            val body = EclipseJson.encodeToString(
                AniListRequest.serializer(),
                AniListRequest(
                    query = query,
                    variables = AniListVariables(),
                ),
            )
            when (val result = httpClient.postJson(baseUrl, body)) {
                is NetworkResult.Success -> {
                    try {
                        val response = EclipseJson.decodeFromString(AniListEnvelope.serializer(), result.value)
                        response.data.page.media.forEach { media ->
                            media.idMal?.let { malId -> resolved[malId] = media }
                        }
                    } catch (error: SerializationException) {
                        return NetworkResult.Failure.Serialization(error)
                    }
                }
                is NetworkResult.Failure -> return result
            }
        }
        return NetworkResult.Success(resolved)
    }

    suspend fun specialMappingsForTmdbShow(tmdbShowId: Int): NetworkResult<List<AniMapSpecialMapping>> {
        aniMapSpecialCacheByTmdbShowId[tmdbShowId]?.let { return NetworkResult.Success(it) }

        val url = "https://animap.s0n1c.ca/mappings/$tmdbShowId?mapping_key=tmdb_show"
        return when (val result = httpClient.get(url)) {
            is NetworkResult.Success -> try {
                val element = EclipseJson.parseToJsonElement(result.value)
                val mappings = when (element) {
                    is JsonArray -> element.mapNotNull { item ->
                        runCatching { EclipseJson.decodeFromJsonElement<AniMapSpecialMapping>(item) }.getOrNull()
                    }
                    is JsonObject -> listOf(EclipseJson.decodeFromJsonElement<AniMapSpecialMapping>(element))
                    else -> emptyList()
                }.filter { mapping ->
                    mapping.tmdbShowId == tmdbShowId &&
                        mapping.mediaType?.uppercase() in setOf("SPECIAL", "OVA")
                }
                aniMapSpecialCacheByTmdbShowId[tmdbShowId] = mappings
                NetworkResult.Success(mappings)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            } catch (error: IllegalArgumentException) {
                NetworkResult.Failure.Serialization(SerializationException(error.message ?: "AniMap response could not be decoded.", error))
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun fetchHomeCatalogs(perPage: Int = 18): NetworkResult<HomeCatalogs> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = HOME_CATALOGS_QUERY,
                variables = AniListVariables(perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(HomeCatalogsEnvelope.serializer(), result.value)
                NetworkResult.Success(
                    HomeCatalogs(
                        trending = response.data.trending.media,
                        popular = response.data.popular.media,
                        topRated = response.data.topRated.media,
                        airing = response.data.airing.media,
                        upcoming = response.data.upcoming.media,
                    ),
                )
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun fetchMangaCatalogs(perPage: Int = 18): NetworkResult<MangaCatalogs> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = MANGA_CATALOGS_QUERY,
                variables = AniListVariables(perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(MangaCatalogsEnvelope.serializer(), result.value)
                NetworkResult.Success(
                    MangaCatalogs(
                        trending = response.data.trending.media,
                        popular = response.data.popular.media,
                        topRated = response.data.topRated.media,
                        recentlyUpdated = response.data.recentlyUpdated.media,
                    ),
                )
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun fetchNovelCatalogs(perPage: Int = 18): NetworkResult<MangaCatalogs> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = NOVEL_CATALOGS_QUERY,
                variables = AniListVariables(perPage = perPage),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body)) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(MangaCatalogsEnvelope.serializer(), result.value)
                NetworkResult.Success(
                    MangaCatalogs(
                        trending = response.data.trending.media,
                        popular = response.data.popular.media,
                        topRated = response.data.topRated.media,
                        recentlyUpdated = response.data.recentlyUpdated.media,
                    ),
                )
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    suspend fun fetchAnimeLibrary(
        accessToken: String,
        username: String? = null,
    ): NetworkResult<List<LibraryEntry>> =
        fetchLibrary(
            accessToken = accessToken,
            username = username,
            query = ANIME_LIBRARY_QUERY,
        )

    suspend fun fetchMangaLibrary(
        accessToken: String,
        username: String? = null,
    ): NetworkResult<List<LibraryEntry>> =
        fetchLibrary(
            accessToken = accessToken,
            username = username,
            query = MANGA_LIBRARY_QUERY,
        )

    private suspend fun fetchLibrary(
        accessToken: String,
        username: String?,
        query: String,
    ): NetworkResult<List<LibraryEntry>> {
        val token = accessToken.trim()
        if (token.isBlank()) {
            return NetworkResult.Failure.Http(401, "AniList access token is required.")
        }

        val resolvedUsername = username
            ?.trim()
            ?.takeIf(String::isNotBlank)
            ?: when (val viewer = fetchViewer(token)) {
                is NetworkResult.Success -> viewer.value.name.takeIf(String::isNotBlank)
                is NetworkResult.Failure -> return viewer
            }
            ?: return NetworkResult.Failure.Http(401, "AniList username could not be resolved from this token.")

        val entriesByMediaId = linkedMapOf<Int, LibraryEntry>()
        var chunk = 1
        var hasNextChunk = true

        while (hasNextChunk) {
            val body = EclipseJson.encodeToString(
                AniListRequest.serializer(),
                AniListRequest(
                    query = query,
                    variables = AniListVariables(
                        userName = resolvedUsername,
                        chunk = chunk,
                        perChunk = 500,
                    ),
                ),
            )

            when (val result = httpClient.postJson(baseUrl, body, token.authorizationHeaders())) {
                is NetworkResult.Success -> try {
                    val response = EclipseJson.decodeFromString(MediaListCollectionEnvelope.serializer(), result.value)
                    val collection = response.data?.collection
                        ?: return NetworkResult.Failure.Serialization(
                            IllegalStateException("AniList library fetch returned no collection data."),
                        )

                    collection.lists.forEach { list ->
                        list.entries.forEach { entry ->
                            val media = entry.media ?: return@forEach
                            entriesByMediaId[media.id] = LibraryEntry(
                                media = media,
                                status = entry.status ?: list.status ?: list.name,
                                progress = entry.progress,
                                progressVolumes = entry.progressVolumes,
                                score = entry.score,
                                updatedAtEpochSeconds = entry.updatedAt,
                            )
                        }
                    }
                    hasNextChunk = collection.hasNextChunk
                    chunk += 1
                } catch (error: SerializationException) {
                    return NetworkResult.Failure.Serialization(error)
                }

                is NetworkResult.Failure -> return result
            }
        }

        return NetworkResult.Success(entriesByMediaId.values.toList())
    }

    suspend fun fetchAiringSchedule(
        daysAhead: Int = 7,
        perPage: Int = 100,
    ): NetworkResult<List<AniListAiringScheduleEntry>> {
        val zoneId = ZoneId.systemDefault()
        val start = LocalDate.now(zoneId).atStartOfDay(zoneId).toEpochSecond().toInt()
        val end = LocalDate.now(zoneId)
            .plusDays(maxOf(daysAhead, 1).toLong() + 1L)
            .atStartOfDay(zoneId)
            .toEpochSecond()
            .toInt()
        val allSchedules = mutableListOf<AniListAiringScheduleEntry>()
        var page = 1
        var hasNextPage = true
        val pageSize = min(perPage, 100)
        val maxPages = 10

        while (hasNextPage && page <= maxPages) {
            val body = EclipseJson.encodeToString(
                AniListRequest.serializer(),
                AniListRequest(
                    query = AIRING_SCHEDULE_QUERY,
                    variables = AniListVariables(
                        page = page,
                        perPage = pageSize,
                        airingAtGreater = start - 1,
                        airingAtLesser = end,
                    ),
                ),
            )

            when (val result = httpClient.postJson(baseUrl, body)) {
                is NetworkResult.Success -> try {
                    val response = EclipseJson.decodeFromString(AiringScheduleEnvelope.serializer(), result.value)
                    allSchedules += response.data.page.airingSchedules
                    hasNextPage = response.data.page.pageInfo.hasNextPage
                    page += 1
                } catch (error: SerializationException) {
                    return NetworkResult.Failure.Serialization(error)
                }

                is NetworkResult.Failure -> return result
            }
        }

        return NetworkResult.Success(allSchedules)
    }

    private suspend fun fetchViewer(accessToken: String): NetworkResult<AniListViewer> {
        val body = EclipseJson.encodeToString(
            AniListRequest.serializer(),
            AniListRequest(
                query = VIEWER_QUERY,
                variables = AniListVariables(),
            ),
        )

        return when (val result = httpClient.postJson(baseUrl, body, accessToken.authorizationHeaders())) {
            is NetworkResult.Success -> try {
                val response = EclipseJson.decodeFromString(ViewerEnvelope.serializer(), result.value)
                NetworkResult.Success(response.data.viewer)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
    }

    @Serializable
    private data class AniListRequest(
        val query: String,
        val variables: AniListVariables,
    )

    @Serializable
    private data class AniListVariables(
        val search: String? = null,
        val page: Int = 1,
        val perPage: Int = 20,
        val id: Int? = null,
        val userName: String? = null,
        val chunk: Int? = null,
        val perChunk: Int? = null,
        val airingAtGreater: Int? = null,
        val airingAtLesser: Int? = null,
    )

    @Serializable
    private data class AniListEnvelope(
        val data: AniListData,
    )

    @Serializable
    private data class AniListData(
        @SerialName("Page") val page: AniListPageResponse,
    )

    @Serializable
    private data class AniListMediaEnvelope(
        val data: AniListMediaData,
    )

    @Serializable
    private data class AniListMediaData(
        @SerialName("Media") val media: AniListMedia,
    )

    @Serializable
    private data class HomeCatalogsEnvelope(
        val data: HomeCatalogsData,
    )

    @Serializable
    private data class HomeCatalogsData(
        val trending: AniListPageResponse = AniListPageResponse(),
        val popular: AniListPageResponse = AniListPageResponse(),
        val topRated: AniListPageResponse = AniListPageResponse(),
        val airing: AniListPageResponse = AniListPageResponse(),
        val upcoming: AniListPageResponse = AniListPageResponse(),
    )

    @Serializable
    private data class MangaCatalogsEnvelope(
        val data: MangaCatalogsData,
    )

    @Serializable
    private data class MangaCatalogsData(
        val trending: AniListPageResponse = AniListPageResponse(),
        val popular: AniListPageResponse = AniListPageResponse(),
        val topRated: AniListPageResponse = AniListPageResponse(),
        val recentlyUpdated: AniListPageResponse = AniListPageResponse(),
    )

    @Serializable
    private data class AiringScheduleEnvelope(
        val data: AiringScheduleData,
    )

    @Serializable
    private data class AiringScheduleData(
        @SerialName("Page") val page: AiringSchedulePage,
    )

    @Serializable
    private data class AiringSchedulePage(
        val pageInfo: AniListPageInfo = AniListPageInfo(),
        @SerialName("airingSchedules") val airingSchedules: List<AniListAiringScheduleEntry> = emptyList(),
    )

    @Serializable
    private data class ViewerEnvelope(
        val data: ViewerData,
    )

    @Serializable
    private data class ViewerData(
        @SerialName("Viewer") val viewer: AniListViewer,
    )

    @Serializable
    private data class AniListViewer(
        val id: Int = 0,
        val name: String = "",
    )

    @Serializable
    private data class MediaListCollectionEnvelope(
        val data: MediaListCollectionData? = null,
    )

    @Serializable
    private data class MediaListCollectionData(
        @SerialName("MediaListCollection") val collection: MediaListCollection? = null,
    )

    @Serializable
    private data class MediaListCollection(
        val hasNextChunk: Boolean = false,
        val lists: List<MediaListGroup> = emptyList(),
    )

    @Serializable
    private data class MediaListGroup(
        val name: String = "",
        val status: String? = null,
        val entries: List<MediaListEntry> = emptyList(),
    )

    @Serializable
    private data class MediaListEntry(
        val status: String? = null,
        val progress: Int = 0,
        val progressVolumes: Int = 0,
        val score: Double = 0.0,
        val updatedAt: Long? = null,
        val media: AniListMedia? = null,
    )

    private companion object {
        const val VIEWER_QUERY = """
            query Viewer {
              Viewer {
                id
                name
              }
            }
        """

        const val ANIME_LIBRARY_QUERY = """
            query AnimeLibrary(${'$'}userName: String, ${'$'}chunk: Int, ${'$'}perChunk: Int) {
              MediaListCollection(
                userName: ${'$'}userName,
                type: ANIME,
                chunk: ${'$'}chunk,
                perChunk: ${'$'}perChunk,
                forceSingleCompletedList: true,
                status_in: [CURRENT, PLANNING, COMPLETED, PAUSED, DROPPED, REPEATING]
              ) {
                hasNextChunk
                lists {
                  name
                  status
                  entries {
                    status
                    progress
                    score(format: POINT_10)
                    updatedAt
                    media {
                      id
                      idMal
                      description(asHtml: false)
                      format
                      season
                      seasonYear
                      episodes
                      duration
                      status
                      bannerImage
                      isAdult
                      type
                      synonyms
                      genres
                      title {
                        romaji
                        english
                        native
                        userPreferred
                      }
                      coverImage {
                        extraLarge
                        large
                        medium
                        color
                      }
                      nextAiringEpisode {
                        episode
                        timeUntilAiring
                        airingAt
                      }
                    }
                  }
                }
              }
            }
        """

        const val MANGA_LIBRARY_QUERY = """
            query MangaLibrary(${'$'}userName: String, ${'$'}chunk: Int, ${'$'}perChunk: Int) {
              MediaListCollection(
                userName: ${'$'}userName,
                type: MANGA,
                chunk: ${'$'}chunk,
                perChunk: ${'$'}perChunk,
                forceSingleCompletedList: true,
                status_in: [CURRENT, PLANNING, COMPLETED, PAUSED, DROPPED, REPEATING]
              ) {
                hasNextChunk
                lists {
                  name
                  status
                  entries {
                    status
                    progress
                    progressVolumes
                    score(format: POINT_10)
                    updatedAt
                    media {
                      id
                      idMal
                      description(asHtml: false)
                      format
                      chapters
                      volumes
                      status
                      bannerImage
                      isAdult
                      type
                      synonyms
                      genres
                      title {
                        romaji
                        english
                        native
                        userPreferred
                      }
                      coverImage {
                        extraLarge
                        large
                        medium
                        color
                      }
                    }
                  }
                }
              }
            }
        """

        const val SEARCH_QUERY = """
            query SearchAnime(${'$'}search: String, ${'$'}page: Int, ${'$'}perPage: Int) {
              Page(page: ${'$'}page, perPage: ${'$'}perPage) {
                pageInfo {
                  currentPage
                  hasNextPage
                  perPage
                  total
                }
                media(search: ${'$'}search, type: ANIME) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
            }
        """

        const val MEDIA_QUERY = """
            query MediaById(${'$'}id: Int) {
              Media(id: ${'$'}id, type: ANIME) {
                id
                idMal
                description(asHtml: false)
                format
                season
                seasonYear
                episodes
                duration
                status
                bannerImage
                isAdult
                type
                synonyms
                genres
                title {
                  romaji
                  english
                  native
                  userPreferred
                }
                coverImage {
                  extraLarge
                  large
                  medium
                  color
                }
                nextAiringEpisode {
                  episode
                  timeUntilAiring
                  airingAt
                }
                relations {
                  edges {
                    relationType
                    node {
                      id
                      idMal
                      description(asHtml: false)
                      format
                      season
                      seasonYear
                      episodes
                      duration
                      status
                      bannerImage
                      isAdult
                      type
                      synonyms
                      genres
                      title {
                        romaji
                        english
                        native
                        userPreferred
                      }
                      coverImage {
                        extraLarge
                        large
                        medium
                        color
                      }
                      nextAiringEpisode {
                        episode
                        timeUntilAiring
                        airingAt
                      }
                    }
                  }
                }
              }
            }
        """

        const val MANGA_SEARCH_QUERY = """
            query SearchManga(${'$'}search: String, ${'$'}page: Int, ${'$'}perPage: Int) {
              Page(page: ${'$'}page, perPage: ${'$'}perPage) {
                pageInfo {
                  currentPage
                  hasNextPage
                  perPage
                  total
                }
                media(search: ${'$'}search, type: MANGA) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
            }
        """

        const val NOVEL_SEARCH_QUERY = """
            query SearchNovels(${'$'}search: String, ${'$'}page: Int, ${'$'}perPage: Int) {
              Page(page: ${'$'}page, perPage: ${'$'}perPage) {
                pageInfo {
                  currentPage
                  hasNextPage
                  perPage
                  total
                }
                media(search: ${'$'}search, type: MANGA, format_in: [NOVEL]) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
            }
        """

        const val HOME_CATALOGS_QUERY = """
            query HomeAnimeCatalogs(${'$'}perPage: Int) {
              trending: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: ANIME, sort: TRENDING_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
              popular: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: ANIME, sort: POPULARITY_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
              topRated: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: ANIME, sort: SCORE_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
              airing: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: ANIME, status: RELEASING, sort: POPULARITY_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
              upcoming: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  season
                  seasonYear
                  episodes
                  duration
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                  nextAiringEpisode {
                    episode
                    timeUntilAiring
                    airingAt
                  }
                }
              }
            }
        """

        const val MANGA_CATALOGS_QUERY = """
            query MangaCatalogs(${'$'}perPage: Int) {
              trending: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, sort: TRENDING_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              popular: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, sort: POPULARITY_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              topRated: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, sort: SCORE_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              recentlyUpdated: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, sort: UPDATED_AT_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
            }
        """

        const val NOVEL_CATALOGS_QUERY = """
            query NovelCatalogs(${'$'}perPage: Int) {
              trending: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, format_in: [NOVEL], sort: TRENDING_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              popular: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, format_in: [NOVEL], sort: POPULARITY_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              topRated: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, format_in: [NOVEL], sort: SCORE_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
              recentlyUpdated: Page(page: 1, perPage: ${'$'}perPage) {
                media(type: MANGA, format_in: [NOVEL], sort: UPDATED_AT_DESC) {
                  id
                  idMal
                  description(asHtml: false)
                  format
                  chapters
                  volumes
                  status
                  bannerImage
                  isAdult
                  synonyms
                  genres
                  title {
                    romaji
                    english
                    native
                    userPreferred
                  }
                  coverImage {
                    extraLarge
                    large
                    medium
                    color
                  }
                }
              }
            }
        """

        const val AIRING_SCHEDULE_QUERY = """
            query AiringSchedule(${'$'}page: Int, ${'$'}perPage: Int, ${'$'}airingAtGreater: Int, ${'$'}airingAtLesser: Int) {
              Page(page: ${'$'}page, perPage: ${'$'}perPage) {
                pageInfo {
                  hasNextPage
                }
                airingSchedules(
                  airingAt_greater: ${'$'}airingAtGreater,
                  airingAt_lesser: ${'$'}airingAtLesser,
                  sort: TIME
                ) {
                  id
                  episode
                  airingAt
                  media {
                    id
                    format
                    title {
                      romaji
                      english
                      native
                      userPreferred
                    }
                    coverImage {
                      extraLarge
                      large
                      medium
                      color
                    }
                  }
                }
              }
            }
        """
    }
}

private fun mediaByMalIdsQuery(
    malIds: List<Int>,
    mediaType: String,
): String {
    val idList = malIds.joinToString(", ")
    return """
        query MediaByMalIds {
          Page(page: 1, perPage: ${malIds.size.coerceAtLeast(1)}) {
            media(type: $mediaType, idMal_in: [$idList]) {
              id
              idMal
              description(asHtml: false)
              format
              season
              seasonYear
              episodes
              chapters
              volumes
              duration
              status
              bannerImage
              isAdult
              type
              synonyms
              genres
              title {
                romaji
                english
                native
                userPreferred
              }
              coverImage {
                extraLarge
                large
                medium
                color
              }
              nextAiringEpisode {
                episode
                timeUntilAiring
                airingAt
              }
            }
          }
        }
    """.trimIndent()
}

private fun String.safeAniListMediaType(): String =
    if (equals("MANGA", ignoreCase = true)) "MANGA" else "ANIME"

private fun String.authorizationHeaders(): Map<String, String> =
    mapOf("Authorization" to "Bearer ${trim()}")
