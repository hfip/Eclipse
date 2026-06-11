package dev.soupy.eclipse.android.data

import android.content.Context
import dev.soupy.eclipse.android.core.model.BackupReaderDownloadItem
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

class ReaderCacheRepository internal constructor(
    private val root: File,
) {
    constructor(context: Context) : this(File(context.cacheDir, "reader-cache"))

    private val manifestFile = File(root, ".reader_downloads.json")

    suspend fun stats(): Result<ReaderCacheStats> = runCatching {
        withContext(Dispatchers.IO) {
            statsSnapshot()
        }
    }

    suspend fun clear(): Result<ReaderCacheStats> = runCatching {
        withContext(Dispatchers.IO) {
            val current = statsSnapshot()
            if (root.exists()) {
                root.deleteRecursively()
            }
            current
        }
    }

    suspend fun exportDownloads(): Result<List<BackupReaderDownloadItem>> = runCatching {
        withContext(Dispatchers.IO) {
            readManifest()
        }
    }

    suspend fun restoreDownloads(items: List<BackupReaderDownloadItem>): Result<Unit> = runCatching {
        withContext(Dispatchers.IO) {
            if (items.isEmpty()) return@withContext
            writeManifest(
                items.map { item ->
                    item.copy(
                        status = if (item.status.equals("completed", ignoreCase = true)) {
                            "metadata-only"
                        } else {
                            item.status.ifBlank { "metadata-only" }
                        },
                        progress = item.progress.coerceIn(0.0, 1.0),
                        error = item.error ?: "Files are not embedded in Eclipse backups; reopen the chapter to rebuild Android's app-scoped reader cache.",
                    )
                },
            )
        }
    }

    suspend fun load(
        moduleId: String?,
        chapterParams: String?,
        isNovel: Boolean,
    ): Result<KanzenReaderContentSnapshot?> = runCatching {
        withContext(Dispatchers.IO) {
            val directory = cacheDirectory(moduleId, chapterParams, isNovel) ?: return@withContext null
            if (!directory.isDirectory) return@withContext null
            val textFile = File(directory, "chapter.txt")
            if (isNovel && textFile.isFile) {
                return@withContext KanzenReaderContentSnapshot(
                    chapterParams = chapterParams.orEmpty(),
                    text = textFile.readText(),
                    isCached = true,
                    cacheMessage = "Loaded chapter text from reader cache.",
                )
            }
            val pages = directory.listFiles()
                .orEmpty()
                .filter { file -> file.isFile && file.name.startsWith("page-") }
                .sortedBy(File::getName)
                .map { file -> file.toURI().toString() }
            pages.takeIf(List<String>::isNotEmpty)?.let { imageUris ->
                KanzenReaderContentSnapshot(
                    chapterParams = chapterParams.orEmpty(),
                    imageUrls = imageUris,
                    isCached = true,
                    cacheMessage = "Loaded ${imageUris.size} cached page${if (imageUris.size == 1) "" else "s"}.",
                )
            }
        }
    }

    suspend fun save(
        moduleId: String?,
        chapterParams: String?,
        isNovel: Boolean,
        content: KanzenReaderContentSnapshot,
        title: String = "",
        chapterNumber: String = "",
    ): Result<KanzenReaderContentSnapshot> = runCatching {
        withContext(Dispatchers.IO) {
            val directory = cacheDirectory(moduleId, chapterParams, isNovel)
                ?: return@withContext content
            directory.mkdirs()
            if (isNovel) {
                content.text?.takeIf(String::isNotBlank)?.let { text ->
                    File(directory, "chapter.txt").writeText(text)
                    rememberDownload(
                        moduleId = moduleId,
                        chapterParams = chapterParams,
                        isNovel = isNovel,
                        title = title,
                        chapterNumber = chapterNumber,
                        directory = directory,
                    )
                    return@withContext content.copy(
                        isCached = true,
                        cacheMessage = "Cached chapter text for offline reading.",
                    )
                }
                return@withContext content
            }

            val cachedPages = content.imageUrls.mapIndexedNotNull { index, imageUrl ->
                cacheImage(
                    imageUrl = imageUrl,
                    target = File(directory, "page-${index.toString().padStart(4, '0')}${imageUrl.extensionOrDefault()}"),
                )
            }
            if (cachedPages.isEmpty()) {
                content
            } else {
                val cachedNames = cachedPages.map(File::getName).toSet()
                directory.listFiles()
                    .orEmpty()
                    .filter { file -> file.isFile && file.name.startsWith("page-") && file.name !in cachedNames }
                    .forEach(File::delete)
                content.copy(
                    imageUrls = cachedPages.map { file -> file.toURI().toString() },
                    isCached = true,
                    cacheMessage = "Cached ${cachedPages.size} page${if (cachedPages.size == 1) "" else "s"} for offline reading.",
                ).also {
                    rememberDownload(
                        moduleId = moduleId,
                        chapterParams = chapterParams,
                        isNovel = isNovel,
                        title = title,
                        chapterNumber = chapterNumber,
                        directory = directory,
                    )
                }
            }
        }
    }

    private fun cacheDirectory(
        moduleId: String?,
        chapterParams: String?,
        isNovel: Boolean,
    ): File? {
        val key = cacheKey(moduleId, chapterParams, isNovel) ?: return null
        return File(root, key.directoryName)
    }

    private fun statsSnapshot(): ReaderCacheStats {
        if (!root.isDirectory) return ReaderCacheStats()
        val entries = root.listFiles()
            .orEmpty()
            .filter { file -> file.isDirectory }
            .count()
        val files = root.walkTopDown()
            .filter { file -> file.isFile && file != manifestFile }
            .toList()
        val downloads = readManifest()
        return ReaderCacheStats(
            entryCount = entries,
            fileCount = files.size,
            byteCount = files.sumOf(File::length),
            downloadCount = downloads.count { item -> item.status.equals("completed", ignoreCase = true) },
            restoredMetadataCount = downloads.count { item -> item.status.equals("metadata-only", ignoreCase = true) },
        )
    }

    private fun rememberDownload(
        moduleId: String?,
        chapterParams: String?,
        isNovel: Boolean,
        title: String,
        chapterNumber: String,
        directory: File,
    ) {
        val key = cacheKey(moduleId, chapterParams, isNovel) ?: return
        val bytes = directory.walkTopDown()
            .filter(File::isFile)
            .filterNot { it == manifestFile }
            .sumOf(File::length)
        val item = BackupReaderDownloadItem(
            id = key.id,
            routeKey = key.routeKey,
            title = title.ifBlank { if (isNovel) "Novel chapter" else "Manga chapter" },
            chapterNumber = chapterNumber,
            status = "completed",
            progress = 1.0,
            downloadedBytes = bytes,
            error = null,
        )
        val updated = (readManifest().filterNot { existing -> existing.id == item.id } + item)
            .sortedWith(compareBy<BackupReaderDownloadItem> { it.title.lowercase() }.thenBy { it.chapterNumber })
        writeManifest(updated)
    }

    private fun readManifest(): List<BackupReaderDownloadItem> =
        runCatching {
            if (!manifestFile.isFile) return emptyList()
            ReaderCacheJson.decodeFromString(
                ListSerializer(BackupReaderDownloadItem.serializer()),
                manifestFile.readText(),
            )
        }.getOrDefault(emptyList())

    private fun writeManifest(items: List<BackupReaderDownloadItem>) {
        root.mkdirs()
        manifestFile.writeText(
            ReaderCacheJson.encodeToString(
                ListSerializer(BackupReaderDownloadItem.serializer()),
                items,
            ),
        )
    }

    private fun cacheImage(
        imageUrl: String,
        target: File,
    ): File? {
        val uri = runCatching { URI(imageUrl) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase()
        if (scheme == "file") return File(uri).takeIf(File::isFile)
        if (scheme != "http" && scheme != "https") return null
        if (target.isFile && target.length() > 0L) return target

        val temp = File(target.parentFile, "${target.name}.tmp")
        return runCatching {
            target.parentFile?.mkdirs()
            val connection = uri.toURL().openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.setRequestProperty("User-Agent", "Eclipse Android Reader Cache")
            connection.inputStream.use { input ->
                temp.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            if (temp.length() <= 0L) {
                temp.delete()
                return null
            }
            if (target.exists()) target.delete()
            temp.renameTo(target)
            target
        }.getOrElse {
            temp.delete()
            null
        }
    }
}

data class ReaderCacheStats(
    val entryCount: Int = 0,
    val fileCount: Int = 0,
    val byteCount: Long = 0L,
    val downloadCount: Int = 0,
    val restoredMetadataCount: Int = 0,
) {
    val displayText: String
        get() = if (fileCount == 0 && restoredMetadataCount == 0) {
            "Reader cache empty."
        } else {
            buildList {
                if (fileCount > 0) {
                    add(
                        "$entryCount cached ${if (entryCount == 1) "chapter" else "chapters"}, " +
                            "$fileCount ${if (fileCount == 1) "file" else "files"}, ${byteCount.toHumanSize()}",
                    )
                }
                if (downloadCount > 0) add("$downloadCount reader download${if (downloadCount == 1) "" else "s"}")
                if (restoredMetadataCount > 0) add("$restoredMetadataCount restored reader download marker${if (restoredMetadataCount == 1) "" else "s"}")
            }.joinToString("; ") + "."
        }
}

private data class ReaderCacheKey(
    val routeKey: String,
    val id: String,
    val directoryName: String,
)

private fun cacheKey(
    moduleId: String?,
    chapterParams: String?,
    isNovel: Boolean,
): ReaderCacheKey? {
    if (moduleId.isNullOrBlank() || moduleId == "anilist" || chapterParams.isNullOrBlank()) {
        return null
    }
    val type = if (isNovel) "novel" else "manga"
    val routeKey = "$type:$moduleId:$chapterParams"
    val id = routeKey.sha256()
    return ReaderCacheKey(
        routeKey = routeKey,
        id = id,
        directoryName = "$type-$id",
    )
}

private fun String.sha256(): String =
    MessageDigest.getInstance("SHA-256")
        .digest(toByteArray())
        .joinToString("") { byte -> "%02x".format(byte) }

private fun String.extensionOrDefault(): String {
    val path = runCatching { URI(this).path.orEmpty() }.getOrDefault("")
    val extension = path.substringAfterLast('.', missingDelimiterValue = "")
        .lowercase()
        .takeIf { value -> value.length in 2..5 && value.all { it.isLetterOrDigit() } }
        ?: "img"
    return ".$extension"
}

private fun Long.toHumanSize(): String =
    when {
        this >= 1024L * 1024L -> "${this / (1024L * 1024L)} MB"
        this >= 1024L -> "${this / 1024L} KB"
        else -> "$this B"
    }

private val ReaderCacheJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
}
