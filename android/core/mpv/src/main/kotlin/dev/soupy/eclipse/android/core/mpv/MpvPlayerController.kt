package dev.soupy.eclipse.android.core.mpv

import dev.soupy.eclipse.android.core.model.PlaybackSettingsSnapshot
import dev.soupy.eclipse.android.core.model.PlayerSource
import dev.soupy.eclipse.android.core.model.SubtitleTrack
import `is`.xyz.mpv.MPVLib
import kotlin.math.roundToLong

data class MpvProgressSnapshot(
    val positionMs: Long,
    val durationMs: Long,
    val isPlaying: Boolean,
    val isFinished: Boolean,
)

data class MpvTrackOption(
    val id: Int,
    val name: String,
)

data class MpvTrackSnapshot(
    val audioTracks: List<MpvTrackOption> = emptyList(),
    val subtitleTracks: List<MpvTrackOption> = emptyList(),
    val selectedAudioTrackId: Int = -1,
    val selectedSubtitleTrackId: Int = -1,
)

sealed interface MpvPlayerEvent {
    data object Ready : MpvPlayerEvent
    data class Progress(val snapshot: MpvProgressSnapshot) : MpvPlayerEvent
    data class TracksChanged(val snapshot: MpvTrackSnapshot) : MpvPlayerEvent
    data object Ended : MpvPlayerEvent
    data class Error(val message: String) : MpvPlayerEvent
}

