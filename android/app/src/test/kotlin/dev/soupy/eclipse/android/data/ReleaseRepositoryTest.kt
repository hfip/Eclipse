package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.storage.AppSettings
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ReleaseRepositoryTest {
    @Test
    fun cachedReleaseStateClearsStalePromptWhenCurrentVersionCatchesUp() {
        val settings = AppSettings(
            githubReleaseUpdateAvailable = true,
            githubReleaseLatestVersion = "v1.0.4",
            githubReleaseShowAlertPending = true,
        )

        val refreshed = refreshedGitHubReleaseCachedState(
            settings = settings,
            currentVersion = "1.0.4",
        )
        val effective = effectiveGitHubReleaseCachedState(
            settings = settings,
            currentVersion = "1.0.4",
        )

        assertEquals(GitHubReleaseCachedState(updateAvailable = false, showAlertPending = false), refreshed)
        assertFalse(effective.updateAvailable)
        assertFalse(effective.showAlertPending)
    }

    @Test
    fun cachedReleaseStateKeepsFutureReleasePrompt() {
        val settings = AppSettings(
            githubReleaseUpdateAvailable = true,
            githubReleaseLatestVersion = "v1.0.5",
            githubReleaseShowAlertPending = true,
        )

        val refreshed = refreshedGitHubReleaseCachedState(
            settings = settings,
            currentVersion = "1.0.4",
        )
        val effective = effectiveGitHubReleaseCachedState(
            settings = settings,
            currentVersion = "1.0.4",
        )

        assertNull(refreshed)
        assertTrue(effective.updateAvailable)
        assertTrue(effective.showAlertPending)
    }

    @Test
    fun pendingPromptRequiresStoredUpdateFlagForDisplay() {
        val settings = AppSettings(
            githubReleaseUpdateAvailable = false,
            githubReleaseLatestVersion = "v1.0.5",
            githubReleaseShowAlertPending = true,
        )

        val effective = effectiveGitHubReleaseCachedState(
            settings = settings,
            currentVersion = "1.0.4",
        )

        assertFalse(effective.updateAvailable)
        assertFalse(effective.showAlertPending)
    }

    @Test
    fun dismissedReleaseDoesNotPromptAgain() {
        assertTrue(
            shouldPromptForGitHubRelease(
                updateAvailable = true,
                latestVersion = "v1.0.5",
                lastPromptedVersion = "v1.0.4",
            ),
        )
        assertFalse(
            shouldPromptForGitHubRelease(
                updateAvailable = true,
                latestVersion = "v1.0.5",
                lastPromptedVersion = "v1.0.5",
            ),
        )
    }
}
