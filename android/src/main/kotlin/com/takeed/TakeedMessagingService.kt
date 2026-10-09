package com.takeed

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** FCM entry point. Shows Takeed messages itself so buttons, images and receipts work with the app closed. */
class TakeedMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Store.saveToken(applicationContext, token)
        TakeedPlugin.instance?.onToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        if (!data.containsKey("takeed_notification_id")) return

        Events.report(applicationContext, data, "received")

        // A system-displayed message (notification payload) is shown by Android already.
        if (message.notification != null) return

        val plugin = TakeedPlugin.instance
        if (plugin != null && plugin.isInForeground()) {
            plugin.onForeground(data)
        } else {
            NotificationDisplay.show(applicationContext, data)
        }
    }
}
