package dev.soupy.eclipse.android.core.mpv

import android.content.Context
import android.os.Build
import android.util.AttributeSet
import androidx.core.content.ContextCompat
import `is`.xyz.mpv.BaseMPVView
import `is`.xyz.mpv.MPVLib
import `is`.xyz.mpv.MPVLib.MpvFormat.MPV_FORMAT_DOUBLE
import `is`.xyz.mpv.MPVLib.MpvFormat.MPV_FORMAT_FLAG
import `is`.xyz.mpv.MPVLib.MpvFormat.MPV_FORMAT_INT64
import `is`.xyz.mpv.MPVLib.MpvFormat.MPV_FORMAT_NONE
import `is`.xyz.mpv.MPVLib.MpvFormat.MPV_FORMAT_STRING

internal class EclipseMpvView(
    context: Context,
    attrs: AttributeSet? = null,
) : BaseMPVView(context, attrs) {
    override fun initOptions() {
        MPVLib.setOptionString("profile", "fast")
        setVo("gpu")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = ContextCompat.getDisplayOrDefault(context)
            MPVLib.setOptionString("display-fps-override", display.mode.refreshRate.toString())
        }
        MPVLib.setOptionString("gpu-context", "android")
        MPVLib.setOptionString("opengl-es", "yes")
        MPVLib.setOptionString("hwdec", "mediacodec,mediacodec-copy")
        MPVLib.setOptionString("hwdec-codecs", "h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1")
        MPVLib.setOptionString("ao", "audiotrack,opensles")
        MPVLib.setOptionString("audio-set-media-role", "yes")
        MPVLib.setOptionString("tls-verify", "yes")
        MPVLib.setOptionString("input-default-bindings", "yes")
        MPVLib.setOptionString("sub-auto", "all")
        val cacheMegs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) 64 else 32
        MPVLib.setOptionString("demuxer-max-bytes", "${cacheMegs * 1024 * 1024}")
        MPVLib.setOptionString("demuxer-max-back-bytes", "${cacheMegs * 1024 * 1024}")
    }

    override fun postInitOptions() {
        MPVLib.setOptionString("save-position-on-quit", "no")
    }

    override fun observeProperties() {
        arrayOf(
            "time-pos/full" to MPV_FORMAT_DOUBLE,
            "duration/full" to MPV_FORMAT_DOUBLE,
            "pause" to MPV_FORMAT_FLAG,
            "eof-reached" to MPV_FORMAT_FLAG,
            "idle-active" to MPV_FORMAT_FLAG,
            "speed" to MPV_FORMAT_DOUBLE,
            "track-list" to MPV_FORMAT_NONE,
            "aid" to MPV_FORMAT_STRING,
            "sid" to MPV_FORMAT_STRING,
            "media-title" to MPV_FORMAT_STRING,
            "playlist-pos" to MPV_FORMAT_INT64,
        ).forEach { (name, format) -> MPVLib.observeProperty(name, format) }
    }
}
