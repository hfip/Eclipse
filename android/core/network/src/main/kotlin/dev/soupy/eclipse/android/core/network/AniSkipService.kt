package dev.soupy.eclipse.android.core.network

import dev.soupy.eclipse.android.core.model.SkipSegment
import dev.soupy.eclipse.android.core.model.SkipType
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString

class AniSkipService(
    private val baseUrl: String = "https://api.aniskip.com/v2",
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    suspend fun fetchSkipTimes(
        malId: Int,
        episodeNumber: Int,
        episodeDurationSeconds: Double,
    ): NetworkResult<List<SkipSegment>> {
        val url = aniSkipTimesUrl(
            baseUrl = baseUrl,
            malId = malId,
            episodeNumber = episodeNumber,
            episodeDurationSeconds = episodeDurationSeconds,
        )

        return when (val result = httpClient.get(url)) {
            is NetworkResult.Success -> decode(result.value, episodeDurationSeconds)
            is NetworkResult.Failure.Http -> NetworkResult.Success(emptyList())
            is NetworkResult.Failure.Connectivity -> result
            is NetworkResult.Failure.Serialization -> result
        }
    }

    private fun decode(
        body: String,
        episodeDurationSeconds: Double,
    ): NetworkResult<List<SkipSegment>> = try {
        val response = EclipseJson.decodeFromString<AniSkipResponse>(body)
        val segments = if (response.found) {
            response.results.orEmpty()
                .mapNotNull { result ->
                    val type = result.skipType.toSkipType() ?: return@mapNotNull null
                    SkipSegment(
                        startTime = result.interval.startTime,
                        endTime = result.interval.endTime,
                        type = type,
                    ).clamped(episodeDurationSeconds)
                }
                .sortedBy(SkipSegment::startTime)
        } else {
            emptyList()
        }

        NetworkResult.Success(segments)
    } catch (error: SerializationException) {
        NetworkResult.Failure.Serialization(error)
    }
}

internal fun aniSkipTimesUrl(
    baseUrl: String,
    malId: Int,
    episodeNumber: Int,
    episodeDurationSeconds: Double,
): String {
    val episodeLength = if (episodeDurationSeconds.isFinite() && episodeDurationSeconds > 0) {
        episodeDurationSeconds.toInt()
    } else {
        0
    }
    return "$baseUrl/skip-times/$malId/$episodeNumber" +
        "?types%5B%5D=op&types%5B%5D=ed&types%5B%5D=recap" +
        "&types%5B%5D=mixed-op&types%5B%5D=mixed-ed&episodeLength=$episodeLength"
}

@Serializable
private data class AniSkipResponse(
    val found: Boolean,
    val results: List<AniSkipResult>? = null,
    val statusCode: Int = 0,
)

@Serializable
private data class AniSkipResult(
    val interval: AniSkipInterval,
    val skipType: String,
    val skipId: String? = null,
    val episodeLength: Double = 0.0,
)

@Serializable
private data class AniSkipInterval(
    val startTime: Double,
    val endTime: Double,
)

private fun String.toSkipType(): SkipType? = when (this) {
    "op", "mixed-op" -> SkipType.INTRO
    "ed", "mixed-ed" -> SkipType.OUTRO
    "recap" -> SkipType.RECAP
    else -> null
}
