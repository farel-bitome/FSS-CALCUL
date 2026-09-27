// FSS-PVIT — client du relais FSS-PAY pour Flutter (FSS-CALCUL)
// FALLSERVICES&SOLUTIONS INFO — Farel Bitome
//
// Aucune dépendance externe : utilise dart:io.
// La clé secrète PVIT reste sur le relais ; l'appli n'a que la clé du terminal.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Statuts renvoyés par le relais.
class PvitStatut {
  static const pending = 'PENDING';
  static const success = 'SUCCESS';
  static const failed = 'FAILED';
  static const ambiguous = 'AMBIGUOUS';
  static const annule = 'ANNULE';
}

class PvitPaiement {
  final String reference;
  final String? transactionId;
  final String statut;
  final int montant;
  final double? frais;
  final String telephone;
  final String operateur;
  final String? message;
  final String? ticket;

  PvitPaiement({
    required this.reference,
    required this.transactionId,
    required this.statut,
    required this.montant,
    required this.frais,
    required this.telephone,
    required this.operateur,
    required this.message,
    required this.ticket,
  });

  bool get paye => statut == PvitStatut.success;
  bool get final_ => statut == PvitStatut.success || statut == PvitStatut.failed;

  factory PvitPaiement.fromJson(Map<String, dynamic> j) => PvitPaiement(
        reference: j['reference']?.toString() ?? '',
        transactionId: j['transactionId']?.toString(),
        statut: j['statut']?.toString() ?? PvitStatut.pending,
        montant: (j['montant'] as num?)?.round() ?? 0,
        frais: (j['frais'] as num?)?.toDouble(),
        telephone: j['telephone']?.toString() ?? '',
        operateur: j['operateur']?.toString() ?? '',
        message: j['message']?.toString(),
        ticket: j['ticket']?.toString(),
      );

  /// Lignes à imprimer sur le ticket.
  List<String> lignesTicket() => [
        'Paiement : ${FssPvit.nomOperateur(operateur)}',
        'Téléphone : ${FssPvit.telMasque(telephone)}',
        'Réf. PVIT : ${transactionId ?? '-'}',
        'Réf. FSS : $reference',
      ];
}

class PvitErreur implements Exception {
  final String message;
  final int? http;
  final bool reseau;
  PvitErreur(this.message, {this.http, this.reseau = false});
  @override
  String toString() => message;
}

class FssPvit {
  String relais;
  String cle;
  final Duration timeout;

  FssPvit({required String relais, required this.cle, this.timeout = const Duration(seconds: 30)})
      : relais = relais.replaceAll(RegExp(r'/+$'), '');

  bool get estConfigure => relais.isNotEmpty && cle.isNotEmpty;

  // ------------------------------------------------------------ utilitaires
  static String normaliserTelephone(String brut) {
    var t = brut.replaceAll(RegExp(r'[^\d+]'), '').replaceFirst(RegExp(r'^\+'), '').replaceFirst(RegExp(r'^00'), '');
    if (t.startsWith('241') && (t.length == 12 || t.length == 11)) t = t.substring(3);
    if (t.length == 8 && RegExp(r'^[67]').hasMatch(t)) t = '0$t';
    return t;
  }

  static bool telephoneValide(String t) => RegExp(r'^0[67]\d{7}$').hasMatch(t);

  /// Airtel = 07x xx xx xx, Moov = 06x xx xx xx
  static String? detecterOperateur(String t) {
    if (RegExp(r'^07\d{7}$').hasMatch(t)) return 'airtel';
    if (RegExp(r'^06\d{7}$').hasMatch(t)) return 'moov';
    return null;
  }

  static String nomOperateur(String op) =>
      const {'airtel': 'Airtel Money', 'moov': 'Moov Money', 'gimac': 'QR GIMAC'}[op] ?? 'Mobile Money';

  static String telLisible(String t) => t.length == 9
      ? '${t.substring(0, 3)} ${t.substring(3, 5)} ${t.substring(5, 7)} ${t.substring(7)}'
      : t;

  static String telMasque(String t) => t.length == 9 ? '${t.substring(0, 3)} ** ** ${t.substring(7)}' : t;

  static String fcfa(num n) {
    final s = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }

