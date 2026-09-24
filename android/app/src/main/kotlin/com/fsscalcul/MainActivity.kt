package com.fsscalcul

import android.content.Context
import android.os.Build
import android.print.PrintAttributes
import android.print.PrintManager
import android.webkit.WebView
import android.webkit.WebViewClient
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.SunmiPrinterService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Pont d'impression FSS-CALCUL.
 *
 * Ordre : imprimante intégrée SUNMI (bibliothèque officielle com.sunmi:printerlibrary)
 * puis, si elle est absente ou en échec, système d'impression Android.
 * Les terminaux Senraise H10 sont gérés côté Dart (plugin senraise_printer).
 */
class MainActivity : FlutterActivity() {
    private val channel = "fss_calcul/printer"

    /** Référence gardée pour que la WebView ne soit pas détruite avant la fin de l'impression. */
    private var printWebView: WebView? = null

    private data class TicketData(
        val numero: Int,
        val date: String,
        val devise: String,
        val total: Double,
        val articles: List<Map<*, *>>,
        val societe: Map<*, *>,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> result.success(
                        "${Build.MANUFACTURER} ${Build.MODEL} • Android ${Build.VERSION.RELEASE}"
                    )
                    "printTicket" -> {
                        val t = TicketData(
                            numero = call.argument<Number>("ticket")?.toInt() ?: 0,
                            date = call.argument<String>("date") ?: "",
                            devise = call.argument<String>("devise") ?: "FCFA",
                            total = call.argument<Number>("total")?.toDouble() ?: 0.0,
                            articles = call.argument<List<Map<*, *>>>("articles") ?: emptyList(),
                            societe = call.argument<Map<*, *>>("societe") ?: emptyMap<String, Any>(),
                        )
                        if (isSunmiDevice()) {
                            printViaSunmi(t, result)
                        } else {
                            printViaAndroidFramework(t, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Détection sur le fabricant uniquement : le nom du modèle (V2, T1, S2…) ne suffit pas. */
    private fun isSunmiDevice(): Boolean =
        Build.MANUFACTURER.contains("SUNMI", ignoreCase = true) ||
            Build.BRAND.contains("SUNMI", ignoreCase = true)

    // ---------- Contenu du ticket (commun aux deux méthodes) ----------

    private fun fmt(n: Double): String = String.format(java.util.Locale.US, "%,.0f", n).replace(',', ' ')

    private fun txt(m: Map<*, *>, key: String): String = (m[key] ?: "").toString().trim()

    private fun enteteLignes(t: TicketData): List<String> {
        val s = t.societe
        val nom = txt(s, "nom").ifEmpty { "FSS-CALCUL" }
        val lignes = mutableListOf(nom)
        for (k in listOf("adresse", "telephone", "email", "siteWeb")) {
            txt(s, k).takeIf { it.isNotEmpty() }?.let { lignes.add(it) }
        }
        txt(s, "identifiantFiscal").takeIf { it.isNotEmpty() }?.let { lignes.add("NIF : $it") }
        txt(s, "registreCommerce").takeIf { it.isNotEmpty() }?.let { lignes.add("RCCM : $it") }
        return lignes
    }

    private fun piedTicket(t: TicketData): String =
        txt(t.societe, "piedTicket").ifEmpty { "Merci pour votre confiance" }

    // ---------- SUNMI ----------

    private fun printViaSunmi(t: TicketData, result: MethodChannel.Result) {
        var repondu = false
        fun repondre(action: () -> Unit) {
            if (!repondu) { repondu = true; action() }
        }

        val callback = object : InnerPrinterCallback() {
            override fun onConnected(service: SunmiPrinterService) {
                try {
                    if (!InnerPrinterManager.getInstance().hasPrinter(service)) {
                        throw IllegalStateException("Aucune imprimante intégrée sur ce terminal SUNMI.")
                    }
                    imprimerSunmi(service, t)
                    repondre { result.success("Ticket imprimé sur l'imprimante SUNMI.") }
                } catch (e: Exception) {
                    // Échec SUNMI : on bascule sur l'impression Android
                    repondre { printViaAndroidFramework(t, result) }
                } finally {
                    try { InnerPrinterManager.getInstance().unBindService(this@MainActivity, this) } catch (_: Exception) {}
                }
            }

            override fun onDisconnected() {}
        }

        try {
            val ok = InnerPrinterManager.getInstance().bindService(this, callback)
            if (!ok) repondre { printViaAndroidFramework(t, result) }
        } catch (e: Exception) {
            repondre { printViaAndroidFramework(t, result) }
        }
    }

    private fun imprimerSunmi(p: SunmiPrinterService, t: TicketData) {
        val sep = "--------------------------------\n" // 32 caractères = largeur 58 mm
        p.printerInit(null)

        val entete = enteteLignes(t)
        p.setAlignment(1, null)
        p.printTextWithFont("${entete.first()}\n", null, 30f, null)
        for (l in entete.drop(1)) p.printTextWithFont("$l\n", null, 22f, null)

        p.setAlignment(0, null)
        p.printTextWithFont("Ticket #${t.numero}\n${t.date}\n$sep", null, 24f, null)
        for (a in t.articles) {
            val q = (a["quantite"] as? Number)?.toInt() ?: 1
            val pu = (a["prix"] as? Number)?.toDouble() ?: 0.0
            val st = (a["sousTotal"] as? Number)?.toDouble() ?: 0.0
            p.printTextWithFont("${txt(a, "designation")}\n", null, 24f, null)
            p.printTextWithFont("  $q x ${fmt(pu)} = ${fmt(st)} ${t.devise}\n", null, 24f, null)
        }
        p.printTextWithFont(sep, null, 24f, null)

        p.setAlignment(2, null)
        p.printTextWithFont("TOTAL : ${fmt(t.total)} ${t.devise}\n", null, 30f, null)
        p.setAlignment(1, null)
        p.printTextWithFont("\n${piedTicket(t)}\n", null, 22f, null)
        p.lineWrap(3, null)
    }

    // ---------- Impression Android (secours) ----------

    private fun printViaAndroidFramework(t: TicketData, result: MethodChannel.Result) {
        try {
            val web = WebView(this)
            printWebView = web
            web.settings.javaScriptEnabled = false
            web.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView?, url: String?) {
                    try {
                        val pm = getSystemService(Context.PRINT_SERVICE) as PrintManager
                        val adapter = web.createPrintDocumentAdapter("FSS-CALCUL-Ticket-${t.numero}")
                        pm.print(
                            "FSS-CALCUL #${t.numero}",
                            adapter,
                            PrintAttributes.Builder()
                                .setMediaSize(PrintAttributes.MediaSize("FSS58", "Ticket 58 mm", 2283, 11690))
                                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                                .build()
                        )
                        result.success("Ticket envoyé au système d'impression Android.")
                    } catch (e: Exception) {
                        result.error("ANDROID_PRINT", e.message, null)
                    }
                }
            }
            web.loadDataWithBaseURL(null, buildHtml(t), "text/html", "UTF-8", null)
        } catch (e: Exception) {
            result.error("ANDROID_PRINT", e.message, null)
        }
    }

    private fun esc(s: String) =
        s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    private fun buildHtml(t: TicketData): String {
        val sb = StringBuilder()
        sb.append(
            """<html><head><meta charset="utf-8"><style>
            @page{size:58mm auto;margin:0}body{width:54mm;margin:2mm auto;font-family:monospace;
            font-size:11px;color:#000}h2{text-align:center;margin:0 0 1mm}p{margin:1mm 0}
            .c{text-align:center}.r{text-align:right}.line{border-top:1px dashed #000;margin:2mm 0}
            .total{font-size:15px;font-weight:bold;text-align:right}</style></head><body>"""
        )
        val entete = enteteLignes(t)
        sb.append("<h2>${esc(entete.first())}</h2>")
        for (l in entete.drop(1)) sb.append("<p class='c'>${esc(l)}</p>")
        sb.append("<div class='line'></div><p>Ticket #${t.numero}</p><p>${esc(t.date)}</p><div class='line'></div>")
        for (a in t.articles) {
            val q = (a["quantite"] as? Number)?.toInt() ?: 1
            val pu = (a["prix"] as? Number)?.toDouble() ?: 0.0
            val st = (a["sousTotal"] as? Number)?.toDouble() ?: 0.0
            sb.append("<p>${esc(txt(a, "designation"))}</p>")
            sb.append("<p class='r'>$q x ${fmt(pu)} = ${fmt(st)} ${esc(t.devise)}</p>")
        }
        sb.append("<div class='line'></div><p class='total'>TOTAL : ${fmt(t.total)} ${esc(t.devise)}</p>")
        sb.append("<p class='c'>${esc(piedTicket(t))}</p></body></html>")
        return sb.toString()
    }
}
