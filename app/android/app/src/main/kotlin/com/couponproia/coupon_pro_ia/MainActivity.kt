package com.couponproia.coupon_pro_ia

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // LOT 26 : mise à jour téléchargée et installée par l'application. Les appels
        // (empreinte d'un fichier de 33 Mo, écriture de l'installation) tournent hors du
        // fil de l'interface ; la réponse revient sur celui-ci.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coupon_pro_ia/updater")
            .setMethodCallHandler { call, result ->
                val c = applicationContext
                Thread {
                    try {
                        val value: Any? = when (call.method) {
                            "status" -> AppUpdater.status(c)
                            "startDownload" -> {
                                @Suppress("UNCHECKED_CAST")
                                AppUpdater.startDownload(c, call.arguments as Map<String, Any?>)
                            }
                            "cancel" -> AppUpdater.cancel(c)
                            "canInstall" -> AppUpdater.canInstall(c)
                            "openInstallSettings" -> AppUpdater.openInstallSettings(c)
                            "isUnmetered" -> AppUpdater.isUnmetered(c)
                            "install" -> AppUpdater.install(c)
                            else -> {
                                runOnUiThread { result.notImplemented() }
                                return@Thread
                            }
                        }
                        runOnUiThread { result.success(if (value is Unit) null else value) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("updater", e.message, null) }
                    }
                }.start()
            }
    }
}
