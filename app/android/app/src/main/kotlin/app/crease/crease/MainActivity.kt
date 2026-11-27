package app.crease.crease

import android.os.Bundle
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val UPDATE_CHANNEL = "app.crease.crease/in_app_update"
    }

    private lateinit var appUpdateManager: AppUpdateManager
    private var updateChannel: MethodChannel? = null
    private var updatePromptInFlight = false

    private val installStateUpdatedListener = InstallStateUpdatedListener { state ->
        if (state.installStatus() == InstallStatus.DOWNLOADED) {
            notifyFlutterUpdateDownloaded()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appUpdateManager = AppUpdateManagerFactory.create(applicationContext)
        appUpdateManager.registerListener(installStateUpdatedListener)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updateChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATE_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkForFlexibleUpdate" -> {
                        checkForFlexibleUpdate(result)
                    }
                    "completeUpdate" -> {
                        completeFlexibleUpdate(result)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!::appUpdateManager.isInitialized) return
        // Per Google Play docs: if a flexible update finished downloading while
        // the app was backgrounded, notify Flutter so the user can restart to install.
        appUpdateManager.appUpdateInfo.addOnSuccessListener { info ->
            if (info.installStatus() == InstallStatus.DOWNLOADED) {
                notifyFlutterUpdateDownloaded()
            }
        }
    }

    override fun onDestroy() {
        if (::appUpdateManager.isInitialized) {
            appUpdateManager.unregisterListener(installStateUpdatedListener)
        }
        updateChannel?.setMethodCallHandler(null)
        updateChannel = null
        super.onDestroy()
    }

    private fun checkForFlexibleUpdate(result: MethodChannel.Result) {
        if (!::appUpdateManager.isInitialized) {
            result.success("unavailable")
            return
        }
        if (updatePromptInFlight) {
            result.success("in_progress")
            return
        }

        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { appUpdateInfo ->
                when {
                    appUpdateInfo.installStatus() == InstallStatus.DOWNLOADED -> {
                        notifyFlutterUpdateDownloaded()
                        result.success("downloaded")
                    }
                    appUpdateInfo.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                        appUpdateInfo.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) -> {
                        updatePromptInFlight = true
                        val options = AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build()
                        appUpdateManager
                            .startUpdateFlow(appUpdateInfo, this, options)
                            .addOnSuccessListener { flowResultCode ->
                                updatePromptInFlight = false
                                when (flowResultCode) {
                                    RESULT_OK -> result.success("started")
                                    RESULT_CANCELED -> result.success("dismissed")
                                    else -> result.success("failed")
                                }
                            }
                            .addOnFailureListener {
                                updatePromptInFlight = false
                                result.success("failed")
                            }
                    }
                    else -> result.success("up_to_date")
                }
            }
            .addOnFailureListener {
                // Expected on sideloaded/debug builds not installed via Play Store.
                result.success("unavailable")
            }
    }

    private fun completeFlexibleUpdate(result: MethodChannel.Result) {
        if (!::appUpdateManager.isInitialized) {
            result.success(false)
            return
        }
        appUpdateManager.completeUpdate()
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { result.success(false) }
    }

    private fun notifyFlutterUpdateDownloaded() {
        runOnUiThread {
            updateChannel?.invokeMethod("onUpdateDownloaded", null)
        }
    }
}
