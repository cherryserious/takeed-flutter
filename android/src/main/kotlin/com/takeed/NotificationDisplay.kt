package com.takeed

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.net.HttpURLConnection
import java.net.URL

/** Builds and shows a notification from an Takeed data message. */
internal object NotificationDisplay {
    private const val DEFAULT_CHANNEL = "takeed_default"

    fun notificationId(data: Map<String, String>): Int = (data["takeed_notification_id"] ?: "").hashCode()

    fun show(context: Context, data: Map<String, String>) {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return

        val channelId = ensureChannel(context, data["takeed_channel_id"], data["takeed_sound"])
        val id = notificationId(data)
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(smallIcon(context, data["takeed_small_icon"]))
            .setContentTitle(data["takeed_title"])
            .setContentText(data["takeed_body"])
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(openIntent(context, data, null, id))

        data["takeed_color"]?.let { runCatching { builder.setColor(Color.parseColor(it)) } }
        data["takeed_group"]?.let { builder.setGroup(it) }

        val image = data["takeed_image"]?.let { download(it) }
        if (image != null) {
            builder.setLargeIcon(image)
            builder.setStyle(NotificationCompat.BigPictureStyle().bigPicture(image).bigLargeIcon(null as Bitmap?))
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(data["takeed_body"]))
        }

        Json.parseArray(data["takeed_buttons"]).take(3).forEachIndexed { index, button ->
            val buttonId = button["id"]?.toString() ?: return@forEachIndexed
            builder.addAction(0, button["text"]?.toString() ?: buttonId, openIntent(context, data, buttonId, id * 10 + index + 1))
        }

        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) {
            // Permission revoked between the check and the call.
        }
    }

    private fun openIntent(context: Context, data: Map<String, String>, buttonId: String?, requestCode: Int): PendingIntent {
        val intent = Intent(context, NotificationOpenActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION)
            putExtra(NotificationOpenActivity.EXTRA_DATA, HashMap(data))
            putExtra(NotificationOpenActivity.EXTRA_ACTION, buttonId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(context, requestCode, intent, flags)
    }

    private fun ensureChannel(context: Context, requested: String?, sound: String?): String {
        if (Build.VERSION.SDK_INT < 26) return requested ?: DEFAULT_CHANNEL
        val manager = context.getSystemService(NotificationManager::class.java)
        // An app-defined channel is used as is when it exists.
        if (requested != null && manager.getNotificationChannel(requested) != null) return requested

        val id = requested ?: DEFAULT_CHANNEL
        if (manager.getNotificationChannel(id) == null) {
            val channel = NotificationChannel(id, if (requested == null) "Notifications" else requested, NotificationManager.IMPORTANCE_HIGH)
            soundUri(context, sound)?.let {
                channel.setSound(it, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build())
            }
            manager.createNotificationChannel(channel)
        }
        return id
    }

    private fun soundUri(context: Context, name: String?): Uri? {
        if (name.isNullOrEmpty()) return null
        val res = context.resources.getIdentifier(name.substringBeforeLast('.'), "raw", context.packageName)
        return if (res != 0) Uri.parse("android.resource://${context.packageName}/$res") else null
    }

    private fun smallIcon(context: Context, name: String?): Int {
        val res = context.resources
        if (!name.isNullOrEmpty()) {
            val id = res.getIdentifier(name, "drawable", context.packageName)
            if (id != 0) return id
        }
        val fallback = res.getIdentifier("ic_stat_notification", "drawable", context.packageName)
        return if (fallback != 0) fallback else context.applicationInfo.icon
    }

    /** Downloads the image with a short timeout; returns null on any problem so the text still shows. */
    private fun download(url: String): Bitmap? {
        if (!url.startsWith("https://") && !url.startsWith("http://")) return null
        return try {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 5_000
            conn.readTimeout = 5_000
            conn.instanceFollowRedirects = true
            conn.inputStream.use { BitmapFactory.decodeStream(it) }
        } catch (_: Exception) {
            null
        }
    }
}
