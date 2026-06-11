package dev.soupy.eclipse.android.core.model

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64
import kotlin.math.roundToInt
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject

@Serializable
data class BackupCollection(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val name: String = "",
    val items: List<JsonElement> = emptyList(),
    val description: String? = null,
)

@Serializable
data class BackupProgressEntry(
    val key: String,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val updatedAt: Long = 0,
    val context: EpisodePlaybackContext? = null,
)

@Serializable
data class MovieProgressBackup(
    val id: Int,
    val title: String = "",
    @SerialName("posterURL") val posterUrl: String? = null,
    val currentTime: Double = 0.0,
    val totalDuration: Double = 0.0,
    val isWatched: Boolean = false,
    val lastUpdated: String? = null,
    val lastServiceId: String? = null,
    val lastHref: String? = null,
)

@Serializable
data class EpisodeProgressBackup(
    val id: String = "",
    val showId: Int,
    val seasonNumber: Int,
    val episodeNumber: Int,
    val anilistMediaId: Int? = null,
    val isAnime: Boolean = false,
    val currentTime: Double = 0.0,
    val totalDuration: Double = 0.0,
    val isWatched: Boolean = false,
    val lastUpdated: String? = null,
    val lastServiceId: String? = null,
    val lastHref: String? = null,
    val playbackContext: EpisodePlaybackContext? = null,
)

@Serializable
data class ShowMetadataBackup(
    val showId: Int,
    val title: String,
    @SerialName("posterURL") val posterUrl: String? = null,
)

@Serializable
data class ProgressDataBackup(
    val movieProgress: List<MovieProgressBackup> = emptyList(),
    val episodeProgress: List<EpisodeProgressBackup> = emptyList(),
    val showMetadata: Map<String, ShowMetadataBackup> = emptyMap(),
)

@Serializable
data class BackupCatalog(
    val id: String = "",
    val title: String? = null,
    val type: String? = null,
    val manifestUrl: String? = null,
    val name: String? = null,
    val source: String? = null,
    val isEnabled: Boolean = true,
    val order: Int = 0,
    val displayStyle: String = "standard",
) {
    val displayName: String
        get() = name ?: title ?: id

    val resolvedSource: String
        get() = source ?: type ?: "Local"
}

@Serializable
data class ServiceBackup(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val name: String = "",
    val manifestUrl: String? = null,
    val scriptUrl: String? = null,
    val transportUrl: String? = null,
    val enabled: Boolean = true,
    val sortIndex: Long = 0,
    val sourceKind: String? = null,
    val configurationJson: String? = null,
    val url: String? = null,
    val jsonMetadata: String? = null,
    val jsScript: String? = null,
    val isActive: Boolean? = null,
) {
    val active: Boolean
        get() = isActive ?: enabled

    val resolvedName: String
        get() = name.ifBlank { id.ifBlank { url ?: scriptUrl ?: manifestUrl ?: "Service" } }

    val resolvedManifestUrl: String?
        get() = manifestUrl ?: url?.takeIf { jsScript.isNullOrBlank() }

    val resolvedScriptUrl: String?
        get() = scriptUrl ?: url?.takeIf { !jsScript.isNullOrBlank() }
}

@Serializable
data class StremioAddonBackup(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val name: String = "",
    val manifestUrl: String? = null,
    val transportUrl: String? = null,
    val enabled: Boolean = true,
    val sortIndex: Long = 0,
    val sourceKind: String? = null,
    val configuredURL: String? = null,
    @SerialName("manifestJSON") val manifestJson: String? = null,
    val isActive: Boolean? = null,
) {
    val active: Boolean
        get() = isActive ?: enabled

    val resolvedTransportUrl: String
        get() = transportUrl ?: configuredURL ?: manifestUrl ?: id

    val resolvedManifestId: String
        get() = id.ifBlank { resolvedTransportUrl }

    val resolvedName: String
        get() = name.ifBlank { resolvedManifestId }
}

@Serializable
data class ModuleBackup(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val id: String = "",
    val name: String = "",
    val manifestUrl: String? = null,
    val enabled: Boolean = true,
    val moduleData: JsonElement = JsonObject(emptyMap()),
    val localPath: String? = null,
    val moduleurl: String? = null,
    val isActive: Boolean? = null,
) {
    val active: Boolean
        get() = isActive ?: enabled
}

