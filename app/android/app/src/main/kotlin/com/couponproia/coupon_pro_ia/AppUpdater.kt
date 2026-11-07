package com.couponproia.coupon_pro_ia

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * LOT 26 : mise à jour téléchargée par le gestionnaire de téléchargements d'Android (elle
 * continue si l'application est fermée), vérifiée par son empreinte SHA-256, puis installée
 * par PackageInstaller. Sur Android 12 et plus, les mises à jour suivantes peuvent
 * s'installer sans confirmation (l'application est alors sa propre source d'installation).
 * Tout l'état est gardé ici (préférences « coupon_updater ») : il survit à la fermeture.
 */
object AppUpdater {
    private const val PREFS = "coupon_updater"
    private const val CHANNEL_ID = "app_updates"
    private const val NOTIF_READY = 7301
    private const val NOTIF_DONE = 7302

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun downloads(c: Context) = c.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    fun currentId(c: Context): Long = prefs(c).getLong("id", -1L)

    /** Lance (ou relance) le téléchargement d'une version. Textes déjà traduits par l'app. */
    fun startDownload(c: Context, args: Map<String, Any?>): Long {
        cancel(c)
        val version = args["version"] as String
        val dir = c.getExternalFilesDir("updates") ?: throw IllegalStateException("no_storage")
        val name = "coupon-pro-ia-$version.apk"
        File(dir, name).delete()
        val wifiOnly = args["wifiOnly"] == true
        val request = DownloadManager.Request(Uri.parse(args["url"] as String))
            .setTitle(args["title"] as String)
            .setDescription(args["description"] as String)
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(c, "updates", name)
            .setAllowedOverMetered(!wifiOnly)
            .setAllowedOverRoaming(!wifiOnly)
        val id = downloads(c).enqueue(request)
        prefs(c).edit()
            .putLong("id", id)
            .putString("version", version)
            .putString("sha256", (args["sha256"] as String).lowercase())
            .putString("path", File(dir, name).absolutePath)
            .putString("state", "downloading")
            .putString("readyTitle", args["readyTitle"] as String)
            .putString("readyBody", args["readyBody"] as String)
            .putString("doneTitle", args["doneTitle"] as String)
            .putString("doneBody", args["doneBody"] as String)
            .putString("channelName", args["channelName"] as String)
            .remove("error")
            .apply()
        return id
    }

