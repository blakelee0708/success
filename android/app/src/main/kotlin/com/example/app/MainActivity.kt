package com.example.app

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The launcher's platform side: opening other apps, and this app's standing as
 * the phone's home app.
 *
 * Kept to those two jobs deliberately. Everything a senior sees is drawn in
 * Flutter, and anything decided here cannot be covered by `flutter test`.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> result.success(
                        open(
                            call.argument<String>("packageName"),
                            call.argument<String>("intent"),
                            call.argument<String>("fallbackUrl"),
                        )
                    )
                    "isDefaultHome" -> result.success(isDefaultHome())
                    "deviceStatus" -> result.success(deviceStatus())
                    "openHomeSettings" -> result.success(openHomeSettings())
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Pressing Home while the senior is inside 설정 or SOS delivers a new HOME
     * intent to this already-running task rather than starting an activity, so
     * without this the home key looks broken from anywhere but the home screen.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME)) {
            channel?.invokeMethod("goHome", null)
        }
    }

    /**
     * Package first, then the system category, then the web. Returns false when
     * none of them resolved — the caller says so in the senior's own words
     * instead of leaving them tapping a tile that does nothing.
     */
    private fun open(packageName: String?, intent: String?, fallbackUrl: String?): Boolean {
        if (packageName != null) {
            packageManager.getLaunchIntentForPackage(packageName)?.let { if (start(it)) return true }
        }
        for (candidate in intentsFor(intent)) if (start(candidate)) return true
        if (fallbackUrl != null) {
            return start(Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUrl)))
        }
        return false
    }

    /**
     * Asked for by category rather than by package, so each phone opens the
     * dialer, messenger and gallery its owner already uses.
     *
     * `dial` is ACTION_DIAL and never ACTION_CALL: `06_PERMISSION_AND_POLICY`
     * requires that the user press call themselves, and that holds for the 전화
     * button exactly as it does for SOS.
     */
    private fun intentsFor(name: String?): List<Intent> = when (name) {
        "dial" -> listOf(Intent(Intent.ACTION_DIAL))
        "messaging" -> listOf(
            appIntent(Intent.CATEGORY_APP_MESSAGING),
            Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:")),
        )
        // CATEGORY_APP_GALLERY is the documented way and it is also the one
        // most Korean phones do not answer: neither Samsung Gallery nor Google
        // Photos declares it, so on the phone this was tested on the 앨범 tile
        // did nothing at all. Viewing the image collection is what a gallery
        // app actually registers for, so that is the fallback.
        "gallery" -> listOf(
            appIntent(Intent.CATEGORY_APP_GALLERY),
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, "image/*"),
            Intent(Intent.ACTION_VIEW).setType("image/*"),
        )
        "browser" -> listOf(
            appIntent(Intent.CATEGORY_APP_BROWSER),
            Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com")),
        )
        "camera" -> listOf(
            Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA),
            Intent(MediaStore.ACTION_IMAGE_CAPTURE),
        )
        else -> emptyList()
    }

    private fun appIntent(category: String): Intent =
        Intent(Intent.ACTION_MAIN).addCategory(category)

    /**
     * Caught rather than checked with resolveActivity: under Android 11's
     * package visibility rules resolveActivity can answer null for something
     * that would in fact start, and a tile that silently refuses is worse than
     * one that tries.
     */
    private fun start(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: ActivityNotFoundException) {
        false
    } catch (e: SecurityException) {
        false
    }

    /**
     * 기기 상태 — the battery and the ringer, for the guardian's dashboard.
     *
     * Both are free: Android hands them to any app with no runtime permission,
     * no manifest permission and nothing for Play to review. That is the whole
     * reason this exists before 위치, which cannot ship until the
     * 위치기반서비스사업 신고 is through.
     *
     * The network is deliberately not reported. ConnectivityManager would mean
     * asking for ACCESS_NETWORK_STATE, and the answer is already implied by the
     * call having arrived at all.
     *
     * Every value is omitted rather than defaulted when it cannot be read. The
     * Flutter side treats a missing key as "this phone did not say" and leaves
     * the last real reading standing; a 0 here would be drawn on the dashboard
     * as 배터리 0%, the most alarming reading on the card, invented.
     */
    private fun deviceStatus(): Map<String, Any> {
        val status = HashMap<String, Any>()

        // ACTION_BATTERY_CHANGED is sticky, so registering a null receiver
        // returns the last broadcast immediately rather than waiting for the
        // next change — which may be minutes away on a phone sitting still.
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (battery != null) {
            val level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
            // The scale is not always 100. Dividing by a hard-coded 100 is the
            // usual way this reads 7% on a phone that is actually full.
            if (level >= 0 && scale > 0) {
                status["batteryPercent"] = level * 100 / scale
            }
            when (battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
                BatteryManager.BATTERY_STATUS_CHARGING,
                BatteryManager.BATTERY_STATUS_FULL -> status["isCharging"] = true
                BatteryManager.BATTERY_STATUS_DISCHARGING,
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> status["isCharging"] = false
                // BATTERY_STATUS_UNKNOWN and anything new: say nothing.
            }
        }

        // Reading the ringer mode needs no permission. *Changing* it needs
        // Do Not Disturb access, which this app neither has nor wants — the
        // dashboard reports what the parent chose, it does not override it.
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        when (audio?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> status["ringer"] = "silent"
            AudioManager.RINGER_MODE_VIBRATE -> status["ringer"] = "vibrate"
            AudioManager.RINGER_MODE_NORMAL -> status["ringer"] = "normal"
            else -> {}
        }

        return status
    }

    private fun isDefaultHome(): Boolean {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)
        return resolved?.activityInfo?.packageName == packageName
    }

    /**
     * Android 10 and up can ask inside the app through the HOME role, which is
     * one dialog rather than a trip into Settings — worth the branch, since the
     * senior is the one who has to complete it.
     */
    private fun openHomeSettings(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val roles = getSystemService(RoleManager::class.java)
            if (roles != null &&
                roles.isRoleAvailable(RoleManager.ROLE_HOME) &&
                !roles.isRoleHeld(RoleManager.ROLE_HOME)
            ) {
                // startActivityForResult, and without FLAG_ACTIVITY_NEW_TASK.
                // The platform's role-request screen identifies the asker with
                // getCallingPackage(), which is null for a plain startActivity
                // — so it closes again immediately and the button looks dead.
                // That is exactly what happened on the phone this was tested
                // on: nothing at all.
                try {
                    startActivityForResult(
                        roles.createRequestRoleIntent(RoleManager.ROLE_HOME),
                        REQUEST_HOME_ROLE,
                    )
                    return true
                } catch (e: ActivityNotFoundException) {
                    // Fall through to the settings screens below.
                }
            }
        }
        // Not every phone has every one of these. Samsung in particular may
        // answer none of the first two, which is why the Flutter side has to
        // be told that nothing opened rather than being left to assume.
        return start(Intent(Settings.ACTION_HOME_SETTINGS)) ||
            start(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS)) ||
            start(Intent(Settings.ACTION_SETTINGS))
    }

    private companion object {
        const val CHANNEL = "jalboine/launcher"
        const val REQUEST_HOME_ROLE = 1001
    }
}
