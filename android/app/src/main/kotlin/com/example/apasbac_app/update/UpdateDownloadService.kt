package com.example.apasbac_app.update

import android.app.DownloadManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Environment
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.net.Uri
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Baixa a atualização em segundo plano.
 *
 * 1º caminho: o DownloadManager do próprio Android (o que apps grandes usam
 *    para APKs fora da Play Store): trata redirecionamentos, quedas de rede,
 *    troca Wi-Fi/dados e economia de bateria.
 * 2º caminho: download direto (HttpURLConnection), caso o DownloadManager
 *    esteja desativado ou falhe no aparelho.
 * Em qualquer caminho o arquivo só é aceito depois da verificação de tamanho,
 * SHA-256, pacote, versão e assinatura (UpdateVerifier).
 */
class UpdateDownloadService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var cancelled = false
    @Volatile private var connection: HttpURLConnection? = null
    @Volatile private var downloadId = -1L
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
            val problems = mutableListOf<String>()
            var done = false
            try {
                viaDownloadManager(store, manifest)
                done = true
            } catch (e: InterruptedException) {
                throw e
            } catch (e: Exception) {
                problems += "sistema: " + describe(e)
                store.part.delete()
            }
            if (!done) {
                if (cancelled) throw InterruptedException()
                try {
                    direct(store, manifest)
                } catch (e: InterruptedException) {
                    throw e
                } catch (e: Exception) {
                    problems += "direto: " + describe(e)
                    throw UpdateFailure((e as? UpdateFailure)?.reason ?: "network", problems.joinToString("; "))
                }
            }
            if (cancelled) throw InterruptedException()
            store.prefs.edit().putLong("downloaded", store.part.length()).commit()
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
            } else {
                val failure = e as? UpdateFailure
                store.fail(failure?.reason ?: "network", failure?.detail ?: describe(e))
            }
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

    private fun describe(e: Exception): String = when (e) {
        is UpdateFailure -> e.detail ?: e.reason
        else -> e.javaClass.simpleName + (e.message?.take(80)?.let { ": $it" } ?: "")
    }

    private fun progress(store: UpdateStore, manifest: UpdateManifest, received: Long) {
        store.prefs.edit().putLong("downloaded", received).apply()
        val percent = (received * 100 / manifest.size).toInt().coerceIn(0, 100)
        UpdateNotifications.progress(this,
            UpdateNotifications.build(this, "Baixando versão ${manifest.name} — $percent%", percent))
    }

    /** Download pelo serviço de downloads do Android. */
    private fun viaDownloadManager(store: UpdateStore, manifest: UpdateManifest) {
        val dm = getSystemService(DownloadManager::class.java) ?: throw UpdateFailure("network", "sem DownloadManager")
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: throw UpdateFailure("storage", "sem pasta de download")
        val target = File(dir, "socorro-bicho-update.apk")
        target.delete()
        val request = DownloadManager.Request(Uri.parse(manifest.url))
            .setTitle("Socorro Bicho ${manifest.name}")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_HIDDEN)
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .setMimeType("application/vnd.android.package-archive")
            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, target.name)
        val id = dm.enqueue(request)
        downloadId = id
        val began = SystemClock.elapsedRealtime()
        try {
            while (true) {
                if (cancelled) throw InterruptedException()
                if (SystemClock.elapsedRealtime() - began > 15 * 60 * 1000) throw UpdateFailure("timeout", "tempo esgotado")
                val cursor = dm.query(DownloadManager.Query().setFilterById(id))
                    ?: throw UpdateFailure("network", "consulta vazia")
                var status = 0
                var received = 0L
                var reason = 0
                cursor.use { c ->
                    if (!c.moveToFirst()) throw UpdateFailure("network", "download removido")
                    status = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    received = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    reason = c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                }
                when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        if (target.length() != manifest.size) throw UpdateFailure("incomplete")
                        target.inputStream().use { input ->
                            store.part.outputStream().use { output -> input.copyTo(output, 65536) }
                        }
                        return
                    }
                    DownloadManager.STATUS_FAILED -> throw UpdateFailure("network", "código $reason")
                    else -> if (received > 0) progress(store, manifest, received)
                }
                Thread.sleep(500)
            }
        } finally {
            downloadId = -1L
            runCatching { dm.remove(id) }
            target.delete()
        }
    }

    /** Download direto, usado se o DownloadManager falhar. */
    private fun direct(store: UpdateStore, manifest: UpdateManifest) {
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
                        progress(store, manifest, received)
                    }
                }
            }
        }
    }

    private fun open(address: String): HttpURLConnection {
        var url = URL(address)
        repeat(6) {
            if (cancelled) throw InterruptedException()
            if (url.protocol != "https" || url.userInfo != null ||
                (url.host != "github.com" && !url.host.endsWith(".githubusercontent.com"))) throw UpdateFailure("url", "endereço ${url.host}")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15000; readTimeout = 30000; instanceFollowRedirects = false
                setRequestProperty("Accept", "application/octet-stream")
                setRequestProperty("Accept-Encoding", "identity")
            }
            connection = conn
            when (val code = conn.responseCode) {
                200 -> return conn
                301, 302, 303, 307, 308 -> {
                    val location = conn.getHeaderField("Location") ?: throw UpdateFailure("http", "redirecionamento sem destino")
                    url = URL(url, location)
                    conn.disconnect()
                }
                else -> throw UpdateFailure("http", "HTTP $code")
            }
        }
        throw UpdateFailure("redirect", "redirecionamentos demais")
    }

    private fun cancelDownload() {
        cancelled = true
        connection?.disconnect()
        val id = downloadId
        if (id >= 0) runCatching { getSystemService(DownloadManager::class.java)?.remove(id) }
    }
    override fun onTimeout(startId: Int, fgsType: Int) { cancelDownload(); stopSelf() }
    override fun onDestroy() { cancelDownload(); worker.shutdown(); super.onDestroy() }
    companion object { @Volatile var running = false }
}
