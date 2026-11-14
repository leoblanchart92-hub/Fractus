// L'activité Flutter, plus un petit canal natif : version de l'appli, lien
// d'appairage reçu (fractus://pair…), permission de notifier, service de fond,
// et l'installation d'un APK téléchargé (mise à jour).

package app.fractus.fractus_mobile

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        grabLink(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        grabLink(intent)
    }

    private fun grabLink(i: Intent?) {
        val d = i?.dataString ?: return
        if (d.startsWith("fractus://")) pendingLink = d
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.fractus/native").setMethodCallHandler { call, result ->
            when (call.method) {
                "versionName" -> {
                    val v = try {
                        packageManager.getPackageInfo(packageName, 0).versionName ?: ""
                    } catch (_: Exception) {
                        ""
                    }
                    result.success(v)
                }
                "launchLink" -> {
                    result.success(pendingLink)
                    pendingLink = null
                }
                "requestNotifications" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4242)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "startService" -> {
                    FractusService.start(this)
                    result.success(true)
                }
                "stopService" -> {
                    FractusService.stop(this)
                    result.success(true)
                }
                "serviceRunning" -> result.success(FractusService.running)
                "cacheDir" -> result.success(cacheDir.absolutePath)
                "installApk" -> {
                    val path = call.argument<String>("path")
                    result.success(path != null && installApk(File(path)))
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Ouvre l'installateur Android sur l'APK téléchargé (dossier cache de l'appli). */
    private fun installApk(file: File): Boolean {
        if (!file.exists()) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val i = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(i)
            true
        } catch (_: Exception) {
            false
        }
    }
}
