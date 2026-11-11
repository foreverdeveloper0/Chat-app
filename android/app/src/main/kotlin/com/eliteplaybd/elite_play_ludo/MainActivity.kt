package com.eliteplaybd.elite_play_ludo

import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Shares the downloaded update APK with Android's installer. */
class UpdateFileProvider : FileProvider()

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The in-app updater: Dart downloads the APK, this hands it over.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "elite_play/update")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "dir" -> {
                            val dir = File(cacheDir, "updates")
                            dir.mkdirs()
                            result.success(dir.absolutePath)
                        }
                        "install" -> {
                            val file = File(call.argument<String>("path") ?: "")
                            if (!file.exists()) {
                                result.error("missing", "The downloaded file is missing", null)
                            } else {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.updates", file
                                )
                                val intent = Intent(Intent.ACTION_VIEW)
                                intent.setDataAndType(uri, "application/vnd.android.package-archive")
                                intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(null)
                            }
                        }
                        "open" -> {
                            val intent = Intent(
                                Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url") ?: "")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Throwable) {
                    result.error("update", e.message ?: e.toString(), null)
                }
            }
    }
}
