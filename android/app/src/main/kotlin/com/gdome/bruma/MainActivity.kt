package com.gdome.bruma

import android.content.ComponentName
import android.content.pm.PackageManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity è richiesto da local_auth (prompt biometrico).
class MainActivity : FlutterFragmentActivity() {
    private val secureChannel = "bruma/secure_screen"
    private val iconChannel = "bruma/app_icon"

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
