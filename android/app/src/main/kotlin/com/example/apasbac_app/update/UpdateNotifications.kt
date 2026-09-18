package com.example.apasbac_app.update

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.example.apasbac_app.MainActivity

object UpdateNotifications {
    const val ID = 7401
    private const val CHANNEL = "app_updates"
    fun build(context: Context, text: String, progress: Int? = null,
        ongoing: Boolean = true, action: Intent? = null): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Atualizações do aplicativo", NotificationManager.IMPORTANCE_LOW))
        val open = action ?: Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(context, ID, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, CHANNEL) else Notification.Builder(context)
        builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("Atualizando aplicativo").setContentText(text)
            .setContentIntent(pending).setOnlyAlertOnce(true).setOngoing(ongoing).setAutoCancel(!ongoing)
        if (ongoing) builder.setProgress(100, progress ?: 0, progress == null)
        return builder.build()
    }
    fun show(context: Context, text: String, action: Intent? = null) {
        // A denied Android 13 notification permission must not break the update.
        progress(context, build(context, text, ongoing = false, action = action))
    }
    fun progress(context: Context, notification: Notification) {
        if (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            runCatching { context.getSystemService(NotificationManager::class.java).notify(ID, notification) }
        }
    }
}
