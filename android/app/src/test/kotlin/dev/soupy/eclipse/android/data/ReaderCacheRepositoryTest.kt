package dev.soupy.eclipse.android.data

import dev.soupy.eclipse.android.core.model.BackupReaderDownloadItem
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.runBlocking

class ReaderCacheRepositoryTest {
    @Test
    fun restoreDownloadsKeepsIosDownloadStateAsAndroidMetadataOnlyMarkers() = runBlocking {
        val repository = ReaderCacheRepository(tempReaderRoot())

        repository.restoreDownloads(
            listOf(
                BackupReaderDownloadItem(
                    id = "ios-download",
                    routeKey = "manga:aidoku.example:chapter=1",
                    title = "Restored Manga",
                    chapterNumber = "1",
                    status = "completed",
                    progress = 1.4,
                ),
            ),
        ).getOrThrow()

        val restored = repository.exportDownloads().getOrThrow().single()
        assertEquals("ios-download", restored.id)
        assertEquals("metadata-only", restored.status)
        assertEquals(1.0, restored.progress)
        assertNotNull(restored.error)

        val stats = repository.stats().getOrThrow()
        assertEquals(0, stats.downloadCount)
        assertEquals(1, stats.restoredMetadataCount)
        assertTrue(stats.displayText.contains("restored reader download marker"))
    }

    @Test
    fun savedNovelChapterExportsCompletedReaderDownloadState() = runBlocking {
        val repository = ReaderCacheRepository(tempReaderRoot())

        val cached = repository.save(
            moduleId = "portable-module",
            chapterParams = "chapter=7",
            isNovel = true,
            content = KanzenReaderContentSnapshot(
                chapterParams = "chapter=7",
                text = "Chapter text",
            ),
            title = "Portable Novel",
            chapterNumber = "7",
        ).getOrThrow()

        assertTrue(cached.isCached)
        val download = repository.exportDownloads().getOrThrow().single()
        assertEquals("Portable Novel", download.title)
        assertEquals("7", download.chapterNumber)
        assertEquals("completed", download.status)
        assertEquals(1.0, download.progress)
        assertTrue(download.downloadedBytes > 0L)
        assertEquals("novel:portable-module:chapter=7", download.routeKey)

        val stats = repository.stats().getOrThrow()
        assertEquals(1, stats.downloadCount)
        assertEquals(0, stats.restoredMetadataCount)
        assertTrue(stats.displayText.contains("reader download"))
    }

    private fun tempReaderRoot(): File =
        createTempDirectory(prefix = "reader-cache-test-").toFile().resolve("reader-cache")
}
