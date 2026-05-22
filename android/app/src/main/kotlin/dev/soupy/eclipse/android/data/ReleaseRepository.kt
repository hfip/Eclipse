package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.network.EclipseJson
import dev.soupy.eclipse.android.core.storage.AppSettings
import dev.soupy.eclipse.android.core.storage.SettingsStore
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

data class ReleaseCheckSummary(
    val latestVersion: String,
    val releaseUrl: String,
    val updateAvailable: Boolean,
    val checked: Boolean,
)

data class GitHubReleaseCachedState(
    val updateAvailable: Boolean,
    val showAlertPending: Boolean,
)

class ReleaseRepository(
    private val settingsStore: SettingsStore,
    private val currentVersion: String,
) {
    suspend fun checkForUpdatesIfNeeded(): Result<ReleaseCheckSummary?> = runCatching {
        val settings = settingsStore.settings.first()
        refreshCachedUpdateStateForCurrentVersion(settings)
        if (!settings.githubReleaseAutoCheckEnabled) return@runCatching null
        val now = System.currentTimeMillis()
        val elapsed = now - settings.githubReleaseLastCheckTimestamp
        if (elapsed in 0 until AutoCheckIntervalMillis) return@runCatching null
        checkForUpdates(settings = settings)
    }

    suspend fun checkForUpdates(): Result<ReleaseCheckSummary> = runCatching {
        val settings = settingsStore.settings.first()
        refreshCachedUpdateStateForCurrentVersion(settings)
        checkForUpdates(settings = settings)
    }

    suspend fun consumePendingPrompt() {
        settingsStore.consumeGitHubReleasePrompt()
    }

    fun cachedStateForDisplay(settings: AppSettings): GitHubReleaseCachedState =
        effectiveGitHubReleaseCachedState(settings, currentVersion)

    private suspend fun refreshCachedUpdateStateForCurrentVersion(settings: AppSettings) {
        if (refreshedGitHubReleaseCachedState(settings, currentVersion) != null) {
            settingsStore.clearGitHubReleaseCachedUpdateState()
        }
    }

    private suspend fun checkForUpdates(
        settings: AppSettings,
    ): ReleaseCheckSummary {
        val release = fetchLatestRelease()
        val latestVersion = release.tagName
        val updateAvailable = normalizedVersion(latestVersion).isNewerThan(normalizedVersion(currentVersion))
        val shouldPrompt = shouldPromptForGitHubRelease(
            updateAvailable = updateAvailable,
            latestVersion = latestVersion,
            lastPromptedVersion = settings.githubReleaseLastPromptedVersion,
        )

        settingsStore.saveGitHubReleaseCheck(
            latestVersion = latestVersion,
            releaseUrl = release.htmlUrl,
            updateAvailable = updateAvailable,
            prompt = shouldPrompt,
        )

        return ReleaseCheckSummary(
            latestVersion = latestVersion,
            releaseUrl = release.htmlUrl,
            updateAvailable = updateAvailable,
            checked = true,
        )
    }

    private suspend fun fetchLatestRelease(): GitHubRelease = withContext(Dispatchers.IO) {
        val connection = (URL(GitHubLatestReleaseUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 15_000
            requestMethod = "GET"
            setRequestProperty("Accept", "application/vnd.github+json")
            setRequestProperty("User-Agent", "Eclipse-Android")
        }
        try {
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                error("GitHub release check failed with HTTP $status.")
            }
            EclipseJson.decodeFromString(GitHubRelease.serializer(), body)
        } finally {
            connection.disconnect()
        }
    }
}

@Serializable
private data class GitHubRelease(
    @SerialName("tag_name") val tagName: String,
    @SerialName("html_url") val htmlUrl: String,
)

private const val GitHubLatestReleaseUrl = "https://api.github.com/repos/Soupy-dev/Eclipse/releases/latest"
private const val AutoCheckIntervalMillis = 6L * 60L * 60L * 1_000L

internal fun shouldPromptForGitHubRelease(
    updateAvailable: Boolean,
    latestVersion: String,
    lastPromptedVersion: String,
): Boolean =
    updateAvailable && latestVersion.isNotBlank() && lastPromptedVersion != latestVersion

internal fun effectiveGitHubReleaseCachedState(
    settings: AppSettings,
    currentVersion: String,
): GitHubReleaseCachedState {
    val latestVersion = normalizedVersion(settings.githubReleaseLatestVersion)
    val updateAvailable = latestVersion.isNotBlank() &&
        settings.githubReleaseUpdateAvailable &&
        latestVersion.isNewerThan(normalizedVersion(currentVersion))
    return GitHubReleaseCachedState(
        updateAvailable = updateAvailable,
        showAlertPending = settings.githubReleaseShowAlertPending && updateAvailable,
    )
}

internal fun refreshedGitHubReleaseCachedState(
    settings: AppSettings,
    currentVersion: String,
): GitHubReleaseCachedState? {
    if (!settings.githubReleaseUpdateAvailable && !settings.githubReleaseShowAlertPending) {
        return null
    }
    val latestVersion = normalizedVersion(settings.githubReleaseLatestVersion)
    val shouldClear = latestVersion.isBlank() ||
        !latestVersion.isNewerThan(normalizedVersion(currentVersion))
    return if (shouldClear) {
        GitHubReleaseCachedState(updateAvailable = false, showAlertPending = false)
    } else {
        null
    }
}

private fun normalizedVersion(raw: String): String =
    raw.trim().removePrefix("v").removePrefix("V")

private fun String.isNewerThan(other: String): Boolean {
    val left = versionComponents()
    val right = other.versionComponents()
    if (left.isEmpty()) return false
    val maxCount = maxOf(left.size, right.size)
    repeat(maxCount) { index ->
        val l = left.getOrElse(index) { 0 }
        val r = right.getOrElse(index) { 0 }
        if (l > r) return true
        if (l < r) return false
    }
    return false
}

private fun String.versionComponents(): List<Int> {
    val components = mutableListOf<Int>()
    val current = StringBuilder()
    forEach { char ->
        if (char.isDigit()) {
            current.append(char)
        } else if (current.isNotEmpty()) {
            components += current.toString().toIntOrNull() ?: 0
            current.clear()
        }
    }
    if (current.isNotEmpty()) {
        components += current.toString().toIntOrNull() ?: 0
    }
    return components
}
