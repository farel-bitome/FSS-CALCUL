package com.fsscalcul

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.Base64
import java.io.ByteArrayOutputStream
import android.os.IBinder
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
import recieptservice.com.recieptservice.PrinterInterface

/**
 * Pont d'impression FSS-CALCUL.
 *
 * Ordre : imprimante intégrée SUNMI (bibliothèque officielle com.sunmi:printerlibrary)
 * ou Senraise H10 (service recieptservice), puis, si elle est absente ou en échec,
 * système d'impression Android.
 */
class MainActivity : FlutterActivity() {
    private val channel = "fss_calcul/printer"

    /** Réponse en attente pour le choix du logo dans la galerie. */
    private var logoEnAttente: MethodChannel.Result? = null
    private val demandeLogo = 4711

    /** Référence gardée pour que la WebView ne soit pas détruite avant la fin de l'impression. */
    private var printWebView: WebView? = null

    private data class TicketData(
        val numero: Int,
        val date: String,
        val devise: String,
        val total: Double,
        val articles: List<Map<*, *>>,
        val societe: Map<*, *>,
        /** Largeur du papier en mm : 58 ou 80. */
        val largeurMm: Int,
        /** Logo de la société (PNG), ou null. */
        val logo: ByteArray?,
    ) {
        /** Largeur imprimable en points (203 dpi) : 384 pour 58 mm, 576 pour 80 mm. */
        val largeurPx: Int get() = if (largeurMm >= 80) 576 else 384
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "deviceInfo" -> result.success(
                        "${Build.MANUFACTURER} ${Build.MODEL} • Android ${Build.VERSION.RELEASE}"
                    )
                    "renderTicket" -> {
                        try {
                            val out = ByteArrayOutputStream()
                            renderTicket(ticketDepuis(call)).compress(Bitmap.CompressFormat.PNG, 100, out)
                            result.success(out.toByteArray())
                        } catch (e: Exception) {
                            result.error("RENDER", e.message, null)
                        }
                    }
                    "printTicket" -> {
                        val t = ticketDepuis(call)
                        if (isSunmiDevice()) {
                            printViaSunmi(t, result)
                        } else if (isSenraiseDevice()) {
                            printViaSenraise(t, result)
                        } else {
                            printViaAndroidFramework(t, result)
                        }
                    }
                    "pickLogo" -> {
                        logoEnAttente?.success(null)
                        logoEnAttente = result
                        try {
                            val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                                type = "image/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                            }
                            startActivityForResult(Intent.createChooser(intent, "Choisir le logo"), demandeLogo)
                        } catch (e: Exception) {
                            logoEnAttente = null
                            result.error("LOGO", "Impossible d'ouvrir la galerie : ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != demandeLogo) return
        val r = logoEnAttente ?: return
        logoEnAttente = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { r.success(null); return }
        try {
            val brut = contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
                ?: throw IllegalStateException("Image illisible.")
            // Logo réduit (max 512 px) : suffisant pour l'écran et pour un ticket 80 mm
            val echelle = minOf(1f, 512f / maxOf(brut.width, brut.height))
            val img = if (echelle < 1f)
                Bitmap.createScaledBitmap(brut, (brut.width * echelle).toInt().coerceAtLeast(1), (brut.height * echelle).toInt().coerceAtLeast(1), true)
            else brut
            val out = ByteArrayOutputStream()
            img.compress(Bitmap.CompressFormat.PNG, 100, out)
            r.success(out.toByteArray())
        } catch (e: Exception) {
            r.error("LOGO", e.message, null)
        }
    }

    private fun ticketDepuis(call: io.flutter.plugin.common.MethodCall) = TicketData(
        numero = call.argument<Number>("ticket")?.toInt() ?: 0,
        date = call.argument<String>("date") ?: "",
        devise = call.argument<String>("devise") ?: "FCFA",
        total = call.argument<Number>("total")?.toDouble() ?: 0.0,
        articles = call.argument<List<Map<*, *>>>("articles") ?: emptyList(),
        societe = call.argument<Map<*, *>>("societe") ?: emptyMap<String, Any>(),
        largeurMm = call.argument<Number>("largeur")?.toInt() ?: 58,
        logo = call.argument<ByteArray>("logo"),
    )

    /** Détection sur le fabricant uniquement : le nom du modèle (V2, T1, S2…) ne suffit pas. */
    private fun isSunmiDevice(): Boolean =
        Build.MANUFACTURER.contains("SUNMI", ignoreCase = true) ||
            Build.BRAND.contains("SUNMI", ignoreCase = true)

    private fun isSenraiseDevice(): Boolean =
        Build.MANUFACTURER.contains("SENRAISE", ignoreCase = true) ||
            Build.BRAND.contains("SENRAISE", ignoreCase = true) ||
            Build.MODEL.uppercase().startsWith("H10")

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

    // ---------- Rendu du ticket en image (58 mm, tout en gras, filigrane) ----------

    private val marge = 6
    private val filigrane = "BITOME-FAREL"

    private fun paint(taille: Float, align: Paint.Align = Paint.Align.LEFT) = Paint().apply {
        isAntiAlias = false          // bords nets pour l'impression thermique
        color = Color.BLACK
        textSize = taille
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        isFakeBoldText = true        // gras renforcé
        textAlign = align
    }

    /** Coupe un texte en lignes qui tiennent dans [largeur] pixels. */
    private fun decouper(texte: String, pt: Paint, largeur: Float): List<String> {
        val lignes = mutableListOf<String>()
        for (para in texte.split('\n')) {
            var courant = ""
            for (mot in para.split(' ')) {
                val essai = if (courant.isEmpty()) mot else "$courant $mot"
                if (pt.measureText(essai) <= largeur) { courant = essai; continue }
                if (courant.isNotEmpty()) lignes.add(courant)
                // mot trop long : coupé caractère par caractère
                var m = mot
                while (pt.measureText(m) > largeur && m.length > 1) {
                    var n = m.length
                    while (n > 1 && pt.measureText(m.substring(0, n)) > largeur) n--
                    lignes.add(m.substring(0, n)); m = m.substring(n)
                }
                courant = m
            }
            lignes.add(courant)
        }
        return lignes
    }

    private sealed class Ligne(val hauteur: Float)
    private class Texte(val s: String, val pt: Paint, h: Float) : Ligne(h)
    private class Colonnes(val gauche: String, val droite: String, val pt: Paint, h: Float) : Ligne(h)
    private class Separateur : Ligne(14f)
    private class Logo(val bmp: Bitmap) : Ligne(bmp.height + 8f)
    /** Une ligne d'article : désignation | quantité | montant, sur la même ligne. */
    private class LigneArticle(
        val designation: String, val qte: String, val montant: String,
        val pt: Paint, h: Float,
    ) : Ligne(h)

    private fun renderTicket(t: TicketData): Bitmap {
        val largeurPx = t.largeurPx
        val utile = (largeurPx - 2 * marge).toFloat()
        val titre = paint(32f, Paint.Align.CENTER)
        val centre = paint(22f, Paint.Align.CENTER)
        val normal = paint(23f)
        val total = paint(30f)
        val lignes = mutableListOf<Ligne>()
        fun ajouter(texte: String, pt: Paint) {
            for (l in decouper(texte, pt, utile)) lignes.add(Texte(l, pt, pt.textSize * 1.25f))
        }

        logoTicket(t, utile)?.let { lignes.add(Logo(it)) }
        val entete = enteteLignes(t)
        ajouter(entete.first(), titre)
        for (l in entete.drop(1)) ajouter(l, centre)
        lignes.add(Separateur())
        ajouter("Ticket #${t.numero}", normal)
        ajouter(t.date, normal)
        lignes.add(Separateur())
        // Colonnes : désignation (reste de la largeur) | Qté | Montant
        val articles = t.articles.map { a ->
            Triple(
                txt(a, "designation"),
                ((a["quantite"] as? Number)?.toInt() ?: 1).toString(),
                fmt((a["sousTotal"] as? Number)?.toDouble() ?: 0.0),
            )
        }
        val entetePt = paint(20f)
        val colQte = maxOf(entetePt.measureText("Qté"), articles.maxOfOrNull { normal.measureText(it.second) } ?: 0f) + 12f
        val colMontant = maxOf(entetePt.measureText("Montant"), articles.maxOfOrNull { normal.measureText(it.third) } ?: 0f) + 6f
        lignes.add(LigneArticle("Article", "Qté", "Montant", entetePt, entetePt.textSize * 1.3f))
        for ((d, q, m) in articles) {
            lignes.add(LigneArticle(d, q, m, normal, normal.textSize * 1.3f))
        }
        lignes.add(Separateur())
        val totalTxt = "${fmt(t.total)} ${t.devise}"
        if (total.measureText("TOTAL $totalTxt") <= utile) {
            lignes.add(Colonnes("TOTAL", totalTxt, total, total.textSize * 1.35f))
        } else {
            ajouter("TOTAL", total); ajouter(totalTxt, total)
        }
        lignes.add(Separateur())
        ajouter(piedTicket(t), centre)

        val hauteur = (lignes.sumOf { it.hauteur.toDouble() } + 2 * marge + 10).toInt()
        val bmp = Bitmap.createBitmap(largeurPx, hauteur, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.WHITE)
        dessinerFiligrane(bmp)

        var y = marge.toFloat()
        val trait = Paint().apply { color = Color.BLACK; strokeWidth = 3f }
        for (l in lignes) {
            when (l) {
                is Texte -> {
                    val x = if (l.pt.textAlign == Paint.Align.CENTER) largeurPx / 2f else marge.toFloat()
                    c.drawText(l.s, x, y + l.pt.textSize, l.pt)
                }
                is Colonnes -> {
                    c.drawText(l.gauche, marge.toFloat(), y + l.pt.textSize, l.pt)
                    val d = Paint(l.pt).apply { textAlign = Paint.Align.RIGHT }
                    c.drawText(l.droite, (largeurPx - marge).toFloat(), y + l.pt.textSize, d)
                }
                is Logo -> c.drawBitmap(l.bmp, (largeurPx - l.bmp.width) / 2f, y, null)
                is LigneArticle -> {
                    val base = y + l.pt.textSize
                    val xMontant = (largeurPx - marge).toFloat()
                    val xQte = xMontant - colMontant - colQte / 2
                    val placeDesignation = xMontant - colMontant - colQte - marge - 4f
                    // la désignation est réduite puis, si besoin, raccourcie avec « … » pour tenir sur la ligne
                    val pd = Paint(l.pt)
                    while (pd.measureText(l.designation) > placeDesignation && pd.textSize > 17f) pd.textSize -= 1f
                    var d = l.designation
                    if (pd.measureText(d) > placeDesignation) {
                        while (d.isNotEmpty() && pd.measureText("$d…") > placeDesignation) d = d.dropLast(1)
                        d = "$d…"
                    }
                    c.drawText(d, marge.toFloat(), base, pd)
                    c.drawText(l.qte, xQte, base, Paint(l.pt).apply { textAlign = Paint.Align.CENTER })
                    c.drawText(l.montant, xMontant, base, Paint(l.pt).apply { textAlign = Paint.Align.RIGHT })
                }
                is Separateur -> {
                    val ym = y + l.hauteur / 2
                    var x = marge.toFloat()
                    while (x < largeurPx - marge) { c.drawLine(x, ym, minOf(x + 8f, (largeurPx - marge).toFloat()), ym, trait); x += 14f }
                }
            }
            y += l.hauteur
        }
        return bmp
    }

    /**
     * Logo de la société converti en noir et blanc tramé (Floyd-Steinberg),
     * seul rendu fiable sur une imprimante thermique. Hauteur max 140 points.
     */
    private fun logoTicket(t: TicketData, largeurMax: Float): Bitmap? {
        val octets = t.logo ?: return null
        val src = try { BitmapFactory.decodeByteArray(octets, 0, octets.size) } catch (_: Exception) { null } ?: return null
        val echelle = minOf(largeurMax * 0.7f / src.width, 140f / src.height, 1f)
        val w = (src.width * echelle).toInt().coerceAtLeast(1)
        val h = (src.height * echelle).toInt().coerceAtLeast(1)
        val img = Bitmap.createScaledBitmap(src, w, h, true)
        val px = IntArray(w * h)
        img.getPixels(px, 0, w, 0, 0, w, h)
        // niveaux de gris (transparence = blanc)
        val gris = FloatArray(w * h) { i ->
            val p = px[i]; val a = Color.alpha(p) / 255f
            val g = 0.299f * Color.red(p) + 0.587f * Color.green(p) + 0.114f * Color.blue(p)
            g * a + 255f * (1 - a)
        }
        val out = IntArray(w * h)
        for (y in 0 until h) for (x in 0 until w) {
            val i = y * w + x
            val nouveau = if (gris[i] < 128f) 0f else 255f
            val err = gris[i] - nouveau
            out[i] = if (nouveau == 0f) Color.BLACK else Color.WHITE
            if (x + 1 < w) gris[i + 1] += err * 7 / 16
            if (y + 1 < h) {
                if (x > 0) gris[i + w - 1] += err * 3 / 16
                gris[i + w] += err * 5 / 16
                if (x + 1 < w) gris[i + w + 1] += err * 1 / 16
            }
        }
        return Bitmap.createBitmap(out, w, h, Bitmap.Config.ARGB_8888)
    }

    /**
     * Filigrane « BITOME-FAREL » en diagonale, répété sur toute la hauteur.
     * Une imprimante thermique n'imprime que du noir : le gris est obtenu par
     * une trame de points espacés, qui reste lisible sous le texte.
     */
    private fun dessinerFiligrane(bmp: Bitmap) {
        val w = bmp.width; val h = bmp.height
        val masque = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(masque)
        val pt = paint(36f, Paint.Align.CENTER)
        val pas = 200f
        var cy = pas / 2
        while (cy < h + pas / 2) {
            c.save()
            c.rotate(-30f, w / 2f, cy)
            c.drawText(filigrane, w / 2f, cy + pt.textSize / 3, pt)
            c.restore()
            cy += pas
        }
        val px = IntArray(w * h)
        masque.getPixels(px, 0, w, 0, 0, w, h)
        val out = IntArray(w * h) { Color.WHITE }
        for (y in 0 until h) for (x in 0 until w) {
            val i = y * w + x
            // trame : 1 point sur 3 en quinconce
            if (Color.alpha(px[i]) > 128 && (x + 2 * y) % 3 == 0) out[i] = Color.BLACK
        }
        bmp.setPixels(out, 0, w, 0, 0, w, h)
        masque.recycle()
    }

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
        p.printerInit(null)
        p.setAlignment(1, null)
        p.printBitmap(renderTicket(t), null)
        p.lineWrap(4, null)
    }

    // ---------- Senraise H10 / H10C / H10S / H10P ----------

    private fun printViaSenraise(t: TicketData, result: MethodChannel.Result) {
        var repondu = false
        fun repondre(action: () -> Unit) {
            if (!repondu) { repondu = true; action() }
        }

        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                try {
                    val p = PrinterInterface.Stub.asInterface(binder)
                        ?: throw IllegalStateException("Service Senraise indisponible.")
                    imprimerSenraise(p, t)
                    repondre { result.success("Ticket imprimé sur l'imprimante Senraise.") }
                } catch (e: Exception) {
                    repondre { printViaAndroidFramework(t, result) }
                } finally {
                    try { unbindService(this) } catch (_: Exception) {}
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {}
        }

        val intent = Intent().apply {
            setClassName(
                "recieptservice.com.recieptservice",
                "recieptservice.com.recieptservice.service.PrinterService"
            )
        }
        try {
            val ok = bindService(intent, connection, Context.BIND_AUTO_CREATE)
            if (!ok) repondre { printViaAndroidFramework(t, result) }
        } catch (e: Exception) {
            repondre { printViaAndroidFramework(t, result) }
        }
    }

    private fun imprimerSenraise(p: PrinterInterface, t: TicketData) {
        p.setAlignment(1)
        p.printBitmap(renderTicket(t))
        p.nextLine(4)
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
                                .setMediaSize(
                                    if (t.largeurMm >= 80) PrintAttributes.MediaSize("FSS80", "Ticket 80 mm", 3150, 11690)
                                    else PrintAttributes.MediaSize("FSS58", "Ticket 58 mm", 2283, 11690)
                                )
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

    private fun buildHtml(t: TicketData): String {
        val out = ByteArrayOutputStream()
        renderTicket(t).compress(Bitmap.CompressFormat.PNG, 100, out)
        val b64 = Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        return """<html><head><meta charset="utf-8"><style>
            @page{size:${t.largeurMm}mm auto;margin:0}body{margin:0;padding:0}
            img{display:block;width:${if (t.largeurMm >= 80) 72 else 48}mm;margin:2mm auto;image-rendering:pixelated}
            </style></head><body><img src="data:image/png;base64,$b64"></body></html>"""
    }
}
