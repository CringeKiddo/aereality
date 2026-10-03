package com.aereality

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
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
                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "video/mp4"

                    if (sourcePath == null || fileName == null) {
                        result.error("INVALID_ARGS", "sourcePath or fileName is null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val uri = saveFileToPublicDownloads(sourcePath, fileName, mimeType)
                        if (uri != null) {
                            result.success(uri.toString())
                        } else {
                            result.error("SAVE_FAILED", "Failed to insert into MediaStore", null)
                        }
                    } catch (e: Exception) {
                        result.error("EXCEPTION", e.localizedMessage, null)
                    }
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

    private fun saveFileToPublicDownloads(sourcePath: String, fileName: String, mimeType: String): Uri? {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) return null

        val resolver = applicationContext.contentResolver

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val contentValues = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, contentValues) ?: return null

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(out)
                }
            }

            contentValues.clear()
            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)
            return uri
        } else {
            // Android 9 and lower
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            if (!downloadsDir.exists()) downloadsDir.mkdirs()
            val targetFile = File(downloadsDir, fileName)

            FileInputStream(sourceFile).use { input ->
                FileOutputStream(targetFile).use { out ->
                    input.copyTo(out)
                }
            }
            return Uri.fromFile(targetFile)
        }
    }
}
