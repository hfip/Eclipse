package dev.soupy.eclipse.android.core.model
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder

private val qualityPatterns = listOf(
    "2160p" to 1.00,
    "4k" to 1.00,
    "1080p" to 0.90,
    "720p" to 0.72,
    "480p" to 0.48,
    "cam" to -0.35,
    "hdcam" to -0.35,
    "telesync" to -0.30,
    " ts " to -0.30,
)

@Serializable
data class StremioManifestBehaviorHints(
    val configurable: Boolean = false,
    @SerialName("configurationRequired") val configurationRequired: Boolean = false,
)

@Serializable(with = StremioResourceDescriptorSerializer::class)
data class StremioResourceDescriptor(
    val name: String = "",
    val types: List<String> = emptyList(),
    @SerialName("idPrefixes") val idPrefixes: List<String> = emptyList(),
)

@Serializable
data class StremioManifest(
    val id: String = "",
    val version: String = "",
    val name: String = "",
    val description: String? = null,
    @SerialName("logo") val logoUrl: String? = null,
    val background: String? = null,
    val resources: List<StremioResourceDescriptor> = emptyList(),
    @SerialName("idPrefixes") val idPrefixes: List<String> = emptyList(),
    val types: List<String> = emptyList(),
    val catalogs: List<StremioCatalog> = emptyList(),
    @SerialName("behaviorHints") val behaviorHints: StremioManifestBehaviorHints = StremioManifestBehaviorHints(),
)

@Serializable
data class StremioCatalog(
    val type: String = "",
    val id: String = "",
    val name: String? = null,
    val extra: List<StremioCatalogExtra> = emptyList(),
) {
    val supportsSearch: Boolean
        get() = extra.any { catalogExtra -> catalogExtra.name == "search" }

    val canSearchWithQueryOnly: Boolean
        get() = supportsSearch && extra.all { catalogExtra ->
            !catalogExtra.isRequired || catalogExtra.name == "search"
        }

    fun supportsType(requestedType: String): Boolean =
        type == requestedType || (requestedType == "series" && type == "tv")
}

@Serializable(with = StremioCatalogExtraSerializer::class)
data class StremioCatalogExtra(
    val name: String = "",
    @SerialName("isRequired") val isRequired: Boolean = false,
    val options: List<String> = emptyList(),
    @SerialName("optionsLimit") val optionsLimit: Int? = null,
)

@Serializable
data class StremioProxyHeaders(
    val request: Map<String, String> = emptyMap(),
    val response: Map<String, String> = emptyMap(),
)

@Serializable(with = StremioSubtitleSerializer::class)
data class StremioSubtitle(
    val id: String? = null,
    val lang: String? = null,
    val label: String? = null,
    val url: String? = null,
    val name: String? = null,
    val title: String? = null,
)

@Serializable
data class StremioStreamBehaviorHints(
    @SerialName("bingeGroup") val bingeGroup: String? = null,
    @SerialName("filename") val filename: String? = null,
    @SerialName("notWebReady") val notWebReady: Boolean = false,
    @SerialName("proxyHeaders") val proxyHeaders: StremioProxyHeaders? = null,
)

@Serializable
data class StremioStream(
    val name: String? = null,
    val title: String? = null,
    val description: String? = null,
    val url: String? = null,
    @SerialName("ytId") val ytId: String? = null,
    val infoHash: String? = null,
    val fileIdx: Int? = null,
    val subtitles: List<StremioSubtitle> = emptyList(),
    @SerialName("behaviorHints") val behaviorHints: StremioStreamBehaviorHints? = null,
)

@Serializable
data class StremioStreamResponse(
    val streams: List<StremioStream> = emptyList(),
)

@Serializable
data class StremioSubtitleResponse(
    val subtitles: List<StremioSubtitle> = emptyList(),
)

@Serializable
data class StremioCatalogResponse(
    val metas: List<StremioMetaPreview> = emptyList(),
)