@Serializable
data class TrackerAccountSnapshot(
    val service: String,
    val username: String = "",
    val accessToken: String = "",
    val refreshToken: String? = null,
    val expiresAt: String? = null,
    val userId: String = "",
    val isConnected: Boolean = true,
)

@Serializable
data class TrackerStateSnapshot(
    val accounts: List<TrackerAccountSnapshot> = emptyList(),
    val syncEnabled: Boolean = true,
    val autoSyncRatings: Boolean = false,
    val mergeTraktContinueWatching: Boolean = false,
    val lastSyncDate: String? = null,
    val provider: String? = null,
    val accessToken: String? = null,
    val refreshToken: String? = null,
    val userName: String? = null,
)

@Serializable
data class MangaProgressBackup(
    val readChapterNumbers: Set<String> = emptySet(),
    val lastReadChapter: String? = null,
    val lastReadDate: String? = null,
    val pagePositions: Map<String, Int> = emptyMap(),
    val title: String? = null,
    @SerialName("coverURL") val coverUrl: String? = null,
    val format: String? = null,
    val totalChapters: Int? = null,
    val moduleUUID: String? = null,
    val contentParams: String? = null,
    val isNovel: Boolean? = null,
)

@Serializable
data class BackupData(
    @Serializable(with = StringOrNumberAsStringSerializer::class)
    val version: String = "1.0",
    val createdDate: String? = null,
    @Serializable(with = BackupColorStringSerializer::class)
    val accentColor: String? = null,
    @Serializable(with = BackupColorStringSerializer::class)
    val settingsGradientColor: String? = null,
    val tmdbLanguage: String = "en-US",
    val selectedAppearance: String = "system",
    val enableSubtitlesByDefault: Boolean = false,
    val defaultSubtitleLanguage: String = "eng",
    val enableVLCSubtitleEditMenu: Boolean = true,
    val preferredAnimeAudioLanguage: String = "jpn",
    @Serializable(with = InAppPlayerBackupSerializer::class)
    val inAppPlayer: InAppPlayer = InAppPlayer.MPV,
    @SerialName("playerChoice")
    @Serializable(with = InAppPlayerBackupSerializer::class)
    val legacyPlayerChoice: InAppPlayer? = null,
    val showScheduleTab: Boolean = true,
    val showLocalScheduleTime: Boolean = true,
    val useClassicScheduleUI: Boolean = false,
    val defaultScheduleMode: String = ScheduleMode.Default.rawValue,
    val defaultPlaybackSpeed: Double = 1.0,
    val holdSpeedPlayer: Double = 2.0,
    val externalPlayer: String = "none",
    val preferDownloadedMedia: Boolean = false,
    val alwaysLandscape: Boolean = false,
    val aniSkipEnabled: Boolean = true,
    val introDBEnabled: Boolean = true,
    val aniSkipAutoSkip: Boolean = false,
    val skip85sEnabled: Boolean = false,
    val skip85sAlwaysVisible: Boolean = false,
    val showNextEpisodeButton: Boolean = true,
    val showVLCEpisodeBrowserButton: Boolean = true,
    val showNextEpisodePosterButton: Boolean = false,
    val nextEpisodeThreshold: Double = 0.90,
    val vlcHeaderProxyEnabled: Boolean = true,
    val vlcBrightnessGestureEnabled: Boolean = false,
    val vlcVolumeGestureEnabled: Boolean = false,
    val playerTwoFingerTapPlayPauseEnabled: Boolean = true,
    val vlcDoubleTapSeekEnabled: Boolean = true,
    val vlcDoubleTapSeekSeconds: Double = 10.0,
    val vlcPiPEnabled: Boolean = false,
    val vlcOpenSubtitlesEnabled: Boolean = false,
    val vlcOpenSubtitlesAutoFallbackEnabled: Boolean = true,
    @Serializable(with = BackupColorStringSerializer::class)
    val subtitleForegroundColor: String? = null,
    @Serializable(with = BackupColorStringSerializer::class)
    val subtitleStrokeColor: String? = null,
    val subtitleStrokeWidth: Double = 1.0,
    val subtitleFontSize: Double = 30.0,
    val subtitleVerticalOffset: Double = -6.0,
    val showKanzen: Boolean = false,
    val kanzenAutoMode: Boolean = false,
    val kanzenAutoUpdateModules: Boolean = true,
    val autoUpdateServicesEnabled: Boolean = true,
    @SerialName("servicesAutoModeEnabled") val autoModeEnabled: Boolean = true,
    @SerialName("servicesAutoSelectEpisodesEnabled") val servicesAutoSelectEpisodesEnabled: Boolean = false,
    @SerialName("servicesAutoModeSourceIds") val autoModeSourceIds: List<String> = emptyList(),
    @SerialName("servicesAutoModeSourceOrderIds") val autoModeSourceOrderIds: List<String> = emptyList(),
    val servicesAutoModeQualityPreference: String = ServicesAutoModeQualityPreference.Default.rawValue,
    val githubReleaseAutoCheckEnabled: Boolean = true,
    val githubReleaseUpdateAvailable: Boolean = false,
    val githubReleaseLatestVersion: String = "",
    val githubReleaseURL: String = "",
    val seasonMenu: Boolean = false,
    val horizontalEpisodeList: Boolean = false,
    val mediaDetailElementOrder: String = MediaDetailElement.DefaultOrderRawValue,
    val mediaDetailHiddenElements: String = "",
    val mediaColumnsPortrait: Int = 3,
    val mediaColumnsLandscape: Int = 5,
    val readingMode: Int = 2,
    val readerFontSize: Double = 16.0,
    val readerFontFamily: String = "-apple-system",
    val readerFontWeight: String = "normal",
    val readerColorPreset: Int = 0,
    val readerTextAlignment: String = "left",
    val readerLineSpacing: Double = 1.6,
    val readerMargin: Double = 4.0,
    val autoClearCacheEnabled: Boolean = false,
    val autoClearCacheThresholdMB: Double = 500.0,
    val highQualityThreshold: Double = 0.9,
    @SerialName("filterHorror") val filterHorrorContent: Boolean = false,
    val selectedSimilarityAlgorithm: String = SimilarityAlgorithm.HYBRID.id,
    val collections: List<BackupCollection> = emptyList(),
    val progressData: JsonElement = JsonObject(emptyMap()),
    val trackerState: TrackerStateSnapshot = TrackerStateSnapshot(),
    val catalogs: List<BackupCatalog> = emptyList(),
    val services: List<ServiceBackup> = emptyList(),
    val stremioAddons: List<StremioAddonBackup>? = null,
    val mangaCollections: List<BackupCollection> = emptyList(),
    val mangaReadingProgress: Map<String, MangaProgressBackup> = emptyMap(),
    val mangaProgressData: JsonElement = JsonArray(emptyList()),
    val mangaCatalogs: List<BackupCatalog> = emptyList(),
    val kanzenModules: List<ModuleBackup> = emptyList(),
    val recommendationCache: JsonElement = JsonArray(emptyList()),
    @SerialName("userRatings") val userRatings: Map<String, Double> = emptyMap(),
    val userRatingNotes: Map<String, String> = emptyMap(),
) {
    val resolvedInAppPlayer: InAppPlayer
        get() = (legacyPlayerChoice ?: inAppPlayer).let { player ->
            if (player == InAppPlayer.VLC) InAppPlayer.MPV else player
        }

    fun nextEpisodeThresholdPercent(): Int {
        val percent = if (nextEpisodeThreshold <= 1.0) {
            nextEpisodeThreshold * 100.0
        } else {
            nextEpisodeThreshold
        }
        return percent.roundToInt().coerceIn(50, 99)
    }
}

