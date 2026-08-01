package com.gdome.bruma

import android.Manifest
import android.content.ComponentName
import android.content.ContentUris
import android.content.pm.PackageManager
import android.provider.CalendarContract
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity è richiesto da local_auth (prompt biometrico).
class MainActivity : FlutterFragmentActivity() {
    private val secureChannel = "bruma/secure_screen"
    private val iconChannel = "bruma/app_icon"

    // Calendario in SOLA LETTURA per la maschera "Calendario". Implementato qui
    // invece che col plugin device_calendar perché quello pretende ANCHE
    // WRITE_CALENDAR per considerare i permessi concessi (arePermissionsGranted
    // = write && read), quindi con la sola lettura risponderebbe sempre
    // "negato". Qui chiediamo e usiamo esclusivamente READ_CALENDAR.
    private val calendarChannel = "bruma/calendar"
    private val calendarPermRequest = 8123
    private var pendingCalendarPermission: MethodChannel.Result? = null

    // Activity-alias definite nel manifest (short name, senza package).
    private val aliases = listOf(
        "BrumaDefault", "MaskCalc", "MaskMeteo", "MaskNote", "MaskPromemoria"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "secureOn" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    "secureOff" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, iconChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlias" -> {
                        val target = call.argument<String>("alias")
                        if (target == null || !aliases.contains(target)) {
                            result.error("bad_alias", "alias non valido", null)
                        } else {
                            setAlias(target)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, calendarChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasCalendarPermission())
                    "requestPermission" -> {
                        if (hasCalendarPermission()) {
                            result.success(true)
                        } else {
                            pendingCalendarPermission = result
                            requestPermissions(
                                arrayOf(Manifest.permission.READ_CALENDAR),
                                calendarPermRequest,
                            )
                        }
                    }
                    "readEvents" -> {
                        val from = (call.argument<Number>("from"))?.toLong() ?: 0L
                        val to = (call.argument<Number>("to"))?.toLong() ?: 0L
                        result.success(readEvents(from, to))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasCalendarPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_CALENDAR) ==
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != calendarPermRequest) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingCalendarPermission?.success(granted)
        pendingCalendarPermission = null
    }

    // Legge le occorrenze fra due istanti (epoch ms). Instances (non Events)
    // espande correttamente gli eventi ricorrenti. Nessuna scrittura.
    private fun readEvents(fromMs: Long, toMs: Long): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        if (!hasCalendarPermission()) return out
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, fromMs)
        ContentUris.appendId(builder, toMs)
        val projection = arrayOf(
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
        )
        try {
            contentResolver.query(
                builder.build(),
                projection,
                null,
                null,
                "${CalendarContract.Instances.BEGIN} ASC",
            )?.use { c ->
                while (c.moveToNext()) {
                    val title = c.getString(0) ?: continue
                    if (title.isBlank()) continue
                    out.add(mapOf("title" to title, "begin" to c.getLong(1)))
                }
            }
        } catch (_: Exception) {
            // La maschera non deve mai rompersi per il calendario.
        }
        return out
    }

    // Abilita l'alias scelto e disabilita gli altri (mai zero abilitati: prima
    // abilita il target, poi disabilita il resto). DONT_KILL_APP per non
    // uccidere subito il processo.
    private fun setAlias(target: String) {
        val pm = packageManager
        val pkg = packageName
        pm.setComponentEnabledSetting(
            ComponentName(pkg, "$pkg.$target"),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for (a in aliases) {
            if (a == target) continue
            pm.setComponentEnabledSetting(
                ComponentName(pkg, "$pkg.$a"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }
}
