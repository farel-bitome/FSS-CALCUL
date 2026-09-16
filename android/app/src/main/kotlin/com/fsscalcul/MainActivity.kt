package com.fsscalcul

import android.content.Context
import android.os.Build
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import woyou.aidlservice.jiuiv5.IWoyouService
import woyou.aidlservice.jiuiv5.IWoyouService.Stub
import woyou.aidlservice.jiuiv5.IWoyouService
import woyou.aidlservice.jiuiv5.IWoyouService
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder

class MainActivity : FlutterActivity() {
    private val channel = "fss_calcul/printer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> {
                        result.success("${Build.MANUFACTURER} ${Build.MODEL} • Android ${Build.VERSION.RELEASE}")
                    }
                    "printTicket" -> {
                        val items = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                        val ticket = call.argument<Int>("ticket") ?: 0
                        val total = (call.argument<Number>("total") ?: 0).toDouble()
                        if (isSunmiDevice()) {
                            printViaSunmi(items, ticket, total, result)
                        } else {
                            printViaAndroidFramework(items, ticket, total, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isSunmiDevice(): Boolean =
        Build.MANUFACTURER.contains("SUNMI", ignoreCase = true) ||
        Build.BRAND.contains("SUNMI", ignoreCase = true) ||
        Build.MODEL.contains("V1", ignoreCase = true) ||
        Build.MODEL.contains("V2", ignoreCase = true) ||
        Build.MODEL.contains("V3", ignoreCase = true) ||
        Build.MODEL.contains("P1", ignoreCase = true) ||
        Build.MODEL.contains("T1", ignoreCase = true) ||
        Build.MODEL.contains("T2", ignoreCase = true) ||
        Build.MODEL.contains("D2", ignoreCase = true) ||
        Build.MODEL.contains("S2", ignoreCase = true)

    private fun printViaSunmi(
        items: List<Map<String, Any>>, ticket: Int, total: Double,
        result: MethodChannel.Result
    ) {
        val intent = Intent().apply {
            setPackage("woyou.aidlservice.jiuiv5")
            action = "woyou.aidlservice.jiuiv5.IWoyouService"
        }
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                try {
                    val service = IWoyouService.Stub.asInterface(binder)
                    service.setAlignment(1, null)
                    service.printText("FSS-CALCUL\\n", null)
                    service.printText("BITOME MEYEH\\n", null)
                    service.setAlignment(0, null)
                    service.printText("Ticket #$ticket\\n", null)
                    service.printText("------------------------------\\n", null)
                    for (x in items) {
                        if (x["type"] == "article") {
                            val d = (x["designation"] ?: "").toString()
                            val q = (x["quantite"] as? Number)?.toInt() ?: 1
                            val st = (x["sousTotal"] as? Number)?.toDouble() ?: 0.0
                            val pu = if (q == 0) 0.0 else st / q
                            service.printText("$d\\n$q x ${"%.0f".format(pu)} = ${"%.0f".format(st)} FCFA\\n", null)
                        }
                    }
                    service.printText("------------------------------\\n", null)
                    service.setAlignment(2, null)
                    service.printText("TOTAL: ${"%.0f".format(total)} FCFA\\n\\n", null)
                    service.setAlignment(1, null)
                    service.printText("Merci pour votre confiance\\n\\n\\n", null)
                    unbindService(this)
                    result.success("Ticket imprimé directement sur l'imprimante SUNMI.")
                } catch (e: Exception) {
                    try { unbindService(this) } catch (_: Exception) {}
                    result.error("SUNMI_PRINT", e.message, null)
                }
            }
            override fun onServiceDisconnected(name: ComponentName?) {}
        }
        try {
            val ok = bindService(intent, connection, Context.BIND_AUTO_CREATE)
            if (!ok) result.error("SUNMI_BIND", "Service d'impression SUNMI indisponible.", null)
        } catch (e: Exception) {
            result.error("SUNMI_BIND", e.message, null)
        }
    }

    private fun printViaAndroidFramework(
        items: List<Map<String, Any>>, ticket: Int, total: Double,
        result: MethodChannel.Result
    ) {
        val web = WebView(this)
        web.settings.javaScriptEnabled = false
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                val pm = getSystemService(Context.PRINT_SERVICE) as PrintManager
                val adapter = web.createPrintDocumentAdapter("FSS-CALCUL-Ticket-$ticket")
                pm.print(
                    "FSS-CALCUL #$ticket",
                    adapter,
                    PrintAttributes.Builder()
                        .setMediaSize(PrintAttributes.MediaSize.NA_INDEX_3X5)
                        .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                        .build()
                )
                result.success("Ticket envoyé au système d’impression Android.")
            }
        }
        web.loadDataWithBaseURL(null, buildHtml(items, ticket, total), "text/html", "UTF-8", null)
    }

    private fun buildHtml(items: List<Map<String, Any>>, ticket: Int, total: Double): String {
        val sb = StringBuilder()
        sb.append("""<html><head><meta name="viewport" content="width=58mm"><style>
        @page{size:58mm auto;margin:0}body{width:54mm;margin:2mm auto;font-family:monospace;
        font-size:11px;color:#000}h2{text-align:center;margin:0 0 2mm}p{margin:1mm 0}
        .c{text-align:center}.r{text-align:right}.line{border-top:1px dashed #000;margin:2mm 0}
        .total{font-size:16px;font-weight:bold}</style></head><body>""")
        sb.append("<h2>FSS-CALCUL</h2><p class='c'>BITOME MEYEH</p>")
        sb.append("<p>Ticket #$ticket</p><div class='line'></div>")
        for (x in items) {
            if (x["type"] == "article") {
                val d = (x["designation"] ?: "").toString().replace("&","&amp;").replace("<","&lt;")
                val q = x["quantite"] ?: 1
                val st = (x["sousTotal"] as? Number)?.toDouble() ?: 0.0
                sb.append("<p>$d</p><p>$q x ${"%.0f".format(st / (q as Int))} = ${"%.0f".format(st)} FCFA</p>")
            }
        }
        sb.append("<div class='line'></div><p class='total'>TOTAL: ${"%.0f".format(total)} FCFA</p>")
        sb.append("<p class='c'>Merci pour votre confiance</p></body></html>")
        return sb.toString()
    }
}