data class BackupDocument(
    val payload: BackupData,
    val unknownKeys: Map<String, JsonElement> = emptyMap(),
) {
    fun encode(json: Json): String = json.encodeToString(JsonObject.serializer(), toJsonObject(json))

    fun toJsonObject(json: Json): JsonObject {
        val known = json.encodeToJsonElement(payload).jsonObject
        return JsonObject(known + unknownKeys)
    }

    companion object {
        fun decode(json: Json, raw: String): BackupDocument {
            val root = try {
                json.parseToJsonElement(raw).jsonObject
            } catch (error: IllegalStateException) {
                throw SerializationException("Backup root is not a JSON object", error)
            }
            val payload = json.decodeFromJsonElement<BackupData>(root)
            val knownKeys = BackupData.serializer().descriptor.elementNames()
            val unknownKeys = root.filterKeys { it !in knownKeys }
            return BackupDocument(payload = payload, unknownKeys = unknownKeys)
        }
    }
}

fun JsonElement.hasBackupData(): Boolean = when (this) {
    is JsonArray -> isNotEmpty()
    is JsonObject -> isNotEmpty()
    JsonNull -> false
    else -> true
}

object StringOrNumberAsStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("StringOrNumberAsString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeString()
        return when (val element = jsonDecoder.decodeJsonElement()) {
            JsonNull -> ""
            is JsonPrimitive -> element.content
            else -> element.toString()
        }
    }

    override fun serialize(encoder: Encoder, value: String) {
        encoder.encodeString(value)
    }
}

