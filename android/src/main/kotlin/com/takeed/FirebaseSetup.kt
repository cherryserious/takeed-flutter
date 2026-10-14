package com.takeed

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging

/**
 * Starts Firebase from the settings Takeed hands out (the google-services.json uploaded in the
 * dashboard), so apps don't ship the file or the Google services Gradle plugin.
 *
 * The settings are saved, and [TakeedInitProvider] applies them when the process starts, so
 * messages that wake a closed app are handled too.
 *
 * Takeed's Firebase becomes the default app when the app has none of its own. If the app
 * already uses Firebase (its own google-services.json) for the same project, that is reused;
 * for another project, Takeed's runs alongside it under its own name.
 */
internal object FirebaseSetup {
    private const val TAG = "Takeed"
    private const val NAME = "takeed"

    /** The Firebase app for Takeed's project, started if needed; null until settings are known. */
    fun app(context: Context): FirebaseApp? {
        val settings = Store.firebase(context) ?: return null
        val apps = FirebaseApp.getApps(context)

        apps.firstOrNull { it.options.projectId == settings.projectId && it.options.applicationId == settings.appId }?.let { return it }

        val options = FirebaseOptions.Builder()
            .setProjectId(settings.projectId)
            .setApplicationId(settings.appId)
            .setApiKey(settings.apiKey)
            .setGcmSenderId(settings.senderId)
            .apply { settings.storageBucket?.let { setStorageBucket(it) } }
            .build()

        return try {
            if (apps.none { it.name == FirebaseApp.DEFAULT_APP_NAME }) {
                FirebaseApp.initializeApp(context, options)
            } else {
                apps.firstOrNull { it.name == NAME } ?: FirebaseApp.initializeApp(context, options, NAME)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not start Firebase with the settings from Takeed", e)
            null
        }
    }

    fun messaging(app: FirebaseApp): FirebaseMessaging = app.get(FirebaseMessaging::class.java)

    data class Settings(val projectId: String, val appId: String, val apiKey: String, val senderId: String, val storageBucket: String?)
}
