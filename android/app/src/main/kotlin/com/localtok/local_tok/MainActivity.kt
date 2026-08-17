package com.localtok.local_tok

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val SAF_CHANNEL = "com.localtok.local_tok/saf"
    private val AUDIO_SERVICE_CHANNEL = "com.localtok.local_tok/background_audio"
    private var safChannel: MethodChannel? = null
    private var pendingResult: MethodChannel.Result? = null

    // ... (pickFolderLauncher remains largely same, just call the new scan logic)
    private val pickFolderLauncher =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri: Uri? ->
            val pending = pendingResult
            pendingResult = null
            if (uri == null) {
                pending?.success(null)
                return@registerForActivityResult
            }
            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            // Persist BOTH read and write: deleting files via
            // DocumentsContract.deleteDocument requires write access, so a
            // read-only persisted grant would make permanent delete fail
            // after the app is restarted.
            contentResolver.takePersistableUriPermission(uri, takeFlags)

            Thread {
                val files = scanFolderTree(uri)
                runOnUiThread {
                    pending?.success(mapOf("treeUri" to uri.toString(), "files" to files))
                }
            }.start()
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // SAF file operations channel
        safChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SAF_CHANNEL)
        safChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAndScan" -> {
                    pendingResult = result
                    pickFolderLauncher.launch(null)
                }
                "scan" -> {
                    val treeUriStr = call.argument<String>("treeUri") ?: return@setMethodCallHandler
                    val uri = Uri.parse(treeUriStr)
                    Thread {
                        try {
                            val files = scanFolderTree(uri)
                            runOnUiThread { result.success(files) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SCAN_ERROR", e.message, null) }
                        }
                    }.start()
                }
                "deleteFile" -> {
                    val uriStr = call.argument<String>("uri") ?: return@setMethodCallHandler
                    val uri = Uri.parse(uriStr)
                    Thread {
                        try {
                            val deleted = DocumentsContract.deleteDocument(contentResolver, uri)
                            runOnUiThread { result.success(deleted) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("DELETE_ERROR", e.message, null) }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }

        // Background audio service channel
        val audioServiceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUDIO_SERVICE_CHANNEL
        )
        audioServiceChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startBackgroundService" -> {
                    startBackgroundService()
                    result.success(true)
                }
                "stopBackgroundService" -> {
                    stopBackgroundService()
                    result.success(true)
                }
                "setPlaying" -> {
                    val playing = call.argument<Boolean>("playing") ?: false
                    // Service may not be running yet — the call is a no-op
                    // then (wakeLock == null).
                    BackgroundAudioService.setPlaying(playing)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startBackgroundService() {
        val intent = Intent(this, BackgroundAudioService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            ContextCompat.startForegroundService(this, intent)
        } else {
            startService(intent)
        }
    }

    private fun stopBackgroundService() {
        val intent = Intent(this, BackgroundAudioService::class.java).apply {
            action = BackgroundAudioService.ACTION_STOP
        }
        stopService(intent)
    }

    private fun scanFolderTree(treeUri: Uri): List<Map<String, Any>> {
        // 1. Permission Validation
        val hasPermission = contentResolver.persistedUriPermissions.any { 
            it.uri == treeUri && it.isReadPermission 
        }
        if (!hasPermission) {
            throw Exception("PERMISSION_LOST")
        }

        val results = mutableListOf<Map<String, Any>>()
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        
        reportProgress(0, "正在准备...")
        traverse(treeUri, rootId, results)
        
        return results
    }

    private fun traverse(treeUri: Uri, parentId: String, results: MutableList<Map<String, Any>>) {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            DocumentsContract.Document.COLUMN_SIZE
        )

        contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val modIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            val sizeIdx = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)

            while (cursor.moveToNext()) {
                val docId = cursor.getString(idIdx)
                val name = cursor.getString(nameIdx)
                val mime = cursor.getString(mimeIdx)
                val lastMod = cursor.getLong(modIdx)
                val size = cursor.getLong(sizeIdx)

                if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                    reportProgress(results.size, name)
                    traverse(treeUri, docId, results)
                } else if (isVideoMime(mime) || isVideoFile(name)) {
                    val fileUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                    results.add(mapOf(
                        "uri" to fileUri.toString(),
                        "name" to name,
                        "folderTreeUri" to treeUri.toString(),
                        "lastModified" to lastMod,
                        "size" to size
                    ))
                    if (results.size % 10 == 0) {
                        reportProgress(results.size, null)
                    }
                }
            }
        }
    }

    private fun reportProgress(count: Int, folderName: String?) {
        runOnUiThread {
            safChannel?.invokeMethod("onProgress", mapOf(
                "count" to count,
                "currentFolder" to folderName
            ))
        }
    }

    private fun isVideoMime(mime: String) = mime.startsWith("video/")

    private fun isVideoFile(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".mp4") || lower.endsWith(".mkv") || lower.endsWith(".webm")
    }
}
