package com.example.apasbac_app.update

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.UUID

@Suppress("DEPRECATION")
class UpdateStore(val context: Context) {
    val prefs = context.getSharedPreferences("android_updates", Context.MODE_PRIVATE)
    val directory: File get() = File(context.filesDir, "updates").also { it.mkdirs() }
    val part: File get() = File(directory, "update.part")
    val apk: File get() = File(directory, "update.apk")
    val state: String get() = prefs.getString("state", "idle")!!
    val manifest: UpdateManifest? get() = try { prefs.getString("manifest", null)?.let { UpdateManifest.parse(it) } } catch (_: Exception) { null }
    fun installed(): PackageInfo = context.packageManager.getPackageInfo(context.packageName,
        if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
    fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
    fun state(value: String, message: String? = null) {
        // Installation can kill the process immediately. Critical state must be durable
        // before invoking Android; asynchronous apply() is used only for progress.
        prefs.edit().putString("state", value).putString("message", message).commit()
    }
    fun event(name: String) = synchronized(lock) {
        val events = JSONArray(prefs.getString("events", "[]"))
        if (events.length() >= 30) events.remove(0)
        events.put(JSONObject().put("event", name).put("id", UUID.randomUUID().toString())
            .put("installedVersionCode", code(installed())).put("targetVersionCode", manifest?.code ?: 0))
        prefs.edit().putString("events", events.toString()).commit()
        if ((context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            android.util.Log.d("AppUpdate", name)
        }
    }
    fun fail(reason: String) = synchronized(lock) {
        part.delete()
        apk.delete()
        val message = when (reason) {
            "hash", "incomplete", "invalid_apk" -> "O arquivo de atualização está incompleto ou corrompido. Tente novamente."
            "package", "version", "signature" -> "Esta atualização não é compatível com o aplicativo instalado. Entre em contato com a APASBAC."
            "sdk" -> "Esta atualização exige uma versão mais recente do Android."
            "interrupted" -> "A atualização foi interrompida. Toque em Tentar novamente."
            "install" -> "A instalação não foi concluída. Tente novamente e confirme a atualização no Android."
            else -> "Não foi possível baixar a atualização. Verifique sua conexão e tente novamente."
        }
        prefs.edit().putInt("failures", prefs.getInt("failures", 0) + 1)
            .remove("pendingAction").remove("permissionRequested").commit()
        state("failed", message)
        event(if (reason == "hash") "update_hash_failed" else "update_install_failed")
    }
    fun cleanup() { part.delete(); apk.delete() }
    fun recover() = synchronized(lock) {
        val current = manifest
        if (current == null) {
            if (state != "idle") { cleanup(); state("idle") }
            return@synchronized
        }
        if (code(installed()) >= current.code) {
            if (prefs.getBoolean("installRequested", false)) event("update_install_success_detected")
            cleanup()
            context.getSystemService(android.app.NotificationManager::class.java).cancel(UpdateNotifications.ID)
            prefs.edit().remove("manifest").remove("sessionId").remove("pendingAction")
                .remove("permissionRequested").putBoolean("installRequested", false)
                .putInt("failures", 0).commit()
            state("idle")
        } else if (state in listOf("downloading", "verifying") && !UpdateDownloadService.running) {
            fail("interrupted")
        } else if (state == "installing" && !UpdateInstaller.preparing) {
            val session = context.packageManager.packageInstaller.getSessionInfo(prefs.getInt("sessionId", -1))
            if (session == null || System.currentTimeMillis() - prefs.getLong("installStarted", 0) > 600000) {
                session?.let { runCatching { context.packageManager.packageInstaller.abandonSession(it.sessionId) } }
                fail("install")
            }
        }
    }
    fun snapshot(): Map<String, Any?> = mapOf("state" to state,
        "message" to prefs.getString("message", null), "downloaded" to prefs.getLong("downloaded", 0),
        "failures" to prefs.getInt("failures", 0),
        "manifest" to manifest?.let { jsonMap(JSONObject(it.json)) })
    companion object {
        val lock = Any()
        fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
            when (val value = json.get(key)) {
                is JSONObject -> jsonMap(value)
                is JSONArray -> (0 until value.length()).map { value.get(it) }
                JSONObject.NULL -> null
                else -> value
            }
        }
    }
}
