package dev.soupy.eclipse.android.core.network

import dev.soupy.eclipse.android.core.model.SkipSegment
import dev.soupy.eclipse.android.core.model.SkipType
import java.net.URLEncoder
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

class IntroDbService(
    private val baseUrl: String = "https://api.theintrodb.org/v2",
    private val appBaseUrl: String = "https://api.introdb.app",
    private val httpClient: EclipseHttpClient = EclipseHttpClient(),
) {
    suspend fun fetchSkipTimes(
        tmdbId: Int,
        seasonNumber: Int? = null,
        episodeNumber: Int? = null,
        episodeDurationSeconds: Double = 0.0,
    ): NetworkResult<List<SkipSegment>> {
        val url = buildString {
            append("$baseUrl/media?tmdb_id=$tmdbId")
            seasonNumber?.let { append("&season=$it") }
            episodeNumber?.let { append("&episode=$it") }
        }

        return when (val result = httpClient.get(url)) {
            is NetworkResult.Success -> decode(result.value, episodeDurationSeconds)
            is NetworkResult.Failure.Http -> NetworkResult.Success(emptyList())
            is NetworkResult.Failure.Connectivity -> result
            is NetworkResult.Failure.Serialization -> result
        }
    }

    suspend fun fetchIntroDbAppSkipTimes(
        imdbId: String,
        seasonNumber: Int? = null,
        episodeNumber: Int? = null,
        episodeDurationSeconds: Double = 0.0,
    ): NetworkResult<List<SkipSegment>> {
        val cleanId = imdbId.trim().takeIf { it.isNotBlank() } ?: return NetworkResult.Success(emptyList())
        val url = buildString {
            append("$appBaseUrl/segments?imdb_id=")
            append(URLEncoder.encode(cleanId, Charsets.UTF_8.name()))
            seasonNumber?.let { append("&season=$it") }
            episodeNumber?.let { append("&episode=$it") }
        }

        return when (val result = httpClient.get(url)) {
            is NetworkResult.Success -> decodeIntroDbAppSkipSegments(result.value, episodeDurationSeconds)
            is NetworkResult.Failure.Http -> NetworkResult.Success(emptyList())
            is NetworkResult.Failure.Connectivity -> result
            is NetworkResult.Failure.Serialization -> result
        }
    }

    private fun decode(
        body: String,
        episodeDurationSeconds: Double,
    ): NetworkResult<List<SkipSegment>> = try {
        val response = EclipseJson.decodeFromString<IntroDbResponse>(body)
        val segments = buildList {
            response.intro.orEmpty().mapToSegments(SkipType.INTRO, episodeDurationSeconds).let(::addAll)
            response.recap.orEmpty().mapToSegments(SkipType.RECAP, episodeDurationSeconds).let(::addAll)
            response.credits.orEmpty().mapToSegments(SkipType.OUTRO, episodeDurationSeconds).let(::addAll)
            response.preview.orEmpty().mapToSegments(SkipType.PREVIEW, episodeDurationSeconds).let(::addAll)
        }.sortedBy(SkipSegment::startTime)

        NetworkResult.Success(segments)
    } catch (error: SerializationException) {
        NetworkResult.Failure.Serialization(error)
    }

}

internal fun decodeIntroDbAppSkipSegments(
    body: String,
    episodeDurationSeconds: Double,
): NetworkResult<List<SkipSegment>> = try {
    val root = EclipseJson.parseToJsonElement(body).jsonObject
    val segments = buildList {
        root["intro"].introDbAppSegments(SkipType.INTRO, episodeDurationSeconds).let(::addAll)
        root["recap"].introDbAppSegments(SkipType.RECAP, episodeDurationSeconds).let(::addAll)
        root["outro"].introDbAppSegments(SkipType.OUTRO, episodeDurationSeconds).let(::addAll)
        root["credits"].introDbAppSegments(SkipType.OUTRO, episodeDurationSeconds).let(::addAll)
        root["preview"].introDbAppSegments(SkipType.PREVIEW, episodeDurationSeconds).let(::addAll)
    }.sortedBy(SkipSegment::startTime)
        .distinctBy { segment ->
            "${segment.type.id}:${segment.startTime.toInt()}:${segment.endTime.toInt()}"
        }

    NetworkResult.Success(segments)
} catch (error: IllegalArgumentException) {
    NetworkResult.Failure.Serialization(SerializationException("Unexpected introdb.app response.", error))
}

