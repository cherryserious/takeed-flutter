package com.takeed

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.app.NotificationManagerCompat

/** Handles a tap on a notification or one of its buttons, then opens the app or the link. */
class NotificationOpenActivity : Activity() {
    companion object {
        const val EXTRA_DATA = "takeed_data"
        const val EXTRA_ACTION = "takeed_action"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        @Suppress("UNCHECKED_CAST", "DEPRECATION")
        val data = (intent.getSerializableExtra(EXTRA_DATA) as? HashMap<String, String>) ?: hashMapOf()
        val actionId = intent.getStringExtra(EXTRA_ACTION)

        NotificationManagerCompat.from(this).cancel(NotificationDisplay.notificationId(data))
        Events.report(applicationContext, data, "clicked", actionId)

        val button = Json.parseArray(data["takeed_buttons"]).firstOrNull { it["id"]?.toString() == actionId }
        val url = (button?.get("url") ?: data["takeed_url"])?.toString()?.takeIf { it.startsWith("https://") || it.startsWith("http://") }

        val payload = TakeedPlugin.clickPayload(data, actionId, url)
        val plugin = TakeedPlugin.instance
        if (plugin != null && plugin.hasEngine()) plugin.onClick(payload) else Store.saveInitialClick(applicationContext, payload)

        val open = if (url != null) {
            Intent(Intent.ACTION_VIEW, Uri.parse(url))
        } else {
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        }
        open?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (open != null) runCatching { startActivity(open) }
        finish()
    }
}