  // ------------------------------------------------------------------- HTTP
  Future<Map<String, dynamic>> _requete(String methode, String chemin, [Map<String, dynamic>? corps]) async {
    if (!estConfigure) {
      throw PvitErreur('Paiement Mobile Money non configuré (adresse du relais et clé du terminal).');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(methode, Uri.parse('$relais/api$chemin')).timeout(timeout);
      req.headers.set('X-FSS-Cle', cle);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (corps != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(corps)));
      }
      final rep = await req.close().timeout(timeout);
      final texte = await rep.transform(utf8.decoder).join().timeout(timeout);
      Map<String, dynamic> json = {};
      try {
        final d = jsonDecode(texte);
        if (d is Map<String, dynamic>) json = d;
      } catch (_) {}
      if (rep.statusCode >= 400 && json['paiement'] == null) {
        throw PvitErreur(json['erreur']?.toString() ?? 'Erreur ${rep.statusCode}', http: rep.statusCode);
      }
      return json;
    } on PvitErreur {
      rethrow;
    } on SocketException {
      throw PvitErreur('Pas de connexion Internet ou relais FSS-PAY injoignable.', reseau: true);
    } on TimeoutException {
      throw PvitErreur('Le relais FSS-PAY ne répond pas (délai dépassé).', reseau: true);
    } on HandshakeException {
      throw PvitErreur('Erreur de connexion sécurisée (HTTPS) avec le relais.', reseau: true);
    } finally {
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------------- API
  Future<bool> tester() async {
    final r = await _requete('GET', '/paiements');
    return r['ok'] == true;
  }

  /// Nom du titulaire (KYC). Renvoie null si PVIT ne le communique pas.
  Future<String?> kyc(String telephone, {String? operateur}) async {
    final q = 'telephone=${Uri.encodeQueryComponent(telephone)}${operateur != null ? '&operateur=$operateur' : ''}';
    final r = await _requete('GET', '/kyc?$q');
    return r['nom']?.toString();
  }

  /// Frais PVIT : {frais, total, payePar}
  Future<Map<String, dynamic>> frais(int montant, String operateur) =>
      _requete('GET', '/frais?montant=$montant&operateur=$operateur');

  Future<PvitPaiement> initier({
    required int montant,
    required String telephone,
    String? operateur,
    String? ticket,
    String? libelle,
    String? caissier,
  }) async {
    final r = await _requete('POST', '/paiements', {
      'montant': montant,
      'telephone': telephone,
      if (operateur != null) 'operateur': operateur,
      if (ticket != null) 'ticket': ticket,
      if (libelle != null) 'libelle': libelle,
      if (caissier != null) 'caissier': caissier,
    });
    return PvitPaiement.fromJson(Map<String, dynamic>.from(r['paiement'] as Map));
  }

  Future<PvitPaiement> suivre(String reference, {bool verifier = false}) async {
    final r = await _requete('GET', '/paiements/${Uri.encodeComponent(reference)}${verifier ? '?verifier=1' : ''}');
    return PvitPaiement.fromJson(Map<String, dynamic>.from(r['paiement'] as Map));
  }

  /// Attend le statut définitif (SUCCESS / FAILED) ou la fin du délai.
  /// [surProgression] est appelé à chaque interrogation (secondes écoulées).
  Stream<PvitPaiement> attendreConfirmation(
    PvitPaiement p, {
    Duration delaiMax = const Duration(minutes: 3),
    Duration intervalle = const Duration(seconds: 3),
  }) async* {
    final debut = DateTime.now();
    var courant = p;
    while (true) {
      final ecoule = DateTime.now().difference(debut);
      try {
        // Au-delà d'une minute, on demande au relais d'interroger PVIT (API Check Status)
        courant = await suivre(p.reference, verifier: ecoule.inSeconds > 60 && ecoule.inSeconds % 15 < 3);
      } on PvitErreur catch (e) {
        if (!e.reseau) rethrow; // coupure passagère : on continue
      }
      yield courant;
      if (courant.final_ || ecoule >= delaiMax) return;
      await Future<void>.delayed(intervalle);
    }
  }

  /// Historique d'une journée (format AAAA-MM-JJ) : {nombre, totalEncaisse, paiements}
  Future<Map<String, dynamic>> historique({String? du, String? au}) =>
      _requete('GET', '/paiements?du=${du ?? ''}&au=${au ?? du ?? ''}');
}
