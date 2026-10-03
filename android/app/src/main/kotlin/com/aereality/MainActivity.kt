package com.aereality

import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.aereality/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        MediaScannerConnection.scanFile(
                            context,
                            arrayOf(path),
                            null
                        ) { scannedPath, uri ->
                            result.success(uri?.toString() ?: scannedPath)
                        }
                    } else {
                        result.error("INVALID_PATH", "Path cannot be null", null)
                    }
                }
                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                    if (sourcePath == null || fileName == null) {
                        result.error("INVALID_ARGS", "sourcePath and fileName cannot be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val srcFile = File(sourcePath)
                        if (!srcFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source file does not exist: $sourcePath", null)
                            return@setMethodCallHandler
                        }

                        val resolver = applicationContext.contentResolver
                        val contentValues = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                        }

                        val collectionUri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            MediaStore.Downloads.EXTERNAL_CONTENT_URI
                        } else {
                            MediaStore.Files.getContentUri("external")
                        }

                        val itemUri = resolver.insert(collectionUri, contentValues)
                        if (itemUri == null) {
                            result.error("INSERT_FAILED", "Failed to create MediaStore entry in Downloads", null)
                            return@setMethodCallHandler
                        }

                        resolver.openOutputStream(itemUri)?.use { outStream ->
                            FileInputStream(srcFile).use { inStream ->
                                inStream.copyTo(outStream)
                            }
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            contentValues.clear()
                            contentValues.put(MediaStore.MediaColumns.IS_PENDING, 0)
                            resolver.update(itemUri, contentValues, null, null)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            result.success(itemUri.toString())
                        } else {
                            val publicPath = "/storage/emulated/0/Download/$fileName"
                            MediaScannerConnection.scanFile(context, arrayOf(publicPath), arrayOf(mimeType)) { _, _ ->
                                result.success(itemUri.toString())
                            }
                        }
                    } catch (e: Exception) {
                        result.error("COPY_FAILED", "Exception saving file to MediaStore: ${e.message}", null)
                    }
                }
                "installApk" -> {
                    val uriString = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType") ?: "application/vnd.android.package-archive"

                    if (uriString == null) {
                        result.error("INVALID_URI", "URI cannot be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val uri = Uri.parse(uriString)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", "Exception launching install: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