object BackupColorStringSerializer : KSerializer<String> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("BackupColorString", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): String {
        val jsonDecoder = decoder as? JsonDecoder ?: return decoder.decodeString().decodedBackupColor()
        return when (val element = jsonDecoder.decodeJsonElement()) {
            JsonNull -> ""
            is JsonPrimitive -> element.contentOrNull.orEmpty().decodedBackupColor()
            else -> element.toString().decodedBackupColor()
        }
    }

    override fun serialize(encoder: Encoder, value: String) {
        encoder.encodeString(value.decodedBackupColor())
    }
}

private fun String.decodedBackupColor(): String {
    val raw = trim()
    if (raw.isBlank()) return raw
    normalizedHexColor(raw)?.let { return it }
    decodeBase64BackupColor(raw)?.let { return it }
    return raw
}

private fun normalizedHexColor(raw: String): String? {
    val value = raw
        .trim()
        .removePrefix("#")
        .removePrefix("0x")
        .removePrefix("0X")
    if ((value.length != 6 && value.length != 8) || !value.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
        return null
    }
    return "#${value.uppercase()}"
}

private fun decodeBase64BackupColor(raw: String): String? {
    val decoded = runCatching { Base64.getDecoder().decode(raw) }.getOrNull() ?: return null
    decoded.toString(Charsets.UTF_8).trim('\u0000', ' ', '\n', '\r', '\t').let { text ->
        normalizedHexColor(text)?.let { return it }
    }
    decoded.toString(Charsets.ISO_8859_1).let { text ->
        BackupColorRegex.find(text)?.value?.let { return normalizedHexColor(it) }
        decodeArchivedColorComponentText(text)?.let { return it }
    }
    return runCatching { BinaryPropertyListColorDecoder(decoded).decodeColor() }.getOrNull()
}

private fun decodeArchivedColorComponentText(text: String): String? {
    fun component(name: String): Double? {
        val pattern = Regex("""$name[^0-9.-]*(0(?:\.\d+)?|1(?:\.0+)?|\.\d+)""", RegexOption.IGNORE_CASE)
        return pattern.find(text)?.groupValues?.getOrNull(1)?.toDoubleOrNull()
    }
    val red = component("UIRed") ?: component("red")
    val green = component("UIGreen") ?: component("green")
    val blue = component("UIBlue") ?: component("blue")
    val alpha = component("UIAlpha") ?: component("alpha") ?: 1.0
    return if (red != null && green != null && blue != null) {
        rgbaToHex(red, green, blue, alpha)
    } else {
        null
    }
}

private fun rgbaToHex(red: Double, green: Double, blue: Double, alpha: Double = 1.0): String {
    fun component(value: Double): Int =
        (value.coerceIn(0.0, 1.0) * 255.0).roundToInt().coerceIn(0, 255)
    val a = component(alpha)
    val r = component(red)
    val g = component(green)
    val b = component(blue)
    return if (a < 255) {
        "#%02X%02X%02X%02X".format(a, r, g, b)
    } else {
        "#%02X%02X%02X".format(r, g, b)
    }
}

private val BackupColorRegex = Regex("""#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})""")

private data class BinaryPropertyListUid(val index: Int)

