package com.example.no_dopamine.usage

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class UsageBridge(private val activity: FlutterActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "no_dopamine/usage")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val preferences = activity.getSharedPreferences("usage_preferences", 0)
    private val store = UsageStore(activity.applicationContext)

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "openPermissionSettings") {
                try {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS,
                        Uri.parse("package:${activity.packageName}"))
                    try { activity.startActivity(intent) }
                    catch (_: ActivityNotFoundException) {
                        activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    }
                    result.success(null)
                } catch (_: Exception) {
                    result.error("SETTINGS_UNAVAILABLE", "Não foi possível abrir o acesso de uso.", null)
                }
                return@setMethodCallHandler
            }
            worker.execute {
                try {
                    val value: Any? = when (call.method) {
                        "getState" -> {
                            val apps = installedApps()
                            val ids = apps.map { it["id"] as String }.toSet()
                            mapOf("hasPermission" to hasPermission(), "apps" to apps,
                                "selectedIds" to selected().intersect(ids).toList())
                        }
                        "saveSelection" -> {
                            val packages = call.argument<List<String>>("packages")
                                ?: throw IllegalArgumentException("Seleção inválida.")
                            val allowed = launcherPackages()
                            require(packages.all { it in allowed }) { "Aplicativo indisponível." }
                            check(preferences.edit().putStringSet("selected", packages.toSet()).commit())
                            null
                        }
                        "getUsage", "getHistory" -> {
                            if (!hasPermission()) throw SecurityException("Autorize o acesso de uso no Android.")
                            val user = activity.getSystemService(UserManager::class.java)
                            if (Build.VERSION.SDK_INT >= 24 && !user.isUserUnlocked) {
                                throw IllegalStateException("Desbloqueie o celular para consultar o uso.")
                            }
                            val start = call.argument<Number>("start")?.toLong()
                                ?: throw IllegalArgumentException("Período inválido.")
                            val end = call.argument<Number>("end")?.toLong()
                                ?: throw IllegalArgumentException("Período inválido.")
                            val maxDays = if (call.method == "getHistory") 91L else 8L
                            require(end > start && end - start <= maxDays * 24 * 60 * 60 * 1000)
                            val now = System.currentTimeMillis()
                            val packages = selected().intersect(launcherPackages())
                            sync(packages, now)
                            store.snapshot(packages, start, end, now)
                        }
                        else -> {
                            main.post { result.notImplemented() }
                            return@execute
                        }
                    }
                    main.post { result.success(value) }
                } catch (error: Exception) {
                    val code = if (error is SecurityException) "PERMISSION_DENIED" else "USAGE_ERROR"
                    main.post { result.error(code, error.message ?: "Não foi possível ler o histórico.", null) }
                }
            }
        }
    }

    private fun selected(): Set<String> = preferences.getStringSet("selected", emptySet())!!.toSet()

    @Suppress("DEPRECATION")
    private fun hasPermission(): Boolean {
        val ops = activity.getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), activity.packageName)
        } else ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), activity.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    @Suppress("DEPRECATION")
    private fun launcherPackages(): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return activity.packageManager.queryIntentActivities(intent, 0)
            .map { it.activityInfo.packageName }.filter { it != activity.packageName }.toSet()
    }

    private fun installedApps(): List<Map<String, Any?>> {
        val manager = activity.packageManager
        return launcherPackages().mapNotNull { id ->
            try {
                @Suppress("DEPRECATION")
                val info = manager.getApplicationInfo(id, 0)
                val drawable = manager.getApplicationIcon(info)
                val bitmap = Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888)
                drawable.setBounds(0, 0, 72, 72)
                drawable.draw(Canvas(bitmap))
                val bytes = ByteArrayOutputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    it.toByteArray()
                }
                bitmap.recycle()
                mapOf("id" to id, "name" to manager.getApplicationLabel(info).toString(), "icon" to bytes)
            } catch (_: Exception) { null }
        }.sortedBy { (it["name"] as String).lowercase() }
    }

    private fun sync(packages: Set<String>, now: Long) {
        if (packages.isEmpty()) return
        val manager = activity.getSystemService(UsageStatsManager::class.java)
        // Android only retains a few days of detailed events. Archive what it
        // actually returns, with explicit coverage ranges, for up to 90 days.
        val events = manager.queryEvents(now - 30L * 24 * 60 * 60 * 1000, now)
            ?: throw IllegalStateException("Histórico indisponível. Desbloqueie o celular e tente novamente.")
        val event = UsageEvents.Event()
        val selectedEvents = mutableListOf<StoredEvent>()
        var oldest: Long? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (oldest == null || event.timeStamp < oldest) oldest = event.timeStamp
            when (event.eventType) {
                1, 2, 23 -> if (event.packageName in packages) {
                    selectedEvents.add(StoredEvent(event.timeStamp, event.eventType,
                        event.packageName, event.className ?: ""))
                }
                16, 17, 26, 27 -> selectedEvents.add(StoredEvent(event.timeStamp,
                    event.eventType, "", ""))
            }
        }
        store.sync(selectedEvents, packages, oldest, now)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.execute { store.close() }
        worker.shutdown()
    }
}
