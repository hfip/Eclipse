package `is`.xyz.mpv

import android.content.Context
import android.graphics.Bitmap
import android.view.Surface

@Suppress("unused")
object MPVLib {
    private val loadResult: Result<Unit> = runCatching {
        arrayOf("mpv", "player").forEach(System::loadLibrary)
    }

    val loadError: Throwable?
        get() = loadResult.exceptionOrNull()

    val isAvailable: Boolean
        get() = loadResult.isSuccess

    fun requireAvailable() {
        loadResult.getOrThrow()
    }

    external fun create(appctx: Context)
    external fun init()
    external fun destroy()
    external fun attachSurface(surface: Surface)
    external fun detachSurface()

    external fun command(cmd: Array<out String>)

    external fun setOptionString(name: String, value: String): Int

    external fun grabThumbnail(dimension: Int): Bitmap?

    external fun getPropertyInt(property: String): Int?
    external fun setPropertyInt(property: String, value: Int)
    external fun getPropertyDouble(property: String): Double?
    external fun setPropertyDouble(property: String, value: Double)
    external fun getPropertyBoolean(property: String): Boolean?
    external fun setPropertyBoolean(property: String, value: Boolean)
    external fun getPropertyString(property: String): String?
    external fun setPropertyString(property: String, value: String)

    external fun observeProperty(property: String, format: Int)

    private val observers = mutableListOf<EventObserver>()

    @JvmStatic
    fun addObserver(observer: EventObserver) {
        synchronized(observers) {
            observers.add(observer)
        }
    }

    @JvmStatic
    fun removeObserver(observer: EventObserver) {
        synchronized(observers) {
            observers.remove(observer)
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Long) {
        synchronized(observers) {
            observers.forEach { it.eventProperty(property, value) }
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Boolean) {
        synchronized(observers) {
            observers.forEach { it.eventProperty(property, value) }
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: Double) {
        synchronized(observers) {
            observers.forEach { it.eventProperty(property, value) }
        }
    }

    @JvmStatic
    fun eventProperty(property: String, value: String) {
        synchronized(observers) {
            observers.forEach { it.eventProperty(property, value) }
        }
    }

    @JvmStatic
    fun eventProperty(property: String) {
        synchronized(observers) {
            observers.forEach { it.eventProperty(property) }
        }
    }

    @JvmStatic
    fun event(eventId: Int) {
        synchronized(observers) {
            observers.forEach { it.event(eventId) }
        }
    }

    private val logObservers = mutableListOf<LogObserver>()

    @JvmStatic
    fun addLogObserver(observer: LogObserver) {
        synchronized(logObservers) {
            logObservers.add(observer)
        }
    }

    @JvmStatic
    fun removeLogObserver(observer: LogObserver) {
        synchronized(logObservers) {
            logObservers.remove(observer)
        }
    }

    @JvmStatic
    fun logMessage(prefix: String, level: Int, text: String) {
        synchronized(logObservers) {
            logObservers.forEach { it.logMessage(prefix, level, text) }
        }
    }

    interface EventObserver {
        fun eventProperty(property: String)
        fun eventProperty(property: String, value: Long)
        fun eventProperty(property: String, value: Boolean)
        fun eventProperty(property: String, value: String)
        fun eventProperty(property: String, value: Double)
        fun event(eventId: Int)
    }

    interface LogObserver {
        fun logMessage(prefix: String, level: Int, text: String)
    }

    object MpvFormat {
        const val MPV_FORMAT_NONE: Int = 0
        const val MPV_FORMAT_STRING: Int = 1
        const val MPV_FORMAT_FLAG: Int = 3
        const val MPV_FORMAT_INT64: Int = 4
        const val MPV_FORMAT_DOUBLE: Int = 5
    }

    object MpvEvent {
        const val MPV_EVENT_START_FILE: Int = 6
        const val MPV_EVENT_END_FILE: Int = 7
        const val MPV_EVENT_FILE_LOADED: Int = 8
        const val MPV_EVENT_PROPERTY_CHANGE: Int = 22
    }
}