private class BinaryPropertyListColorDecoder(
    private val bytes: ByteArray,
) {
    private val parsedObjects = mutableMapOf<Int, Any?>()
    private val offsets: List<Int>
    private val objectRefSize: Int
    private val topObjectIndex: Int

    init {
        require(bytes.size >= 40 && bytes.copyOfRange(0, 8).toString(Charsets.US_ASCII) == "bplist00") {
            "Not a binary property list."
        }
        val trailerOffset = bytes.size - 32
        val offsetIntSize = bytes[trailerOffset + 6].toInt() and 0xff
        objectRefSize = bytes[trailerOffset + 7].toInt() and 0xff
        val objectCount = readUnsigned(trailerOffset + 8, 8).toInt()
        topObjectIndex = readUnsigned(trailerOffset + 16, 8).toInt()
        val offsetTableOffset = readUnsigned(trailerOffset + 24, 8).toInt()
        offsets = List(objectCount) { index ->
            readUnsigned(offsetTableOffset + index * offsetIntSize, offsetIntSize).toInt()
        }
    }

    fun decodeColor(): String? {
        val root = parseObject(topObjectIndex)
        val objects = (root as? Map<*, *>)?.get("\$objects") as? List<*>
        val nodes = mutableListOf<Any?>()
        collectNodes(root, nodes, objects)
        return nodes
            .asSequence()
            .mapNotNull { it as? Map<*, *> }
            .mapNotNull { map -> decodeColorMap(map, objects) }
            .firstOrNull()
    }

    private fun collectNodes(value: Any?, nodes: MutableList<Any?>, objects: List<*>?) {
        val resolved = resolve(value, objects)
        nodes += resolved
        when (resolved) {
            is Map<*, *> -> resolved.values.forEach { collectNodes(it, nodes, objects) }
            is List<*> -> resolved.forEach { collectNodes(it, nodes, objects) }
        }
    }

    private fun decodeColorMap(map: Map<*, *>, objects: List<*>?): String? {
        val red = number(map["UIRed"], objects) ?: number(map["red"], objects)
        val green = number(map["UIGreen"], objects) ?: number(map["green"], objects)
        val blue = number(map["UIBlue"], objects) ?: number(map["blue"], objects)
        val alpha = number(map["UIAlpha"], objects) ?: number(map["alpha"], objects) ?: 1.0
        if (red != null && green != null && blue != null) {
            return rgbaToHex(red, green, blue, alpha)
        }

        val white = number(map["UIWhite"], objects) ?: number(map["white"], objects)
        if (white != null) {
            return rgbaToHex(white, white, white, alpha)
        }

        val components = list(map["NSComponents"], objects)
            ?: list(map["UIComponents"], objects)
            ?: list(map["components"], objects)
        val componentValues = components?.mapNotNull { number(it, objects) }.orEmpty()
        if (componentValues.size >= 3) {
            return rgbaToHex(
                red = componentValues[0],
                green = componentValues[1],
                blue = componentValues[2],
                alpha = componentValues.getOrNull(3) ?: alpha,
            )
        }

        map.values
            .mapNotNull { resolve(it, objects) as? String }
            .forEach { string ->
                normalizedHexColor(string)?.let { return it }
                decodeArchivedColorComponentText(string)?.let { return it }
            }
        return null
    }

    private fun parseObject(index: Int): Any? {
        parsedObjects[index]?.let { return it }
        val offset = offsets.getOrNull(index) ?: error("Invalid property-list object index.")
        val marker = bytes[offset].toInt() and 0xff
        val type = marker ushr 4
        val info = marker and 0x0f
        val parsed = when (type) {
            0x0 -> when (info) {
                0x0 -> null
                0x8 -> false
                0x9 -> true
                else -> null
            }
            0x1 -> readSignedInteger(offset + 1, 1 shl info)
            0x2 -> readReal(offset + 1, 1 shl info)
            0x5 -> {
                val (length, contentOffset) = readLength(info, offset + 1)
                String(bytes, contentOffset, length, Charsets.US_ASCII)
            }
            0x6 -> {
                val (length, contentOffset) = readLength(info, offset + 1)
                String(bytes, contentOffset, length * 2, Charsets.UTF_16BE)
            }
            0x8 -> BinaryPropertyListUid(readUnsigned(offset + 1, info + 1).toInt())
            0xA -> {
                val (length, contentOffset) = readLength(info, offset + 1)
                List(length) { position ->
                    parseObject(readObjectReference(contentOffset + position * objectRefSize))
                }
            }
            0xD -> {
                val (length, contentOffset) = readLength(info, offset + 1)
                val valueRefsOffset = contentOffset + length * objectRefSize
                buildMap<String, Any?> {
                    repeat(length) { position ->
                        val key = parseObject(readObjectReference(contentOffset + position * objectRefSize))
                        val value = parseObject(readObjectReference(valueRefsOffset + position * objectRefSize))
                        put(key?.toString().orEmpty(), value)
                    }
                }
            }
            else -> null
        }
        parsedObjects[index] = parsed
        return parsed
    }

    private fun readLength(info: Int, offset: Int): Pair<Int, Int> {
        if (info < 0x0F) return info to offset
        val marker = bytes[offset].toInt() and 0xff
        require(marker ushr 4 == 0x1) { "Property-list length marker is not an integer." }
        val byteCount = 1 shl (marker and 0x0f)
        return readUnsigned(offset + 1, byteCount).toInt() to offset + 1 + byteCount
    }

    private fun readObjectReference(offset: Int): Int =
        readUnsigned(offset, objectRefSize).toInt()

    private fun readSignedInteger(offset: Int, size: Int): Long {
        val unsigned = readUnsigned(offset, size)
        val signBit = 1L shl (size * 8 - 1)
        return if (unsigned and signBit != 0L) unsigned - (1L shl (size * 8)) else unsigned
    }

    private fun readReal(offset: Int, size: Int): Double = when (size) {
        4 -> ByteBuffer.wrap(bytes, offset, size).order(ByteOrder.BIG_ENDIAN).float.toDouble()
        8 -> ByteBuffer.wrap(bytes, offset, size).order(ByteOrder.BIG_ENDIAN).double
        else -> 0.0
    }

    private fun readUnsigned(offset: Int, size: Int): Long {
        var value = 0L
        repeat(size) { index ->
            value = (value shl 8) or (bytes[offset + index].toLong() and 0xff)
        }
        return value
    }

    private fun resolve(value: Any?, objects: List<*>?): Any? =
        if (value is BinaryPropertyListUid) objects?.getOrNull(value.index) else value

    private fun number(value: Any?, objects: List<*>?): Double? = when (val resolved = resolve(value, objects)) {
        is Number -> resolved.toDouble()
        is String -> resolved.toDoubleOrNull()
        else -> null
    }

    private fun list(value: Any?, objects: List<*>?): List<*>? =
        resolve(value, objects) as? List<*>
}

