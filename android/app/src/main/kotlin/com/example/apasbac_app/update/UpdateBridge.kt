package com.example.apasbac_app.update

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.lang.ref.WeakReference

class UpdateBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "org.apasbac/app_update")
    init {
        channel.setMethodCallHandler { call, result ->
            try {
                val store = UpdateStore(activity)
                when (call.method) {
                    "installedVersion" -> {
                        val installed = store.installed()
                        result.success(mapOf("code" to store.code(installed), "name" to (installed.versionName ?: ""),
                            "packageName" to installed.packageName))
                    }
                    "isOnline" -> {
                        val manager = activity.getSystemService(ConnectivityManager::class.java)
                        val network = manager.activeNetwork
                        result.success(network != null && manager.getNetworkCapabilities(network)
                            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true)
                    }
                    "snapshot" -> { store.recover(); result.success(store.snapshot()) }
                    "download" -> {
                        synchronized(UpdateStore.lock) {
                            require(!UpdateDownloadService.running && !UpdateInstaller.preparing && store.state != "installing")
                            val manifest = UpdateManifest.parse(call.argument<String>("manifest")!!)
                            require(manifest.code > store.code(store.installed()))
                            val required = call.argument<Boolean>("mandatory") == true || manifest.mandatory || store.code(store.installed()) < manifest.minimum
                            val failures = if (store.manifest?.code == manifest.code) store.prefs.getInt("failures", 0) else 0
                            store.prefs.edit().putString("manifest", manifest.json).putBoolean("mandatory", required)
                                .putLong("downloaded", 0).putInt("failures", failures).remove("pendingAction").commit()
                            store.state("downloading")
                            UpdateDownloadService.running = true
                            try {
                                if (Build.VERSION.SDK_INT >= 33 && activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                                    !store.prefs.getBoolean("notificationAsked", false)) {
                                    store.prefs.edit().putBoolean("notificationAsked", true).commit()
                                    activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7401)
                                }
                                val service = Intent(activity, UpdateDownloadService::class.java)
                                if (Build.VERSION.SDK_INT >= 26) activity.startForegroundService(service) else activity.startService(service)
                            } catch (e: Exception) { UpdateDownloadService.running = false; store.fail("network"); throw e }
                        }
                        result.success(null)
                    }
                    "cancel" -> {
                        if (UpdateDownloadService.running && !store.prefs.getBoolean("mandatory", false)) {
                            activity.startService(Intent(activity, UpdateDownloadService::class.java).setAction("cancel"))
                        }
                        result.success(null)
                    }
                    "install" -> { UpdateInstaller.install(activity); result.success(null) }
                    "requestInstallPermission" -> { UpdateInstaller.permission(activity); result.success(null) }
                    "resume" -> { UpdateInstaller.resume(activity); result.success(null) }
                    "postpone" -> {
                        if (!store.prefs.getBoolean("mandatory", false)) {
                            store.prefs.edit().remove("permissionRequested").commit()
                        }
                        result.success(null)
                    }
                    "drainEvents" -> {
                        synchronized(UpdateStore.lock) {
                            val events = JSONArray(store.prefs.getString("events", "[]"))
                            store.prefs.edit().putString("events", "[]").commit()
                            result.success((0 until events.length()).map { UpdateStore.jsonMap(events.getJSONObject(it)) })
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) { result.error("UPDATE_FAILED", "Não foi possível atualizar. Tente novamente.", null) }
        }
    }
    fun resume() { UpdateInstaller.foreground = WeakReference(activity) }
    fun pause() { if (UpdateInstaller.foreground.get() === activity) UpdateInstaller.foreground.clear() }
    fun dispose() { pause(); channel.setMethodCallHandler(null) }
}
