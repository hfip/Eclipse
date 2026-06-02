package dev.soupy.eclipse.android.data

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class ProgressRepositoryTest {
    @Test
    fun stableProgressTimesPreserveEarlierLongerDuration() {
        val times = stableProgressTimes(
            currentTimeSeconds = 30.0,
            totalDurationSeconds = 30.0,
            previousDurationSeconds = 1_800.0,
        )

        assertEquals(30.0, times.currentTimeSeconds)
        assertEquals(1_800.0, times.totalDurationSeconds)
    }

    @Test
    fun stableProgressTimesFinishAgainstPreservedDuration() {
        val times = stableProgressTimes(
            currentTimeSeconds = 30.0,
            totalDurationSeconds = 30.0,
            previousDurationSeconds = 1_800.0,
            isFinished = true,
        )

        assertEquals(1_800.0, times.currentTimeSeconds)
        assertEquals(1_800.0, times.totalDurationSeconds)
    }

    @Test
    fun stableProgressTimesRejectInvalidDurations() {
        assertFailsWith<IllegalArgumentException> {
            stableProgressTimes(
                currentTimeSeconds = 0.0,
                totalDurationSeconds = Double.NaN,
            )
        }
    }
}