@Serializable(with = StremioMetaResponseSerializer::class)
data class StremioMetaResponse(
    val meta: StremioMetaPreview? = null,
)

@Serializable
data class StremioMetaPreview(
    val id: String = "",
    val type: String? = null,
    val name: String = "",
    val poster: String? = null,
    val description: String? = null,
    @SerialName("releaseInfo") val releaseInfo: String? = null,
    val released: String? = null,
    val videos: List<StremioVideo> = emptyList(),
    @SerialName("behaviorHints") val behaviorHints: StremioMetaBehaviorHints? = null,
)

@Serializable
data class StremioMetaBehaviorHints(
    @SerialName("defaultVideoId") val defaultVideoId: String? = null,
)

@Serializable
data class StremioVideo(
    val id: String = "",
    val title: String? = null,
    val released: String? = null,
    val season: Int? = null,
    val episode: Int? = null,
    val streams: List<StremioStream> = emptyList(),
)

@Serializable
data class StremioAddon(
    val transportUrl: String,
    val manifest: StremioManifest,
    val enabled: Boolean = true,
    val sortIndex: Int = 0,
)

@Serializable
data class StremioContentIdRequest(
    val tmdbId: Int,
    val imdbId: String? = null,
    val type: String,
    val season: Int? = null,
    val episode: Int? = null,
    val anilistId: Int? = null,
)

val StremioStream.isDirectHttp: Boolean
    get() = url?.startsWith("http://") == true || url?.startsWith("https://") == true

val StremioStream.isTorrentLike: Boolean
    get() = !infoHash.isNullOrBlank() ||
        url?.startsWith("magnet:", ignoreCase = true) == true ||
        url?.contains("btih:", ignoreCase = true) == true ||
        url
            ?.substringBefore('?')
            ?.substringBefore('#')
            ?.endsWith(".torrent", ignoreCase = true) == true

fun StremioManifest.supportsResource(name: String): Boolean =
    resources.any { resource -> resource.name.equals(name, ignoreCase = true) }

val StremioManifest.searchableCatalogs: List<StremioCatalog>
    get() = catalogs.filter(StremioCatalog::canSearchWithQueryOnly)

fun StremioManifest.buildContentId(
    request: StremioContentIdRequest,
    resourceName: String = "stream",
): String? = buildContentIds(request = request, resourceName = resourceName).firstOrNull()

fun StremioManifest.buildContentIds(
    request: StremioContentIdRequest,
    resourceName: String = "stream",
): List<String> {
    val resourcePrefixes = resources
        .filter { resource -> resource.name.equals(resourceName, ignoreCase = true) }
        .flatMap(StremioResourceDescriptor::idPrefixes)
        .filter(String::isNotBlank)
    val prefixes = resourcePrefixes.ifEmpty { idPrefixes }.map { prefix -> prefix.lowercase() }
    val supportsAny = prefixes.isEmpty()
    val supportsImdb = supportsAny || prefixes.any { prefix ->
        prefix == "tt" || prefix.startsWith("tt") || prefix == "imdb" || prefix == "imdb:"
    }
    val supportsImdbNamespace = prefixes.any { prefix -> prefix == "imdb:" }
    val supportsTmdb = supportsAny || prefixes.any { prefix ->
        prefix == "tmdb" || prefix.startsWith("tmdb:")
    }
    val supportsAniList = supportsAny || prefixes.any { prefix ->
        prefix == "anilist" || prefix == "anilist:"
    }
    val candidates = mutableListOf<String>()

    if (supportsImdb) {
        val imdb = request.imdbId?.takeIf { it.isNotBlank() }?.let { value ->
            if (value.startsWith("tt")) value else "tt$value"
        }
        if (imdb != null) {
            val imdbId = if (request.type == "series" && request.season != null && request.episode != null) {
                "$imdb:${request.season}:${request.episode}"
            } else {
                imdb
            }
            candidates += imdbId

            if (supportsImdbNamespace) {
                candidates += if (request.type == "series" && request.season != null && request.episode != null) {
                    "imdb:$imdb:${request.season}:${request.episode}"
                } else {
                    "imdb:$imdb"
                }
            }
        }
    }

    if (supportsTmdb) {
        candidates += if (request.type == "series" && request.season != null && request.episode != null) {
            "tmdb:${request.tmdbId}:${request.season}:${request.episode}"
        } else {
            "tmdb:${request.tmdbId}"
        }
    }

    if (supportsAniList && request.anilistId != null) {
        candidates += if (request.type == "series" && request.season != null && request.episode != null) {
            "anilist:${request.anilistId}:${request.season}:${request.episode}"
        } else {
            "anilist:${request.anilistId}"
        }
    }

    return candidates.distinct()
}

