package com.takeed

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.Locale
import java.util.TimeZone

class TakeedPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    companion object {
        private const val PERMISSION_REQUEST = 41_001

        @Volatile
        var instance: TakeedPlugin? = null
            private set

        fun clickPayload(data: Map<String, String>, actionId: String?, url: String?): Map<String, Any?> = mapOf(
            "notification_id" to data["takeed_notification_id"],
            "title" to data["takeed_title"],
            "body" to data["takeed_body"],
            "url" to url,
            "action_id" to actionId,
            "data" to Json.parseObject(data["takeed_data"]),
            "buttons" to Json.parseArray(data["takeed_buttons"]),
        )
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var resumed = 0
    private val main = Handler(Looper.getMainLooper())
    private val pendingForeground = HashMap<String, Map<String, String>>()

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) {
            resumed++
            if (resumed == 1) channel?.invokeMethod("onResume", null)
        }
        override fun onActivityPaused(a: Activity) { resumed = maxOf(0, resumed - 1) }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivityStopped(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
        override fun onActivityDestroyed(a: Activity) {}
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "takeed").also { it.setMethodCallHandler(this) }
        (binding.applicationContext as? Application)?.registerActivityLifecycleCallbacks(lifecycle)
        instance = this
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        (binding.applicationContext as? Application)?.unregisterActivityLifecycleCallbacks(lifecycle)
        if (instance === this) instance = null
    }

    fun hasEngine(): Boolean = channel != null

    fun isInForeground(): Boolean = resumed > 0

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val ctx = context ?: return result.error("no_context", "Plugin not attached", null)
        when (call.method) {
            "configure" -> {
                Store.configure(ctx, call.argument<String>("app_id") ?: "")
                result.success(null)
            }
            "androidPackage" -> result.success(ctx.packageName)
            "configureFirebase" -> configureFirebase(ctx, call, result)
            "pushToken" -> pushToken(result)
            "permission" -> result.success(NotificationManagerCompat.from(ctx).areNotificationsEnabled())
            "requestPermission" -> requestPermission(ctx, result)
            "deviceInfo" -> result.success(deviceInfo(ctx))
            "initialClick" -> result.success(Store.takeInitialClick(ctx))
            "displayForeground" -> {
                val id = call.argument<String>("notification_id")
                val data = id?.let { pendingForeground.remove(it) }
                if (data != null && call.argument<Boolean>("show") == true) NotificationDisplay.show(ctx, data)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Saves the Firebase settings Takeed sent for this app and starts Firebase with them. */
    private fun configureFirebase(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val settings = FirebaseSetup.Settings(
            projectId = call.argument<String>("project_id") ?: return result.error("bad_settings", "project_id missing", null),
            appId = call.argument<String>("app_id") ?: return result.error("bad_settings", "app_id missing", null),
            apiKey = call.argument<String>("api_key") ?: return result.error("bad_settings", "api_key missing", null),
            senderId = call.argument<String>("project_number") ?: return result.error("bad_settings", "project_number missing", null),
            storageBucket = call.argument<String>("storage_bucket"),
        )
        Store.saveFirebase(ctx, settings)
        result.success(FirebaseSetup.app(ctx) != null)
    }

    private fun pushToken(result: MethodChannel.Result) {
        val app = FirebaseSetup.app(context!!)
            ?: return result.error("firebase_missing", "No Firebase settings from Takeed yet: add google-services.json to the app's Firebase key in the dashboard.", null)
        val projectId = app.options.projectId
        FirebaseSetup.messaging(app).token.addOnCompleteListener { task ->
            main.post {
                if (task.isSuccessful && task.result != null) {
                    Store.saveToken(context!!, task.result)
                    result.success(mapOf("type" to "android", "token" to task.result, "config_identifier" to projectId))
                } else {
                    result.success(null)
                }
            }
        }
    }

    private fun requestPermission(ctx: Context, result: MethodChannel.Result) {
        val act = activity
        if (Build.VERSION.SDK_INT < 33 || act == null ||
            ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(NotificationManagerCompat.from(ctx).areNotificationsEnabled())
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        ActivityCompat.requestPermissions(act, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
        channel?.invokeMethod("onPermission", mapOf("granted" to granted))
        return true
    }

    private fun deviceInfo(ctx: Context): Map<String, Any?> {
        val version = try {
            ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName
        } catch (e: Exception) {
            null
        }
        return mapOf(
            "device_model" to "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(128),
            "os_version" to "Android ${Build.VERSION.RELEASE}",
            "app_version" to version,
            "language" to Locale.getDefault().language,
            "timezone" to TimeZone.getDefault().id,
        )
    }

    fun onToken(token: String) = main.post { channel?.invokeMethod("onToken", mapOf("token" to token)) }

    fun onClick(payload: Map<String, Any?>) = main.post { channel?.invokeMethod("onClick", payload) }

    /** Asks Dart whether to show a notification that arrived while the app is open. */
    fun onForeground(data: Map<String, String>) = main.post {
        val id = data["takeed_notification_id"] ?: return@post
        val ctx = context ?: return@post
        pendingForeground[id] = data
        channel?.invokeMethod("onForeground", clickPayload(data, null, data["takeed_url"]), object : MethodChannel.Result {
            override fun success(result: Any?) {
                // false = the listener called preventDefault() (it may call display() later).
                if (result != false && pendingForeground.remove(id) != null) NotificationDisplay.show(ctx, data)
            }
            override fun error(code: String, message: String?, details: Any?) {
                pendingForeground.remove(id)?.let { NotificationDisplay.show(ctx, it) }
            }
            override fun notImplemented() {
                pendingForeground.remove(id)?.let { NotificationDisplay.show(ctx, it) }
            }
        }) ?: NotificationDisplay.show(ctx, data)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }
}
