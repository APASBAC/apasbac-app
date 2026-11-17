package com.example.apasbac_app.update

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
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
        if (store.state == "installing" && store.prefs.getBoolean("systemInstallerOpened", false) &&
            System.currentTimeMillis() - store.prefs.getLong("installStarted", 0) > 2000) {
            // Voltou do instalador do Android sem a versão nova: a pessoa cancelou.
            // Mantém o arquivo verificado e oferece abrir o instalador de novo.
            store.prefs.edit().remove("systemInstallerOpened").remove("permissionRequested").commit()
            store.state("needsUserPermission",
                "A atualização ainda não foi instalada. Toque no botão abaixo e confirme em \"Atualizar\" ou \"Instalar\".")
            return
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
        if (store.prefs.getBoolean("useSystemInstaller", false)) {
            systemInstall(context, store, manifest)
            return@synchronized
        }
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
                val reason = (e as? UpdateFailure)?.reason
                if (reason == null) store.prefs.edit().putBoolean("useSystemInstaller", true).commit()
                store.fail(reason ?: "install", if (reason == null) e.javaClass.simpleName else null)
            } finally { preparing = false }
        }
    }

    /** Abre o instalador padrão do Android com o APK já verificado (hash, pacote e assinatura). */
    private fun systemInstall(context: Context, store: UpdateStore, manifest: UpdateManifest) {
        val app = context.applicationContext
        try {
            UpdateVerifier(app).verify(store.apk, manifest)
            val uri = FileProvider.getUriForFile(app, "${app.packageName}.fileprovider", store.apk)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            store.prefs.edit().putBoolean("installRequested", true).putBoolean("systemInstallerOpened", true)
                .putLong("installStarted", System.currentTimeMillis()).remove("sessionId")
                .remove("permissionRequested").commit()
            store.state("installing", "Confirme a atualização na tela do Android.")
            store.event("update_install_requested")
            val activity = foreground.get() ?: (context as? Activity)
            if (activity != null && !activity.isFinishing) activity.startActivity(intent)
            else UpdateNotifications.show(app, "Toque para confirmar a atualização.", intent)
        } catch (e: Exception) {
            store.prefs.edit().remove("systemInstallerOpened").commit()
            store.fail((e as? UpdateFailure)?.reason ?: "install", if (e is UpdateFailure) null else e.javaClass.simpleName)
        }
    }
}