val StremioSubtitle.displayLabel: String
    get() = listOfNotNull(label, name, title, lang?.uppercase(), id)
        .firstOrNull { it.isNotBlank() }
        ?: "OpenSubtitles"

object StremioResourceDescriptorSerializer : KSerializer<StremioResourceDescriptor> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("StremioResourceDescriptor") {
        element<String>("name")
        element<List<String>>("types", isOptional = true)
        element<List<String>>("idPrefixes", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): StremioResourceDescriptor {
        val input = decoder as? JsonDecoder ?: error("StremioResourceDescriptor requires JSON decoding")
        return when (val element = input.decodeJsonElement()) {
            is JsonPrimitive -> StremioResourceDescriptor(name = element.contentOrNull.orEmpty())
            else -> input.json.decodeFromJsonElement<StremioResourceDescriptorSurrogate>(element).toResourceDescriptor()
        }
    }

    override fun serialize(encoder: Encoder, value: StremioResourceDescriptor) {
        val output = encoder as? JsonEncoder ?: error("StremioResourceDescriptor requires JSON encoding")
        output.encodeJsonElement(
            output.json.encodeToJsonElement(
                StremioResourceDescriptorSurrogate(
                    name = value.name,
                    types = value.types,
                    idPrefixes = value.idPrefixes,
                ),
            ),
        )
    }
}

object StremioSubtitleSerializer : KSerializer<StremioSubtitle> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("StremioSubtitle") {
        element<String>("id", isOptional = true)
        element<String>("lang", isOptional = true)
        element<String>("label", isOptional = true)
        element<String>("url", isOptional = true)
        element<String>("name", isOptional = true)
        element<String>("title", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): StremioSubtitle {
        val input = decoder as? JsonDecoder ?: error("StremioSubtitle requires JSON decoding")
        val surrogate = input.json.decodeFromJsonElement<StremioSubtitleSurrogate>(input.decodeJsonElement())
        return StremioSubtitle(
            id = surrogate.id?.jsonPrimitive?.contentOrNull,
            lang = surrogate.lang,
            label = surrogate.label,
            url = surrogate.url,
            name = surrogate.name,
            title = surrogate.title,
        )
    }

    override fun serialize(encoder: Encoder, value: StremioSubtitle) {
        val output = encoder as? JsonEncoder ?: error("StremioSubtitle requires JSON encoding")
        output.encodeJsonElement(
            output.json.encodeToJsonElement(
                StremioSubtitleSurrogate(
                    id = value.id?.let(::JsonPrimitive),
                    lang = value.lang,
                    label = value.label,
                    url = value.url,
                    name = value.name,
                    title = value.title,
                ),
            ),
        )
    }
}

object StremioCatalogExtraSerializer : KSerializer<StremioCatalogExtra> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("StremioCatalogExtra") {
        element<String>("name")
        element<Boolean>("isRequired", isOptional = true)
        element<List<String>>("options", isOptional = true)
        element<Int>("optionsLimit", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): StremioCatalogExtra {
        val input = decoder as? JsonDecoder ?: error("StremioCatalogExtra requires JSON decoding")
        return when (val element = input.decodeJsonElement()) {
            is JsonPrimitive -> StremioCatalogExtra(name = element.contentOrNull.orEmpty())
            else -> input.json.decodeFromJsonElement<StremioCatalogExtraSurrogate>(element).toCatalogExtra()
        }
    }

