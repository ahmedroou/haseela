package com.riham.haseela

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var pendingInstall: File? = null
    private var waitingPermission = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "haseela/updates")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "info" -> {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val dir = File(cacheDir, "updates").apply { mkdirs() }
                            result.success(mapOf(
                                "version" to info.versionName,
                                "abis" to Build.SUPPORTED_ABIS.toList(),
                                "directory" to dir.absolutePath
                            ))
                        }
                        "install" -> {
                            val path = call.argument<String>("path") ?: error("Missing APK")
                            val file = verifiedApk(path)
                            if (Build.VERSION.SDK_INT >= 26 && !packageManager.canRequestPackageInstalls()) {
                                pendingInstall = file
                                waitingPermission = true
                                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")))
                                result.success("permission")
                            } else {
                                launchInstaller(file)
                                result.success("installer")
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("UPDATE_ERROR", "تعذّر تثبيت التحديث. ${e.message}", null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun certificates(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28)
            info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { it.toCharsString() }?.toSet() ?: emptySet()
    }

    @Suppress("DEPRECATION")
    private fun verifiedApk(path: String): File {
        val dir = File(cacheDir, "updates").canonicalFile
        val file = File(path).canonicalFile
        require(file.parentFile == dir && file.extension == "apk" && file.isFile) {
            "ملف التحديث غير صالح"
        }
        val flags = if (Build.VERSION.SDK_INT >= 28)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val current = packageManager.getPackageInfo(packageName, flags)
        val next = packageManager.getPackageArchiveInfo(file.absolutePath, flags)
            ?: error("تعذّر قراءة ملف التحديث")
        require(next.packageName == packageName) { "التحديث لا يخص حصيلة" }
        val code = if (Build.VERSION.SDK_INT >= 28) next.longVersionCode else next.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        require(code > oldCode) { "النسخة ليست أحدث من النسخة المثبّتة" }
        val trusted = certificates(current)
        require(trusted.isNotEmpty() && trusted == certificates(next)) { "توقيع التحديث غير موثوق" }
        return file
    }

    private fun launchInstaller(file: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
        startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    override fun onResume() {
        super.onResume()
        if (waitingPermission && Build.VERSION.SDK_INT >= 26) {
            waitingPermission = false
            val file = pendingInstall
            pendingInstall = null
            if (file != null && packageManager.canRequestPackageInstalls()) {
                try { launchInstaller(verifiedApk(file.absolutePath)) }
                catch (_: Exception) { /* The sheet keeps an explicit retry button. */ }
            }
        }
    }
}
