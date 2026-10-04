package com.aereality

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.media.MediaScannerConnection
import android.provider.MediaStore
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aereality/media"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToMovies", "saveToDownloads" -> {   // "saveToDownloads" kept as an alias; both save to Movies/Shaderly
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "video/mp4"

                    if (sourcePath == null || fileName == null) {
                        result.error("INVALID_ARGS", "sourcePath or fileName is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val uri = saveFileToMoviesShaderly(sourcePath, fileName, mimeType)
                        if (uri != null) {
                            result.success(uri.toString())
                        } else {
                            result.error("SAVE_FAILED", "Failed to insert into MediaStore", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.localizedMessage, null)
                    }
                }
                "saveImage" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "image/png"
                    if (sourcePath == null || fileName == null) {
                        result.error("INVALID_ARGS", "sourcePath or fileName is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(saveImageToPictures(sourcePath, fileName, mimeType))
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.localizedMessage, null)
                    }
                }
                "getExitReasons" -> {
                    try {
                        result.success(collectExitReasons())
                    } catch (e: Exception) {
                        result.success(emptyList<Map<String, Any?>>())
                    }
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null, null)
                    }
                    result.success(true)
                }
                "installApk" -> {
                    val contentUriString = call.argument<String>("contentUri")
                    val filePath = call.argument<String>("filePath")

                    try {
                        val uri: Uri = if (contentUriString != null) {
                            Uri.parse(contentUriString)
                        } else if (filePath != null) {
                            val apkFile = File(filePath)
                            FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", apkFile)
                        } else {
                            result.error("INVALID_ARGS", "No URI or path provided", null)
                            return@setMethodCallHandler
                        }

                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Saves exported videos / images into the ROOT Movies folder: /storage/emulated/0/Movies/Shaderly
    // (Movies is created if it does not exist). Android 10+ goes through MediaStore (no permission needed),
    // with a direct-file fallback; Android 9 and lower writes the file directly.
    private fun moviesShaderlyDir(): File {
        val movies = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
        if (!movies.exists()) movies.mkdirs()
        val dir = File(movies, "Shaderly")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun copyToMoviesFolder(sourceFile: File, fileName: String): Uri? {
        val target = File(moviesShaderlyDir(), fileName)
        FileInputStream(sourceFile).use { input ->
            FileOutputStream(target).use { out -> input.copyTo(out) }
        }
        MediaScannerConnection.scanFile(applicationContext, arrayOf(target.absolutePath), null, null)
        return Uri.fromFile(target)
    }

    private fun insertViaMediaStore(
        collection: Uri,
        sourceFile: File,
        fileName: String,
        mimeType: String,
        relativePath: String = Environment.DIRECTORY_MOVIES + "/Shaderly"
    ): Uri? {
        val resolver = applicationContext.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(collection, values) ?: return null
        try {
            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input -> input.copyTo(out) }
            } ?: throw IllegalStateException("openOutputStream returned null")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return uri
        } catch (e: Exception) {
            try { resolver.delete(uri, null, null) } catch (_: Exception) {}
            throw e
        }
    }

    // ---------------------------------------------------------------------------------------------------
    // IMAGES -> Pictures/Shaderly
    // MediaStore refuses images inside Movies (EPERM), but Pictures/Shaderly always works without any permission
    // on Android 10+. Android 9 and lower write the file directly.
    // ---------------------------------------------------------------------------------------------------
    private fun saveImageToPictures(sourcePath: String, fileName: String, mimeType: String): Map<String, String> {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) throw IllegalStateException("Source image does not exist: $sourcePath")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val images = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = insertViaMediaStore(images, sourceFile, fileName, mimeType, Environment.DIRECTORY_PICTURES + "/Shaderly")
                ?: throw IllegalStateException("MediaStore insert returned null")
            return mapOf("uri" to uri.toString(), "location" to "Pictures/Shaderly")
        }

        val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Shaderly")
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, fileName)
        FileInputStream(sourceFile).use { input ->
            FileOutputStream(target).use { out -> input.copyTo(out) }
        }
        MediaScannerConnection.scanFile(applicationContext, arrayOf(target.absolutePath), null, null)
        return mapOf("uri" to Uri.fromFile(target).toString(), "location" to "Pictures/Shaderly")
    }

    // ---------------------------------------------------------------------------------------------------
    // CRASH EVIDENCE (Android 11+): how did the previous process of this app end?
    // For native crashes the tombstone is attached; its readable strings contain the signal, the library
    // and the function names (e.g. libx265 / libavcodec / libvulkan_processor).
    // ---------------------------------------------------------------------------------------------------
    private fun exitReasonName(reason: Int): String = when (reason) {
        0 -> "UNKNOWN"
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH (Java/Kotlin exception)"
        5 -> "CRASH_NATIVE"
        6 -> "ANR (app not responding)"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "REASON_$reason"
    }

    private fun readTraceStrings(info: ApplicationExitInfo): String {
        return try {
            val stream = info.traceInputStream ?: return ""
            val buf = java.io.ByteArrayOutputStream()
            stream.use { s ->
                val chunk = ByteArray(8192)
                var total = 0
                while (total < 600_000) {
                    val n = s.read(chunk)
                    if (n <= 0) break
                    buf.write(chunk, 0, n)
                    total += n
                }
            }
            val bytes = buf.toByteArray()
            val seen = LinkedHashSet<String>()
            val run = StringBuilder()
            fun flushRun() {
                if (run.length >= 6) seen.add(run.toString())
                run.setLength(0)
            }
            for (b in bytes) {
                val c = b.toInt() and 0xFF
                if (c in 32..126) run.append(c.toChar()) else flushRun()
                if (seen.size >= 140) break
            }
            flushRun()
            seen.take(110).joinToString("\n").take(5000)
        } catch (e: Exception) {
            ""
        }
    }

    private fun collectExitReasons(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val infos = am.getHistoricalProcessExitReasons(packageName, 0, 4)
        val out = ArrayList<Map<String, Any?>>()
        for (info in infos) {
            val m = HashMap<String, Any?>()
            m["reason"] = info.reason
            m["reasonName"] = exitReasonName(info.reason)
            m["timestamp"] = info.timestamp
            m["status"] = info.status
            m["importance"] = info.importance
            m["description"] = info.description ?: ""
            m["pssKb"] = info.pss
            m["rssKb"] = info.rss
            if (info.reason == 5) m["trace"] = readTraceStrings(info)
            out.add(m)
        }
        return out
    }

    private fun saveFileToMoviesShaderly(sourcePath: String, fileName: String, mimeType: String): Uri? {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) return null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val isVideo = mimeType.startsWith("video/")
            // Videos belong to the Video collection (Movies is an allowed folder there). The Images collection only
            // allows DCIM / Pictures, so images are put into the generic Files collection to land in Movies/Shaderly.
            val primary = if (isVideo) MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                          else MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            try {
                val uri = insertViaMediaStore(primary, sourceFile, fileName, mimeType)
                if (uri != null) return uri
            } catch (e: Exception) {
                android.util.Log.w("AEReality", "MediaStore save failed, trying direct file copy: ${e.message}")
            }
            // Fallback: direct file into Movies/Shaderly (works with All-files access)
            return copyToMoviesFolder(sourceFile, fileName)
        } else {
            // Android 9 and lower
            return copyToMoviesFolder(sourceFile, fileName)
        }
    }
}