class MpvPlayerController internal constructor(
    private val view: EclipseMpvView,
) {
    fun applySettings(settings: PlaybackSettingsSnapshot) {
        MPVLib.setPropertyDouble("speed", settings.defaultPlaybackSpeed)
        MPVLib.setOptionString("alang", settings.preferredAnimeAudioLanguage.normalizedLanguageCode())
        MPVLib.setOptionString("slang", settings.defaultSubtitleLanguage.normalizedLanguageCode())
        MPVLib.setOptionString("subs-with-matching-audio", "yes")
        MPVLib.setOptionString(
            "sub-scale",
            (settings.subtitleFontSize / 30.0).coerceIn(0.65, 1.55).toString(),
        )
        MPVLib.setOptionString("sub-border-size", settings.subtitleStrokeWidth.coerceIn(0.0, 2.0).toString())
        MPVLib.setOptionString("sub-pos", (100.0 - settings.subtitleVerticalOffset).coerceIn(0.0, 100.0).toString())
        settings.subtitleForegroundColor?.toMpvColor()?.let { MPVLib.setOptionString("sub-color", it) }
        settings.subtitleStrokeColor?.toMpvColor()?.let { MPVLib.setOptionString("sub-border-color", it) }
    }

    fun load(
        source: PlayerSource,
        settings: PlaybackSettingsSnapshot,
        resolveProxiedUrl: (String, Map<String, String>) -> String?,
    ) {
        applySettings(settings)
        val mediaUrl = source.proxiedOrOriginal(settings, resolveProxiedUrl, source.uri)
        if (!settings.playerHeaderProxyEnabled) {
            MPVLib.setOptionString("http-header-fields", source.headers.toMpvHeaderFields())
        }
        view.playFile(mediaUrl)
        source.subtitles.forEachIndexed { index, subtitle ->
            val subtitleUrl = subtitle.uri?.takeIf { it.isNotBlank() } ?: return@forEachIndexed
            val resolvedSubtitleUrl = source.proxiedOrOriginal(settings, resolveProxiedUrl, subtitleUrl)
            val mode = if (settings.enableSubtitlesByDefault && (subtitle.isDefault || index == 0)) "select" else "auto"
            MPVLib.command(arrayOf("sub-add", resolvedSubtitleUrl, mode, subtitle.label.ifBlank { subtitle.language ?: "Subtitle" }))
        }
    }

    fun play() {
        MPVLib.setPropertyBoolean("pause", false)
    }

    fun pause() {
        MPVLib.setPropertyBoolean("pause", true)
    }

    fun togglePause() {
        if (MPVLib.getPropertyBoolean("pause") == true) play() else pause()
    }

    fun seekByMs(deltaMs: Long) {
        seekToMs(currentPositionMs() + deltaMs)
    }

    fun seekToMs(positionMs: Long) {
        val duration = currentDurationMs().takeIf { it > 0L }
        val target = duration?.let { durationMs ->
            positionMs.coerceIn(0L, (durationMs - 1_000L).coerceAtLeast(0L))
        } ?: positionMs.coerceAtLeast(0L)
        MPVLib.setPropertyDouble("time-pos", target / 1_000.0)
    }

    fun setPlaybackSpeed(speed: Double) {
        MPVLib.setPropertyDouble("speed", speed.coerceIn(0.1, 3.0))
    }

    fun selectAudioTrack(trackId: Int) {
        if (trackId == DisabledTrackId) {
            MPVLib.setPropertyString("aid", "no")
        } else {
            MPVLib.setPropertyInt("aid", trackId)
        }
    }

    fun selectSubtitleTrack(trackId: Int) {
        if (trackId == DisabledTrackId) {
            MPVLib.setPropertyString("sid", "no")
        } else {
            MPVLib.setPropertyInt("sid", trackId)
        }
    }

    fun progressSnapshot(): MpvProgressSnapshot? {
        val durationMs = currentDurationMs()
        if (durationMs <= 0L) return null
        val positionMs = currentPositionMs().coerceIn(0L, durationMs)
        val isPaused = MPVLib.getPropertyBoolean("pause") ?: true
        val eof = MPVLib.getPropertyBoolean("eof-reached") ?: false
        return MpvProgressSnapshot(
            positionMs = positionMs,
            durationMs = durationMs,
            isPlaying = !isPaused && !eof,
            isFinished = eof || positionMs >= (durationMs - 1_500L).coerceAtLeast(0L),
        )
    }

    fun trackSnapshot(): MpvTrackSnapshot {
        val tracks = loadTracks()
        return MpvTrackSnapshot(
            audioTracks = tracks["audio"].orEmpty(),
            subtitleTracks = tracks["sub"].orEmpty(),
            selectedAudioTrackId = selectedTrackId("aid"),
            selectedSubtitleTrackId = selectedTrackId("sid"),
        )
    }

    fun destroy() {
        view.destroy()
    }

    private fun currentPositionMs(): Long =
        ((MPVLib.getPropertyDouble("time-pos/full") ?: MPVLib.getPropertyDouble("time-pos") ?: 0.0) * 1_000.0)
            .roundToLong()
            .coerceAtLeast(0L)

    private fun currentDurationMs(): Long =
        ((MPVLib.getPropertyDouble("duration/full") ?: MPVLib.getPropertyDouble("duration") ?: 0.0) * 1_000.0)
            .roundToLong()
            .coerceAtLeast(0L)

    private fun selectedTrackId(property: String): Int =
        MPVLib.getPropertyString(property)?.toIntOrNull()
            ?: MPVLib.getPropertyInt(property)
            ?: DisabledTrackId

    private fun loadTracks(): Map<String, List<MpvTrackOption>> {
        val count = MPVLib.getPropertyInt("track-list/count") ?: return emptyMap()
        val tracks = mutableMapOf<String, MutableList<MpvTrackOption>>()
        repeat(count) { index ->
            val type = MPVLib.getPropertyString("track-list/$index/type") ?: return@repeat
            val id = MPVLib.getPropertyInt("track-list/$index/id") ?: return@repeat
            val lang = MPVLib.getPropertyString("track-list/$index/lang")
            val title = MPVLib.getPropertyString("track-list/$index/title")
            val label = listOfNotNull(title?.takeIf(String::isNotBlank), lang?.takeIf(String::isNotBlank))
                .joinToString(" / ")
                .ifBlank { "${type.replaceFirstChar(Char::uppercaseChar)} $id" }
            tracks.getOrPut(type) { mutableListOf() } += MpvTrackOption(id, label)
        }
        return tracks
    }

    private fun PlayerSource.proxiedOrOriginal(
        settings: PlaybackSettingsSnapshot,
        resolveProxiedUrl: (String, Map<String, String>) -> String?,
        url: String,
    ): String =
        if (settings.playerHeaderProxyEnabled) {
            resolveProxiedUrl(url, headers) ?: url
        } else {
            url
        }

    private fun Map<String, String>.toMpvHeaderFields(): String =
        entries
            .filter { (name, value) -> name.isNotBlank() && value.isNotBlank() }
            .joinToString(",") { (name, value) -> "${name.trim()}: ${value.trim()}" }

    private fun String.toMpvColor(): String? {
        val value = trim().removePrefix("#")
        if ((value.length != 6 && value.length != 8) || !value.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
            return null
        }
        val rgba = if (value.length == 8) value.substring(2) + value.substring(0, 2) else "${value}FF"
        return "#${rgba.uppercase()}"
    }

    private fun String.normalizedLanguageCode(): String =
        trim().lowercase().replace('_', '-').ifBlank { "und" }

    companion object {
        const val DisabledTrackId = -1
    }
}
