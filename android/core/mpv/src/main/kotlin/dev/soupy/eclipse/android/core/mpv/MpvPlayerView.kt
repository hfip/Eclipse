package dev.soupy.eclipse.android.core.mpv

import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import dev.soupy.eclipse.android.core.model.PlaybackSettingsSnapshot
import dev.soupy.eclipse.android.core.model.PlayerSource
import `is`.xyz.mpv.MPVLib
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

@Composable
fun MpvPlayerView(
    source: PlayerSource,
    settings: PlaybackSettingsSnapshot,
    modifier: Modifier = Modifier,
    resolveProxiedUrl: (String, Map<String, String>) -> String?,
    onControllerReady: (MpvPlayerController?) -> Unit = {},
    configureView: (View, MpvPlayerController) -> Unit = { _, _ -> },
    onEvent: (MpvPlayerEvent) -> Unit = {},
) {
    val context = LocalContext.current
    val currentSettings by rememberUpdatedState(settings)
    val currentOnEvent by rememberUpdatedState(onEvent)
    val currentOnControllerReady by rememberUpdatedState(onControllerReady)
    val currentConfigureView by rememberUpdatedState(configureView)
    var controller by remember(source.uri) { mutableStateOf<MpvPlayerController?>(null) }
    var reportedReady by remember(source.uri) { mutableStateOf(false) }
    var lastTracks by remember(source.uri) { mutableStateOf<MpvTrackSnapshot?>(null) }
    var lastFinished by remember(source.uri) { mutableStateOf(false) }

    AndroidView(
        modifier = modifier,
        factory = { factoryContext ->
            EclipseMpvView(factoryContext).also { view ->
                runCatching {
                    if (!MPVLib.isAvailable) {
                        error(MPVLib.loadError?.message ?: "MPV native libraries are not available for this device ABI.")
                    }
                    view.initialize(
                        configDir = factoryContext.filesDir.resolve("mpv").also { it.mkdirs() }.absolutePath,
                        cacheDir = factoryContext.cacheDir.resolve("mpv").also { it.mkdirs() }.absolutePath,
                    )
                    MpvPlayerController(view).also { created ->
                        created.load(source, currentSettings, resolveProxiedUrl)
                        controller = created
                        currentConfigureView(view, created)
                        currentOnControllerReady(created)
                    }
                }.onFailure { error ->
                    currentOnEvent(MpvPlayerEvent.Error(error.message ?: "Embedded MPV playback failed."))
                    currentOnControllerReady(null)
                }
            }
        },
        update = {
            controller?.let { activeController ->
                activeController.applySettings(settings)
                currentConfigureView(it, activeController)
            }
        },
    )

    LaunchedEffect(controller, source.resumePositionMs) {
        val activeController = controller ?: return@LaunchedEffect
        repeat(80) {
            val snapshot = activeController.progressSnapshot()
            if (snapshot != null) {
                if (!reportedReady) {
                    reportedReady = true
                    currentOnEvent(MpvPlayerEvent.Ready)
                }
                val resumeMs = source.resumePositionMs.coerceAtLeast(0L)
                if (resumeMs > 0L) {
                    activeController.seekToMs(resumeMs)
                }
                return@LaunchedEffect
            }
            delay(250L)
        }
    }

    LaunchedEffect(controller) {
        val activeController = controller ?: return@LaunchedEffect
        while (isActive) {
            activeController.progressSnapshot()?.let { snapshot ->
                currentOnEvent(MpvPlayerEvent.Progress(snapshot))
                if (snapshot.isFinished && !lastFinished) {
                    lastFinished = true
                    currentOnEvent(MpvPlayerEvent.Ended)
                }
            }
            val tracks = runCatching { activeController.trackSnapshot() }.getOrNull()
            if (tracks != null && tracks != lastTracks) {
                lastTracks = tracks
                currentOnEvent(MpvPlayerEvent.TracksChanged(tracks))
            }
            delay(1_000L)
        }
    }

    DisposableEffect(controller) {
        onDispose {
            val activeController = controller
            controller = null
            currentOnControllerReady(null)
            runCatching { activeController?.destroy() }
        }
    }
}