@Serializable
private data class IntroDbResponse(
    @SerialName("tmdb_id") val tmdbId: Int? = null,
    val type: String? = null,
    val intro: List<IntroDbSegment>? = null,
    val recap: List<IntroDbSegment>? = null,
    val credits: List<IntroDbSegment>? = null,
    val preview: List<IntroDbSegment>? = null,
)

@Serializable
private data class IntroDbSegment(
    @SerialName("start_ms") val startMs: Int? = null,
    @SerialName("end_ms") val endMs: Int? = null,
    val confidence: Double? = null,
    @SerialName("submission_count") val submissionCount: Int? = null,
)

private fun List<IntroDbSegment>.mapToSegments(
    type: SkipType,
    episodeDurationSeconds: Double,
): List<SkipSegment> = mapNotNull { segment ->
    val maxDuration = if (episodeDurationSeconds > 0) {
        episodeDurationSeconds
    } else {
        Double.MAX_VALUE
    }
    SkipSegment(
        startTime = segment.startMs?.let { it / 1_000.0 } ?: 0.0,
        endTime = segment.endMs?.let { it / 1_000.0 } ?: maxDuration,
        type = type,
    ).clamped(episodeDurationSeconds)
}

private fun JsonElement?.introDbAppSegments(
    type: SkipType,
    episodeDurationSeconds: Double,
): List<SkipSegment> {
    val segmentElements = when (this) {
        is JsonArray -> this
        is JsonObject -> {
            val nested = this["segments"]
            when (nested) {
                is JsonArray -> nested
                is JsonObject -> JsonArray(listOf(nested))
                else -> JsonArray(listOf(this))
            }
        }
        JsonNull,
        null -> return emptyList()
        else -> return emptyList()
    }
    return segmentElements.mapNotNull { element ->
        val segment = element as? JsonObject ?: return@mapNotNull null
        val start = segment.secondsValue("start_sec")
            ?: segment.millisecondsValue("start_ms")
            ?: 0.0
        val end = segment.secondsValue("end_sec")
            ?: segment.millisecondsValue("end_ms")
            ?: episodeDurationSeconds.takeIf { it > 0.0 }
            ?: return@mapNotNull null
        SkipSegment(
            startTime = start,
            endTime = end,
            type = type,
        ).clamped(episodeDurationSeconds)
    }
}

private fun JsonObject.secondsValue(key: String): Double? =
    primitiveValue(key)?.asDoubleOrClockSeconds()

private fun JsonObject.millisecondsValue(key: String): Double? =
    primitiveValue(key)?.let { value ->
        value.doubleOrNull?.div(1_000.0)
            ?: value.intOrNull?.div(1_000.0)
            ?: value.contentOrNull?.toDoubleOrNull()?.div(1_000.0)
    }

private fun JsonObject.primitiveValue(key: String): JsonPrimitive? =
    this[key] as? JsonPrimitive

private fun JsonPrimitive.asDoubleOrClockSeconds(): Double? {
    doubleOrNull?.let { return it }
    intOrNull?.let { return it.toDouble() }
    val raw = contentOrNull?.trim().orEmpty()
    if (raw.isBlank()) return null
    raw.toDoubleOrNull()?.let { return it }
    val parts = raw.split(':').mapNotNull(String::toDoubleOrNull)
    return when (parts.size) {
        2 -> parts[0] * 60.0 + parts[1]
        3 -> parts[0] * 3600.0 + parts[1] * 60.0 + parts[2]
        else -> null
    }
}