object InAppPlayerBackupSerializer : KSerializer<InAppPlayer> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("InAppPlayerBackup", PrimitiveKind.STRING)

    override fun deserialize(decoder: Decoder): InAppPlayer {
        val raw = (decoder as? JsonDecoder)
            ?.decodeJsonElement()
            ?.let { element ->
                when (element) {
                    JsonNull -> ""
                    is JsonPrimitive -> element.content
                    else -> element.toString()
                }
            }
            ?: decoder.decodeString()

        return when (raw.trim().lowercase()) {
            "vlc", "mpv" -> InAppPlayer.MPV
            "external", "outplayer", "outside" -> InAppPlayer.EXTERNAL
            "normal", "default", "media3", "exoplayer" -> InAppPlayer.NORMAL
            else -> InAppPlayer.MPV
        }
    }

    override fun serialize(encoder: Encoder, value: InAppPlayer) {
        val jsonEncoder = encoder as? JsonEncoder
        val encoded = when (value) {
            InAppPlayer.NORMAL -> "Normal"
            InAppPlayer.VLC,
            InAppPlayer.MPV -> "MPV"
            InAppPlayer.EXTERNAL -> "External"
        }
        if (jsonEncoder != null) {
            jsonEncoder.encodeJsonElement(JsonPrimitive(encoded))
        } else {
            encoder.encodeString(encoded)
        }
    }
}

private fun SerialDescriptor.elementNames(): Set<String> =
    (0 until elementsCount).map(::getElementName).toSet()
