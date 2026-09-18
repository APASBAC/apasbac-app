package com.example.apasbac_app.update

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class UpdateDownloadService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    @Volatile private var connection: HttpURLConnection? = null
    private var started = false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val store = UpdateStore(this)
        if (intent?.action == "cancel") {
            if (!store.prefs.getBoolean("mandatory", false)) cancelDownload()
            return START_NOT_STICKY
        }
        if (started) return START_NOT_STICKY
        started = true
        running = true
        val notification = UpdateNotifications.build(this, "Preparando atualização...")
        if (Build.VERSION.SDK_INT >= 29) startForeground(UpdateNotifications.ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(UpdateNotifications.ID, notification)
        worker.execute { download(store) }
        return START_NOT_STICKY
    }
    private fun download(store: UpdateStore) {
        val wake = getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "apasbac:update")
        try {
            wake.acquire(16 * 60 * 1000L)
            val manifest = store.manifest ?: throw UpdateFailure("invalid_manifest")
            store.cleanup()
            store.event("update_download_started")
            val began = SystemClock.elapsedRealtime()
            val conn = open(manifest.url)
            val length = conn.contentLengthLong
            if (length > 0 && length != manifest.size) throw UpdateFailure("incomplete")
            var received = 0L
            var reported = 0L
            conn.inputStream.buffered().use { input ->
                store.part.outputStream().buffered().use { output ->
                    val bytes = ByteArray(65536)
                    while (true) {
                        if (cancelled) throw InterruptedException()
                        if (SystemClock.elapsedRealtime() - began > 15 * 60 * 1000) throw UpdateFailure("timeout")
                        val count = input.read(bytes)
                        if (count < 0) break
                        received += count
                        if (received > manifest.size) throw UpdateFailure("incomplete")
                        output.write(bytes, 0, count)
                        if (SystemClock.elapsedRealtime() - reported > 500) {
                            reported = SystemClock.elapsedRealtime()
                            store.prefs.edit().putLong("downloaded", received).apply()
                            val percent = (received * 100 / manifest.size).toInt()
                            UpdateNotifications.progress(this,
                                UpdateNotifications.build(this, "Baixando versão ${manifest.name} — $percent%", percent))
                        }
                    }
                }
            }
            if (cancelled) throw InterruptedException()
            store.prefs.edit().putLong("downloaded", received).commit()
            store.state("verifying")
            store.event("update_download_completed")
            UpdateNotifications.progress(this,
                UpdateNotifications.build(this, "Verificando atualização..."))
            UpdateVerifier(this).verify(store.part, manifest)
            if (cancelled) throw InterruptedException()
            if (!store.part.renameTo(store.apk)) throw UpdateFailure("storage")
            store.state("readyToInstall")
        } catch (e: Exception) {
            if (cancelled) {
                store.cleanup()
                // Never remove a mandatory gate, even if Android stopped the service.
                store.state("updateAvailable", "Download interrompido. Tente novamente.")
            } else store.fail((e as? UpdateFailure)?.reason ?: "network")
        } finally {
            connection?.disconnect()
            if (wake.isHeld) wake.release()
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            if (store.state == "readyToInstall") UpdateNotifications.show(this, "Atualização pronta. Toque para instalar.")
            else if (store.state == "failed") UpdateNotifications.show(this, "Não foi possível atualizar. Toque para tentar novamente.")
            stopSelf()
        }
    }
    private fun open(address: String): HttpURLConnection {
        var url = URL(address)
        repeat(6) {
            if (cancelled) throw InterruptedException()
            if (url.protocol != "https" || url.userInfo != null ||
                (url.host != "github.com" && !url.host.endsWith(".githubusercontent.com"))) throw UpdateFailure("url")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000; readTimeout = 30000; instanceFollowRedirects = false
                setRequestProperty("Accept", "application/octet-stream")
                setRequestProperty("Accept-Encoding", "identity")
            }
            connection = conn
            when (conn.responseCode) {
                200 -> return conn
                301, 302, 303, 307, 308 -> {
                    val location = conn.getHeaderField("Location") ?: throw UpdateFailure("http")
                    url = URL(url, location)
                    conn.disconnect()
                }
                else -> throw UpdateFailure("http")
            }
        }
        throw UpdateFailure("redirect")
    }
    private fun cancelDownload() { cancelled = true; connection?.disconnect() }
    override fun onTimeout(startId: Int, fgsType: Int) { cancelDownload(); stopSelf() }
    override fun onDestroy() { cancelDownload(); worker.shutdown(); super.onDestroy() }
    companion object { @Volatile var running = false }
}
