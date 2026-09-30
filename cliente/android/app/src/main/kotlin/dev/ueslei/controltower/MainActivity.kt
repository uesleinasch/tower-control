package dev.ueslei.controltower

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var canal: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "control_tower/pareamento").apply {
            setMethodCallHandler { chamada, resposta ->
                if (chamada.method == "pendente") {
                    resposta.success(tirarServidores(intent))
                } else {
                    resposta.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        tirarServidores(intent)?.let { canal?.invokeMethod("servidores", it) }
    }

    private fun tirarServidores(intent: Intent?): String? {
        val servidores = intent?.getStringExtra("servidores") ?: return null
        intent.removeExtra("servidores")
        return servidores
    }
}
