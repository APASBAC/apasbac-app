package com.example.apasbac_app.update

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

object UpdateInstaller {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile var preparing = false
    var foreground = WeakReference<Activity>(null)
    @Suppress("DEPRECATION")
    fun allowed(context: Context): Boolean = if (Build.VERSION.SDK_INT >= 26) {
        context.packageManager.canRequestPackageInstalls()
    } else {
        // Android 7 has a user-wide setting, before per-source authorizations existed.
        Settings.Secure.getInt(context.contentResolver, Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1
    }
    fun permission(activity: Activity) {
        val store = UpdateStore(activity)
        if (allowed(activity)) { install(activity); return }
        store.prefs.edit().putBoolean("permissionRequested", true).commit()
        store.state("needsUserPermission")
        if (Build.VERSION.SDK_INT >= 26) activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:${activity.packageName}")))
        else activity.startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
    }
    fun resume(activity: Activity) {
        val store = UpdateStore(activity)
        store.recover()
        if (store.state == "needsUserPermission" && store.prefs.getBoolean("permissionRequested", false) && allowed(activity)) {
            install(activity)
        }
        if (store.state == "installing") {
            store.prefs.getString("pendingAction", null)?.let { action ->
                store.prefs.edit().remove("pendingAction").commit()
                try { activity.startActivity(Intent.parseUri(action, Intent.URI_INTENT_SCHEME)) }
                catch (_: Exception) { store.fail("install") }
            }
        }
    }
    fun install(context: Context) = synchronized(UpdateStore.lock) {
        val store = UpdateStore(context)
        if (preparing || store.state !in listOf("readyToInstall", "needsUserPermission")) return@synchronized
        if (!allowed(context)) { store.state("needsUserPermission"); return@synchronized }
        val manifest = store.manifest ?: return@synchronized
        preparing = true
        store.state("installing")
        val app = context.applicationContext
        worker.execute {
            var sessionId = -1
            try {
                // Verify again immediately before copying into the private installer session.
                UpdateVerifier(app).verify(store.apk, manifest)
                val installer = app.packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(app.packageName)
                    setSize(manifest.size)
                    if (Build.VERSION.SDK_INT >= 31) setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
                }
                sessionId = installer.createSession(params)
                store.prefs.edit().putInt("sessionId", sessionId).putBoolean("installRequested", true)
                    .putLong("installStarted", System.currentTimeMillis()).remove("permissionRequested").commit()
                installer.openSession(sessionId).use { session ->
                    session.openWrite("base.apk", 0, manifest.size).use { output ->
                        store.apk.inputStream().use { it.copyTo(output) }
                        session.fsync(output)
                    }
                    val intent = Intent(app, InstallStatusReceiver::class.java)
                        .setAction("${app.packageName}.UPDATE_STATUS.$sessionId")
                    val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                    val callback = PendingIntent.getBroadcast(app, sessionId, intent, flags)
                    store.event("update_install_requested")
                    session.commit(callback.intentSender)
                }
            } catch (e: Exception) {
                if (sessionId >= 0) runCatching { app.packageManager.packageInstaller.abandonSession(sessionId) }
                store.fail((e as? UpdateFailure)?.reason ?: "install")
            } finally { preparing = false }
        }
    }
}