    /** État : none, downloading, ready, corrupt, failed, installing ; progression en octets. */
    fun status(c: Context): Map<String, Any?> {
        val p = prefs(c)
        var state = p.getString("state", "none") ?: "none"
        var received = 0L
        var total = -1L
        var paused = false
        val id = p.getLong("id", -1L)
        if (state == "downloading" && id >= 0) {
            val cursor = downloads(c).query(DownloadManager.Query().setFilterById(id))
            if (cursor == null) {
                state = markFailed(c, "download_missing")
            } else {
                cursor.use { cur ->
                    if (!cur.moveToFirst()) {
                        state = markFailed(c, "download_missing")
                    } else {
                        received = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                        total = cur.getLong(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                        when (cur.getInt(cur.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                            DownloadManager.STATUS_SUCCESSFUL -> state = verify(c)
                            DownloadManager.STATUS_FAILED -> state = markFailed(c, "download_failed")
                            DownloadManager.STATUS_PAUSED -> paused = true
                        }
                    }
                }
            }
        }
        return mapOf(
            "state" to state,
            "version" to p.getString("version", null),
            "received" to received,
            "total" to total,
            "paused" to paused,
            "error" to p.getString("error", null),
        )
    }

    /** Vérifie le fichier reçu (empreinte obligatoire) : ready, ou corrupt et fichier supprimé. */
    fun verify(c: Context): String {
        val p = prefs(c)
        val path = p.getString("path", null) ?: return markFailed(c, "no_file")
        val expected = p.getString("sha256", "") ?: ""
        val file = File(path)
        val ok = file.exists() && expected.length == 64 && sha256(file) == expected
        if (!ok) file.delete()
        val state = if (ok) "ready" else "corrupt"
        p.edit().putString("state", state).apply()
        return state
    }

    private fun markFailed(c: Context, error: String): String {
        prefs(c).edit().putString("state", "failed").putString("error", error).apply()
        return "failed"
    }

    fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /** Annule le téléchargement en cours et oublie la version préparée. */
    fun cancel(c: Context) {
        val p = prefs(c)
        val id = p.getLong("id", -1L)
        if (id >= 0) {
            try {
                downloads(c).remove(id)
            } catch (_: Exception) {
            }
        }
        p.getString("path", null)?.let { File(it).delete() }
        p.edit().clear().apply()
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_READY)
    }

    /** L'application a-t-elle le droit d'installer des APK (« installer des applis inconnues ») ? */
    fun canInstall(c: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 26) c.packageManager.canRequestPackageInstalls() else true

    fun openInstallSettings(c: Context) {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${c.packageName}"))
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        c.startActivity(intent)
    }

    /** Réseau actuel sans coût (Wi-Fi) ? */
    fun isUnmetered(c: Context): Boolean {
        val cm = c.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        @Suppress("DEPRECATION")
        val connected = cm.activeNetworkInfo?.isConnected == true
        return connected && !cm.isActiveNetworkMetered
    }

    /** Installe la version prête (vérifiée une dernière fois juste avant). */
    fun install(c: Context): String {
        val p = prefs(c)
        if (p.getString("state", null) != "ready" && p.getString("state", null) != "installing") return "not_ready"
        p.edit().putString("state", "ready").apply()
        if (verify(c) != "ready") return "corrupt"
        val file = File(p.getString("path", "") ?: "")
        val installer = c.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(c.packageName)
        if (Build.VERSION.SDK_INT >= 31) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            session.openWrite("coupon-pro-ia.apk", 0, file.length()).use { out ->
                FileInputStream(file).use { input -> input.copyTo(out) }
                session.fsync(out)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            val callback = PendingIntent.getBroadcast(
                c, sessionId, Intent(c, InstallResultReceiver::class.java), flags,
            )
            session.commit(callback.intentSender)
        } catch (e: Exception) {
            session.abandon()
            p.edit().putString("error", e.message ?: "install_failed").apply()
            return "failed"
        } finally {
            session.close()
        }
        p.edit().putString("state", "installing").remove("error").apply()
        return "installing"
    }

    fun installFailed(c: Context, message: String?) {
        // Le fichier reste prêt : l'utilisateur peut réessayer.
        prefs(c).edit().putString("state", "ready").putString("error", message ?: "install_failed").apply()
    }

    private fun launchIntent(c: Context): PendingIntent? {
        val launch = c.packageManager.getLaunchIntentForPackage(c.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val immutable = if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getActivity(c, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or immutable)
    }

    private fun notify(c: Context, id: Int, title: String?, body: String?) {
        if (title == null) return
        val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val name = prefs(c).getString("channelName", null) ?: "Mises à jour"
            nm.createNotificationChannel(NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT))
            Notification.Builder(c, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(c)
        }
        builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
        launchIntent(c)?.let { builder.setContentIntent(it) }
        try {
            nm.notify(id, builder.build())
        } catch (_: SecurityException) {
            // Notifications refusées : le bandeau de l'accueil prend le relais.
        }
    }

    fun notifyReady(c: Context) {
        val p = prefs(c)
        notify(c, NOTIF_READY, p.getString("readyTitle", null), p.getString("readyBody", null))
    }

    /** Après l'installation : notification « à jour », fichier et état effacés. */
    fun onReplaced(c: Context) {
        val p = prefs(c)
        val title = p.getString("doneTitle", null)
        val body = p.getString("doneBody", null)
        val wasInstalling = p.getString("state", null) == "installing"
        cancel(c)
        if (wasInstalling) notify(c, NOTIF_DONE, title, body)
    }
}

/** Fin d'un téléchargement : vérification, puis notification « mise à jour prête ». */
class UpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (id < 0 || id != AppUpdater.currentId(context)) return
        val pending = goAsync()
        Thread {
            try {
                if (AppUpdater.status(context)["state"] == "ready") AppUpdater.notifyReady(context)
            } finally {
                pending.finish()
            }
        }.start()
    }
}

/** Résultat d'une installation demandée par l'application. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> Unit
            else -> AppUpdater.installFailed(context, intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE))
        }
    }
}

/** L'application vient d'être mise à jour. */
class AppReplacedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) AppUpdater.onReplaced(context)
    }
}
