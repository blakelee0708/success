package com.jalboine.app

import android.app.role.RoleManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import java.io.ByteArrayOutputStream
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
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
    private var tts: TextToSpeech? = null

    /** One thread, reused. A pool per call would outlive the call. */
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /**
     * The app list for the life of this process.
     *
     * Installing or removing an app while the launcher is running is rare and
     * the cost of missing it is small - the senior sees the list they saw a
     * moment ago. The cost of not caching is four seconds every time the
     * 추가하기 slot is pressed, on the one screen a senior reaches by
     * pressing something and waiting.
     */
    private var appList: List<Map<String, Any?>>? = null

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
                    // **Off the main thread, and this is the one call that
                    // must be.** A method channel handler runs on the UI
                    // thread, and listing the apps draws and PNG-encodes an
                    // icon for every launcher activity on the phone - eighty
                    // of them on an ordinary handset. Measured on a real
                    // phone it took four to five seconds, and for all of it
                    // the whole app was frozen: the senior pressed 전화 and
                    // nothing happened until the list was finished. Nothing
                    // else here is expensive enough to matter.
                    "installedApps" -> {
                        val cached = appList
                        if (cached != null) {
                            result.success(cached)
                        } else {
                            work.execute {
                                val apps = try {
                                    installedApps()
                                } catch (e: Exception) {
                                    emptyList()
                                }
                                // A `Result` may only be answered on the main
                                // thread; answering from the worker is the
                                // mistake this would otherwise introduce.
                                main.post {
                                    appList = apps
                                    result.success(apps)
                                }
                            }
                        }
                    }
                    "isDefaultHome" -> result.success(isDefaultHome())
                    "deviceStatus" -> result.success(deviceStatus())
                    "speak" -> result.success(speak(call.argument<String>("text")))
                    "stopSpeaking" -> result.success(stopSpeaking())
                    "openHomeSettings" -> result.success(openHomeSettings())
                    "setRingerMode" -> result.success(setRingerMode(call.argument<String>("mode")))
                    "openInternetPanel" -> result.success(openInternetPanel())
                    "openWifiSettings" -> result.success(openWifiSettings())
                    "openMobileDataSettings" -> result.success(openMobileDataSettings())
                    "internetStatus" -> result.success(internetStatus())
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
    /**
     * 소리 and 진동, and deliberately nothing else.
     *
     * RINGER_MODE_SILENT is left out because it needs ACCESS_NOTIFICATION_POLICY,
     * which is not a runtime dialog but a system settings screen the senior has
     * to find and switch on by themselves - the same ask as the home-app
     * chooser, and this app exists because they cannot make it. The product
     * reason is the stronger one: the guardian installs this because
     * 엄마가 전화를 안 받아, and a phone on silent is the first cause of that.
     *
     * It reads the mode back instead of trusting the write. Do Not Disturb can
     * accept the call and leave the ringer exactly where it was, and the one
     * moment that matters is the one where somebody is trying to get their
     * ringer back - so the Dart side is told false and says so, rather than
     * showing a label that lies.
     */
    private fun setRingerMode(mode: String?): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val target = when (mode) {
            "normal" -> AudioManager.RINGER_MODE_NORMAL
            "vibrate" -> AudioManager.RINGER_MODE_VIBRATE
            else -> return false
        }
        return try {
            audio.ringerMode = target
            audio.ringerMode == target
        } catch (e: SecurityException) {
            false
        }
    }

    /**
     * The phone's own internet sheet.
     *
     * There is no toggle to write here and there never will be:
     * `setWifiEnabled` has been a no-op for ordinary apps since Android 10, and
     * mobile data needs carrier privileges. The panel is what Google gave
     * instead - it needs no permission and it slides over this app rather than
     * sending the senior off into Settings to find their way back.
     *
     * Below Android 10 there is no panel, so the Wi-Fi settings screen stands
     * in. minSdk is 24, so that branch is real even though almost no phone
     * reaches it now.
     */
    private fun openInternetPanel(): Boolean = try {
        startActivity(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            } else {
                Intent(Settings.ACTION_WIFI_SETTINGS)
            }
        )
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /**
     * Wi-Fi and mobile data are **two destinations, not one**, and that was
     * learnt from a photograph of a real Galaxy. The panel above was supposed
     * to be a sheet carrying both; on that phone it arrived as Settings >
     * 연결, where Wi-Fi is a switch at the top and mobile data is not on the
     * screen at all - it is two taps further in, behind 모바일 네트워크 or
     * 데이터 사용. A senior sent there to turn their data on never finds it.
     *
     * So the app stops pretending one door covers both. Which one the senior
     * needs is decided on our own card, in our own words, and this takes them
     * to that one.
     *
     * Each tries the specific screen first and falls back outward, because
     * what a manufacturer's Settings app answers to is not something this
     * repository can check: there is no Android SDK here and the Kotlin has
     * never been compiled, let alone run.
     */
    private fun openWifiSettings(): Boolean =
        startFirst(listOf(Settings.ACTION_WIFI_SETTINGS, Settings.ACTION_WIRELESS_SETTINGS))

    private fun openMobileDataSettings(): Boolean = startFirst(
        listOf(
            // Samsung's 데이터 사용 carries the 모바일 데이터 switch at the top.
            Settings.ACTION_DATA_USAGE_SETTINGS,
            Settings.ACTION_NETWORK_OPERATOR_SETTINGS,
            Settings.ACTION_WIRELESS_SETTINGS,
        )
    )

    private fun startFirst(actions: List<String>): Boolean {
        for (action in actions) {
            try {
                startActivity(Intent(action))
                return true
            } catch (e: ActivityNotFoundException) {
                // The next one down.
            }
        }
        return false
    }

    /**
     * What the phone is on, for the card that is about to offer the two doors
     * above. `wifi`, `mobile`, `other` (ethernet, a dock), or `none`.
     *
     * **`ACCESS_NETWORK_STATE` is not declared by this repository's manifest**
     * - `firebase_messaging` brings it and Gradle merges it in, which is
     * recorded in `## 개인정보처리방침`. If that plugin ever goes, this reads
     * `unknown` rather than throwing, and the card falls back to offering both
     * doors, which is the answer it would give anyway.
     */
    private fun internetStatus(): String = try {
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = manager.activeNetwork
        val caps = if (network == null) null else manager.getNetworkCapabilities(network)
        when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            else -> "other"
        }
    } catch (e: SecurityException) {
        "unknown"
    }

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

    // 소리 울리기 lived here: STREAM_ALARM, a looping MediaPlayer, and a
    // stop that put it back. It is out of the product and so is the code.
    //
    // The sound was never the hard half. A push reaches the app only while
    // the app is in the foreground, so it made a noise on a phone that was
    // already awake and none at all on one in a bag in another room, which
    // is the case it existed for. Waking the phone needs a background
    // handler and USE_FULL_SCREEN_INTENT, which Android 14 does not grant a
    // launcher by default - and no published app was found that lets one
    // adult make another adult's phone sound, so a reviewer would be
    // meeting the idea for the first time here.

    /**
     * 읽어드리기 — reads a message out loud.
     *
     * Android's TTS is built in: no permission, no download, no account. A
     * Korean voice is present on effectively every Korean handset, and a
     * phone without one simply says nothing — the message is still on screen,
     * which is where it was before this existed.
     *
     * QUEUE_FLUSH rather than QUEUE_ADD: pressing a second message means
     * "read this one", not "read it after the other".
     */
    private fun speak(text: String?): Boolean {
        val say = text?.trim().orEmpty()
        if (say.isEmpty()) return false
        val engine = tts
        if (engine != null) {
            engine.speak(say, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID)
            return true
        }
        // First use: the engine is not ready until its init callback runs, so
        // the first press speaks from inside it rather than being dropped.
        tts = TextToSpeech(this) { status ->
            if (status != TextToSpeech.SUCCESS) {
                tts = null
                return@TextToSpeech
            }
            tts?.language = Locale.KOREAN
            tts?.speak(say, TextToSpeech.QUEUE_FLUSH, null, UTTERANCE_ID)
        }
        return true
    }

    private fun stopSpeaking(): Boolean {
        tts?.stop()
        return true
    }

    /** Nothing may outlive the screen that started it. */
    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
        // The activity is going; a worker still holding a `Result` for it is
        // not worth keeping alive. `shutdown` lets a running listing finish
        // and refuses new ones.
        work.shutdown()
        main.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    /**
     * Every app on this phone that has a launcher icon, with its name and its
     * icon, so the senior can put one on their home screen.
     *
     * This is the thing the product is actually for: seniors do not fail at
     * *opening* apps, they fail at **finding** them, and the app they most
     * want is rarely one of six categories.
     *
     * Visible through the `<intent>` query in the manifest rather than
     * QUERY_ALL_PACKAGES. That permission is Play-restricted and its published
     * list of acceptable uses does not include launchers, so asking for it
     * risks the listing over something an intent query already answers.
     *
     * The icons come back as PNG bytes and the Dart side keeps them beside the
     * button it made. Nothing a senior is looking at may wait on this channel,
     * so the home screen must never call it to draw a tile.
     */
    private fun installedApps(): List<Map<String, Any?>> {
        val main = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = packageManager.queryIntentActivities(main, 0)
        return resolved
            .asSequence()
            // This launcher itself is never worth offering: it is the screen
            // they would be putting the button on.
            .filter { it.activityInfo?.packageName != packageName }
            .mapNotNull { info ->
                val pkg = info.activityInfo?.packageName ?: return@mapNotNull null
                val label = info.loadLabel(packageManager)?.toString()?.trim()
                if (label.isNullOrEmpty()) return@mapNotNull null
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "icon" to iconBytes(info),
                )
            }
            // By name, because a senior scanning for 고스톱 is reading, not
            // remembering where it sat last time.
            .distinctBy { it["package"] }
            .sortedBy { it["label"] as String }
            .toList()
    }

    /**
     * An adaptive icon is a Drawable with no bitmap of its own, so it has to be
     * drawn onto one rather than cast. 96px squares: large enough for the tile
     * at 아주 크게 and small enough that eighty of them cross the channel
     * without stalling it.
     */
    private fun iconBytes(info: ResolveInfo): ByteArray? = try {
        val drawable = info.loadIcon(packageManager)
        val size = 96
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, size, size)
        drawable.draw(canvas)
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (e: Exception) {
        // An icon that will not render is no reason to leave the app out of
        // the list — the senior picks it by name either way.
        null
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
        const val UTTERANCE_ID = "jalboine-read-aloud"
    }
}
