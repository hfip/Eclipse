package dev.soupy.eclipse.android.core.network

import java.net.URLEncoder
import dev.soupy.eclipse.android.core.model.TMDBContentRatingsResponse
import dev.soupy.eclipse.android.core.model.TMDBCreditsResponse
import dev.soupy.eclipse.android.core.model.TMDBImagesResponse
import dev.soupy.eclipse.android.core.model.TMDBMovieDetail
import dev.soupy.eclipse.android.core.model.TMDBReleaseDatesResponse
import dev.soupy.eclipse.android.core.model.TMDBSearchResponse
import dev.soupy.eclipse.android.core.model.TMDBSearchResult
import dev.soupy.eclipse.android.core.model.TMDBSeasonDetail
import dev.soupy.eclipse.android.core.model.TMDBTVShowDetail
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString

class TmdbService(
    private val apiKey: String,
    private val baseUrl: String = "https://api.themoviedb.org/3",
    defaultLanguage: String = "en-US",
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    @Volatile
    private var language: String = defaultLanguage.normalizedTmdbLanguage()

    fun setLanguage(value: String) {
        language = value.normalizedTmdbLanguage()
    }

    suspend fun searchMulti(
        query: String,
        page: Int = 1,
        includeAdult: Boolean = false,
    ): NetworkResult<TMDBSearchResponse> = decode {
        httpClient.get(
            "$baseUrl/search/multi?api_key=$apiKey&query=${query.urlEncode()}&language=$language&page=$page&include_adult=$includeAdult",
        )
    }

    suspend fun searchMovies(
        query: String,
        page: Int = 1,
        includeAdult: Boolean = false,
    ): NetworkResult<TMDBSearchResponse> = decode {
        httpClient.get(
            "$baseUrl/search/movie?api_key=$apiKey&query=${query.urlEncode()}&language=$language&page=$page&include_adult=$includeAdult",
        )
    }

    suspend fun searchTvShows(
        query: String,
        page: Int = 1,
        includeAdult: Boolean = false,
    ): NetworkResult<TMDBSearchResponse> = decode {
        httpClient.get(
            "$baseUrl/search/tv?api_key=$apiKey&query=${query.urlEncode()}&language=$language&page=$page&include_adult=$includeAdult",
        )
    }

    suspend fun tvShowDetail(showId: Int): NetworkResult<TMDBTVShowDetail> = decode {
        httpClient.get("$baseUrl/tv/$showId?api_key=$apiKey&language=$language&append_to_response=external_ids")
    }

    suspend fun seasonDetail(
        showId: Int,
        seasonNumber: Int,
    ): NetworkResult<TMDBSeasonDetail> = decode {
        httpClient.get("$baseUrl/tv/$showId/season/$seasonNumber?api_key=$apiKey&language=$language")
    }

    suspend fun movieDetail(movieId: Int): NetworkResult<TMDBMovieDetail> = decode {
        httpClient.get("$baseUrl/movie/$movieId?api_key=$apiKey&language=$language&append_to_response=external_ids")
    }

    suspend fun movieImages(movieId: Int): NetworkResult<TMDBImagesResponse> = decode {
        httpClient.get("$baseUrl/movie/$movieId/images?api_key=$apiKey&include_image_language=${language.imageLanguageList()}")
    }

    suspend fun movieCredits(movieId: Int): NetworkResult<TMDBCreditsResponse> = decode {
        httpClient.get("$baseUrl/movie/$movieId/credits?api_key=$apiKey&language=$language")
    }

    suspend fun tvCredits(showId: Int): NetworkResult<TMDBCreditsResponse> = decode {
        httpClient.get("$baseUrl/tv/$showId/credits?api_key=$apiKey&language=$language")
    }

    suspend fun tvImages(showId: Int): NetworkResult<TMDBImagesResponse> = decode {
        httpClient.get("$baseUrl/tv/$showId/images?api_key=$apiKey&include_image_language=${language.imageLanguageList()}")
    }

    suspend fun movieRecommendations(movieId: Int, page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/movie/$movieId/recommendations?api_key=$apiKey&language=$language&page=$page")

    suspend fun tvRecommendations(showId: Int, page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/tv/$showId/recommendations?api_key=$apiKey&language=$language&page=$page")

    suspend fun movieReleaseDates(movieId: Int): NetworkResult<TMDBReleaseDatesResponse> = decode {
        httpClient.get("$baseUrl/movie/$movieId/release_dates?api_key=$apiKey")
    }

    suspend fun tvContentRatings(showId: Int): NetworkResult<TMDBContentRatingsResponse> = decode {
        httpClient.get("$baseUrl/tv/$showId/content_ratings?api_key=$apiKey")
    }

    suspend fun trendingAll(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/trending/all/week?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun popularMovies(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/movie/popular?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun nowPlayingMovies(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/movie/now_playing?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun upcomingMovies(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/movie/upcoming?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun topRatedMovies(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/movie/top_rated?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun popularTv(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/tv/popular?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun topRatedTv(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/tv/top_rated?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun airingTodayTv(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/tv/airing_today?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun onTheAirTv(page: Int = 1): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/tv/on_the_air?api_key=$apiKey&language=$language&page=$page&include_adult=false")

    suspend fun discoverByGenre(
        genreId: Int,
        mediaType: String = "movie",
        page: Int = 1,
    ): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/discover/$mediaType?api_key=$apiKey&language=$language&page=$page&with_genres=$genreId&include_adult=false")

    suspend fun discoverByNetwork(
        networkId: Int,
        page: Int = 1,
    ): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/discover/tv?api_key=$apiKey&language=$language&page=$page&with_networks=$networkId&include_adult=false")

    suspend fun discoverByCompany(
        companyId: Int,
        mediaType: String = "movie",
        page: Int = 1,
    ): NetworkResult<List<TMDBSearchResult>> =
        decodeResults("$baseUrl/discover/$mediaType?api_key=$apiKey&language=$language&page=$page&with_companies=$companyId&include_adult=false")

    private suspend fun decodeResults(url: String): NetworkResult<List<TMDBSearchResult>> =
        when (val result = httpClient.get(url)) {
            is NetworkResult.Success -> try {
                NetworkResult.Success(EclipseJson.decodeFromString<TMDBSearchResponse>(result.value).results)
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }

    private suspend inline fun <reified T> decode(request: () -> NetworkResult<String>): NetworkResult<T> =
        when (val result = request()) {
            is NetworkResult.Success -> try {
                NetworkResult.Success(EclipseJson.decodeFromString<T>(result.value))
            } catch (error: SerializationException) {
                NetworkResult.Failure.Serialization(error)
            }

            is NetworkResult.Failure -> result
        }
}

private fun String.urlEncode(): String = URLEncoder.encode(this, Charsets.UTF_8)

private fun String.normalizedTmdbLanguage(): String =
    trim().takeIf { it.isNotBlank() } ?: "en-US"

private fun String.imageLanguageList(): String {
    val prefix = substringBefore('-').takeIf { it.isNotBlank() } ?: "en"
    return "$prefix,en,null"
}

