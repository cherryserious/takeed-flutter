package com.takeed

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors

/** Reports receipts and clicks to Takeed from native code (works with the app closed). */
internal object Events {
    private val executor = Executors.newSingleThreadExecutor()

    fun report(context: Context, data: Map<String, String>, type: String, buttonId: String? = null) {
        val receipt = data["takeed_receipt_id"] ?: return
        val appId = data["takeed_app_id"] ?: Store.appId(context) ?: return
        val api = (data["takeed_api"] ?: Store.apiUrl(context) ?: return).trimEnd('/')
        if (!api.startsWith("https://") && !api.startsWith("http://")) return

        executor.execute {
            try {
                val url = URL("$api/api/v1/apps/${URLEncoder.encode(appId, "UTF-8")}/events")
                val conn = url.openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.connectTimeout = 10_000
                conn.readTimeout = 10_000
                conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json")
                val body = JSONObject().put("type", type).put("receipt_id", receipt)
                if (buttonId != null) body.put("button_id", buttonId)
                conn.outputStream.use { it.write(body.toString().toByteArray()) }
                conn.responseCode
                conn.disconnect()
            } catch (_: Exception) {
                // Best effort: a missed receipt only affects statistics.
            }
        }
    }
}