    override fun serialize(encoder: Encoder, value: StremioCatalogExtra) {
        val output = encoder as? JsonEncoder ?: error("StremioCatalogExtra requires JSON encoding")
        output.encodeJsonElement(
            output.json.encodeToJsonElement(
                StremioCatalogExtraSurrogate(
                    name = value.name,
                    isRequired = value.isRequired,
                    options = value.options,
                    optionsLimit = value.optionsLimit,
                ),
            ),
        )
    }
}

object StremioMetaResponseSerializer : KSerializer<StremioMetaResponse> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("StremioMetaResponse") {
        element<StremioMetaPreview>("meta", isOptional = true)
    }

    override fun deserialize(decoder: Decoder): StremioMetaResponse {
        val input = decoder as? JsonDecoder ?: error("StremioMetaResponse requires JSON decoding")
        val root = input.decodeJsonElement() as? JsonObject ?: return StremioMetaResponse()
        val metaElement = root["meta"] ?: return StremioMetaResponse()
        val meta = when (metaElement) {
            is JsonArray -> metaElement.firstOrNull()?.let { element ->
                runCatching { input.json.decodeFromJsonElement<StremioMetaPreview>(element) }.getOrNull()
            }
            is JsonObject -> runCatching {
                input.json.decodeFromJsonElement<StremioMetaPreview>(metaElement)
            }.getOrNull()
            else -> null
        }
        return StremioMetaResponse(meta = meta)
    }

    override fun serialize(encoder: Encoder, value: StremioMetaResponse) {
        val output = encoder as? JsonEncoder ?: error("StremioMetaResponse requires JSON encoding")
        output.encodeJsonElement(output.json.encodeToJsonElement(value.meta?.let { mapOf("meta" to it) } ?: emptyMap()))
    }
}

@Serializable
private data class StremioResourceDescriptorSurrogate(
    val name: String = "",
    val types: List<String> = emptyList(),
    @SerialName("idPrefixes") val idPrefixes: List<String> = emptyList(),
) {
    fun toResourceDescriptor(): StremioResourceDescriptor = StremioResourceDescriptor(
        name = name,
        types = types,
        idPrefixes = idPrefixes,
    )
}

@Serializable
private data class StremioSubtitleSurrogate(
    val id: kotlinx.serialization.json.JsonElement? = null,
    val lang: String? = null,
    val label: String? = null,
    val url: String? = null,
    val name: String? = null,
    val title: String? = null,
)

@Serializable
private data class StremioCatalogExtraSurrogate(
    val name: String = "",
    @SerialName("isRequired") val isRequired: Boolean = false,
    val options: List<String> = emptyList(),
    @SerialName("optionsLimit") val optionsLimit: Int? = null,
) {
    fun toCatalogExtra(): StremioCatalogExtra = StremioCatalogExtra(
        name = name,
        isRequired = isRequired,
        options = options,
        optionsLimit = optionsLimit,
    )
}

fun StremioStream.qualityScore(): Double {
    val haystack = listOfNotNull(
        name,
        title,
        description,
        behaviorHints?.filename,
    ).joinToString(" ").lowercase()

    val base = qualityPatterns.firstOrNull { (needle, _) -> haystack.contains(needle) }?.second ?: 0.50
    val hdrBoost = if (haystack.contains("hdr") || haystack.contains("dolby vision") || haystack.contains("dv")) 0.04 else 0.0
    val remuxBoost = if (haystack.contains("remux") || haystack.contains("bluray")) 0.04 else 0.0
    val webBoost = if (haystack.contains("web-dl") || haystack.contains("webrip")) 0.02 else 0.0
    val notWebReadyPenalty = if (behaviorHints?.notWebReady == true) 0.08 else 0.0

    return (base + hdrBoost + remuxBoost + webBoost - notWebReadyPenalty).coerceIn(0.0, 1.0)
}


