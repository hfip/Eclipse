package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.BackupAidokuInstalledSource
import dev.soupy.eclipse.android.core.model.BackupAidokuSourceListRecord
import dev.soupy.eclipse.android.core.model.BackupAidokuState
import dev.soupy.eclipse.android.core.model.BackupData
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class MangaBackupMappingsTest {
    @Test
    fun backupAidokuStateRestoresAsUnavailableAndroidReaderSources() {
        val backup = BackupData(
            aidokuState = BackupAidokuState(
                sourceLists = listOf(
                    BackupAidokuSourceListRecord(
                        url = "https://aidoku.example/sources.json",
                        name = "Sources",
                        sourceCount = 1,
                    ),
                ),
                installedSources = listOf(
                    BackupAidokuInstalledSource(
                        id = "example.en",
                        name = "Example Aidoku",
                        version = 4,
                        languages = listOf("en"),
                        packageURL = "https://aidoku.example/example.aix",
                        isEnabled = true,
                        order = 7,
                    ),
                ),
                showMatureSources = true,
            ),
        )

        val snapshot = backup.toMangaLibrarySnapshot()

        assertEquals("Sources", snapshot.aidokuState?.sourceLists?.single()?.name)
        val restored = snapshot.restoredAidokuSources.single()
        assertEquals("example.en", restored.id)
        assertEquals("Example Aidoku", restored.displayName)
        assertEquals(7, restored.order)
        assertFalse(restored.subtitle.isBlank())
    }
}
