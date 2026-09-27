// FSS-PVIT — fenêtre « Paiement Mobile Money » pour Flutter (FSS-CALCUL)
//
// Utilisation :
//   final r = await FssPvitDialog.afficher(context,
//       service: FssPvit(relais: 'https://pay.mondomaine.com', cle: 'CLE_TERMINAL'),
//       montant: 12500, ticket: 'T-0042', caissier: 'Marie');
//   if (r.paye) { /* valider la vente, imprimer r.paiement!.lignesTicket() */ }

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fss_pvit_service.dart';

class PvitResultat {
  final bool paye;
  final String statut;
  final PvitPaiement? paiement;
  const PvitResultat(this.paye, this.statut, this.paiement);
}

enum _Etape { saisie, envoi, attente, quitter, resultat }

class FssPvitDialog extends StatefulWidget {
  final FssPvit service;
  final int montant;
  final String? ticket;
  final String? libelle;
  final String? caissier;
  final String? telephone;

  const FssPvitDialog({
    super.key,
    required this.service,
    required this.montant,
    this.ticket,
    this.libelle,
    this.caissier,
    this.telephone,
  });

  static Future<PvitResultat> afficher(
    BuildContext context, {
    required FssPvit service,
    required int montant,
    String? ticket,
    String? libelle,
    String? caissier,
    String? telephone,
  }) async {
    final r = await showDialog<PvitResultat>(
      context: context,
      barrierDismissible: false,
      builder: (_) => FssPvitDialog(
        service: service,
        montant: montant,
        ticket: ticket,
        libelle: libelle,
        caissier: caissier,
        telephone: telephone,
      ),
    );
    return r ?? const PvitResultat(false, PvitStatut.annule, null);
  }

  @override
  State<FssPvitDialog> createState() => _FssPvitDialogState();
}

class _FssPvitDialogState extends State<FssPvitDialog> {
  static const _vert = Color(0xFF1F7A3A);
  static const _rougeAirtel = Color(0xFFE40000);
  static const _bleuMoov = Color(0xFF0055A5);

  final _tel = TextEditingController();
  _Etape _etape = _Etape.saisie;
  String? _operateur;
  String? _info;
  bool _infoErreur = false;
  String? _fraisTexte;
  String? _erreurEnvoi;
  PvitPaiement? _paiement;
  StreamSubscription<PvitPaiement>? _suivi;
  int _jetonKyc = 0;
  DateTime? _debutAttente;
  Timer? _chrono;

  @override
  void initState() {
    super.initState();
    if (widget.telephone != null) {
      _tel.text = FssPvit.telLisible(FssPvit.normaliserTelephone(widget.telephone!));
      _operateur = FssPvit.detecterOperateur(_telNormalise);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _verifierCompte();
      });
    }
  }

  @override
  void dispose() {
    _suivi?.cancel();
    _chrono?.cancel();
    _tel.dispose();
    super.dispose();
  }

  String get _telNormalise => FssPvit.normaliserTelephone(_tel.text);
  bool get _pret => FssPvit.telephoneValide(_telNormalise) && _operateur != null;

  void _fermer() {
    final p = _paiement;
    Navigator.of(context).pop(p == null
        ? const PvitResultat(false, PvitStatut.annule, null)
        : PvitResultat(p.paye, p.statut, p));
  }

  // ---------------------------------------------------------------- saisie
  void _surSaisie(String _) {
    final t = _telNormalise;
    final detecte = FssPvit.detecterOperateur(t);
    setState(() {
      if (detecte != null) _operateur = detecte;
      _erreurEnvoi = null;
    });
    _verifierCompte();
  }

  Future<void> _verifierCompte() async {
    final t = _telNormalise;
    if (!FssPvit.telephoneValide(t) || _operateur == null) {
      setState(() {
        _info = t.length >= 9 ? 'Numéro invalide' : null;
        _infoErreur = t.length >= 9;
        _fraisTexte = null;
      });
      return;
    }
    final jeton = ++_jetonKyc;
    final op = _operateur!;
    setState(() {
      _info = 'Vérification du compte…';
      _infoErreur = false;
    });
    try {
      final nom = await widget.service.kyc(t, operateur: op);
      if (!mounted || jeton != _jetonKyc) return;
      setState(() {
        _info = nom != null && nom.isNotEmpty ? 'Titulaire : $nom' : '${FssPvit.nomOperateur(op)} ✓';
        _infoErreur = false;
      });
    } on PvitErreur catch (e) {
      if (!mounted || jeton != _jetonKyc) return;
      setState(() {
        _info = e.message;
        _infoErreur = true;
      });
    }
    try {
      final f = await widget.service.frais(widget.montant, op);
      if (!mounted || jeton != _jetonKyc || f['frais'] == null) return;
      final frais = (f['frais'] as num);
      final total = (f['total'] as num?) ?? widget.montant;
      setState(() {
        _fraisTexte = f['payePar'] == 'MERCHANT'
            ? 'Frais PVIT à votre charge : ${FssPvit.fcfa(frais)}'
            : 'Frais PVIT : ${FssPvit.fcfa(frais)} — le client paiera ${FssPvit.fcfa(total)}';
      });
    } catch (_) {/* frais indicatifs */}
  }

  // ----------------------------------------------------------------- envoi
  Future<void> _envoyer() async {
    setState(() => _etape = _Etape.envoi);
    try {
      final p = await widget.service.initier(
        montant: widget.montant,
        telephone: _telNormalise,
        operateur: _operateur,
        ticket: widget.ticket,
        libelle: widget.libelle,
        caissier: widget.caissier,
      );
      _paiement = p;
      if (p.statut == PvitStatut.failed) {
        _afficherResultat();
      } else {
        _attendre();
      }
    } on PvitErreur catch (e) {
      setState(() {
        _etape = _Etape.saisie;
        _erreurEnvoi = e.message;
      });
    }
  }

  void _attendre() {
    _suivi?.cancel();
    _debutAttente = DateTime.now();
    _chrono?.cancel();
    _chrono = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    setState(() => _etape = _Etape.attente);
    _suivi = widget.service.attendreConfirmation(_paiement!).listen(
      (p) {
        _paiement = p;
        if (p.final_) _afficherResultat();
      },
      onDone: () {
        if (mounted && _etape == _Etape.attente) _afficherResultat();
      },
      onError: (Object e) {
        if (mounted) _afficherResultat();
      },
    );
  }

  Future<void> _verifierMaintenant() async {
    try {
      final p = await widget.service.suivre(_paiement!.reference, verifier: true);
      _paiement = p;
      if (p.final_) _afficherResultat();
    } catch (_) {}
  }

  void _afficherResultat() {
    _suivi?.cancel();
    _chrono?.cancel();
    if (!mounted) return;
    final p = _paiement;
    if (p != null && p.paye) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
    setState(() => _etape = _Etape.resultat);
  }

  // ------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 6, 6),
                child: Row(children: [
                  const Expanded(
                    child: Text('Paiement Mobile Money', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Fermer',
                    onPressed: _etape == _Etape.envoi
                        ? null
                        : () {
                            if (_etape == _Etape.attente) {
                              _suivi?.cancel();
                              _chrono?.cancel();
                              setState(() => _etape = _Etape.quitter);
                            } else {
                              _fermer();
                            }
                          },
                  ),
                ]),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: _contenu(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenu(BuildContext context) => switch (_etape) {
        _Etape.saisie => _ecranSaisie(context),
        _Etape.envoi => _etat(const CircularProgressIndicator(), 'Envoi de la demande…', null),
        _Etape.attente => _ecranAttente(),
        _Etape.quitter => Column(children: [
            _etat(_rond(Colors.orange, '!'), 'Arrêter d’attendre ?',
                'Le client peut encore valider le paiement. Il apparaîtra alors dans l’historique Mobile Money.'),
            _bouton('Continuer d’attendre', _attendre, principal: true),
            _bouton('Fermer sans attendre', _fermer),
          ]),
        _Etape.resultat => _ecranResultat(),
      };

  Widget _ecranSaisie(BuildContext context) {
    final sous = [widget.libelle, if (widget.ticket != null) 'Ticket ${widget.ticket}'].whereType<String>().join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(FssPvit.fcfa(widget.montant),
          textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
      if (sous.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(sous, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
        ),
      const SizedBox(height: 14),
      const Text('Numéro Mobile Money du client', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      TextField(
        controller: _tel,
        autofocus: true,
        keyboardType: TextInputType.phone,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 2),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d +]')), LengthLimitingTextInputFormatter(16)],
        decoration: InputDecoration(
          hintText: '074 00 00 00',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: _surSaisie,
        onSubmitted: (_) {
          if (_pret) _envoyer();
        },
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _choixOperateur('airtel', 'Airtel Money', _rougeAirtel)),
        const SizedBox(width: 10),
        Expanded(child: _choixOperateur('moov', 'Moov Money', _bleuMoov)),
      ]),
      const SizedBox(height: 10),
      if (_erreurEnvoi != null || _info != null)
        Text(_erreurEnvoi ?? _info!,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14,
                color: (_erreurEnvoi != null || _infoErreur) ? Colors.red.shade700 : Colors.green.shade800)),
      if (_fraisTexte != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(_fraisTexte!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        ),
      _bouton('Envoyer la demande au client', _pret ? _envoyer : null, principal: true),
      _bouton('Annuler', _fermer),
    ]);
  }

  Widget _choixOperateur(String op, String nom, Color couleur) {
    final actif = _operateur == op;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: BorderSide(color: actif ? couleur : Colors.grey.shade400, width: 2),
        backgroundColor: actif ? couleur.withValues(alpha: 0.08) : null,
        foregroundColor: actif ? couleur : Colors.grey.shade700,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () {
        setState(() => _operateur = op);
        _verifierCompte();
      },
      child: Text(nom, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
    );
  }

  Widget _ecranAttente() {
    final p = _paiement!;
    final s = _debutAttente == null ? 0 : DateTime.now().difference(_debutAttente!).inSeconds;
    final chrono = '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    return Column(children: [
      _etat(
        const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 6, color: _vert)),
        'En attente du client',
        'Demande de ${FssPvit.fcfa(p.montant)} envoyée au ${FssPvit.telLisible(p.telephone)} '
            '(${FssPvit.nomOperateur(p.operateur)}).\nLe client doit valider sur son téléphone avec son code PIN.',
      ),
      Text(chrono, style: TextStyle(color: Colors.grey.shade600, fontFeatures: const [FontFeature.tabularFigures()])),
      _bouton('Vérifier maintenant', _verifierMaintenant),
    ]);
  }

  Widget _ecranResultat() {
    final p = _paiement!;
    if (p.statut == PvitStatut.success) {
      return Column(children: [
        _etat(_rond(Colors.green.shade600, '✓'), 'Paiement reçu',
            '${FssPvit.fcfa(p.montant)} via ${FssPvit.nomOperateur(p.operateur)}\nRéf. PVIT ${p.transactionId ?? ''}'),
        _bouton('Terminer', _fermer, principal: true),
      ]);
    }
    if (p.statut == PvitStatut.failed) {
      return Column(children: [
        _etat(_rond(Colors.red.shade600, '✕'), 'Paiement non effectué', p.message ?? 'Refusé ou annulé par le client.'),
        _bouton('Réessayer', () {
          setState(() {
            _paiement = null;
            _etape = _Etape.saisie;
          });
        }, principal: true),
        _bouton('Autre mode de paiement', _fermer),
      ]);
    }
    return Column(children: [
      _etat(_rond(Colors.orange, '?'), 'Paiement non confirmé',
          'Aucune confirmation reçue pour l’instant. Ne relancez pas un nouveau paiement : vérifiez d’abord.\nRéf. ${p.reference}'),
      _bouton('Vérifier / attendre encore', _attendre, principal: true),
      _bouton('Fermer', _fermer),
    ]);
  }

  Widget _rond(Color c, String t) => Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800)),
      );

  Widget _etat(Widget icone, String titre, String? texte) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(children: [
          const SizedBox(height: 4),
          icone,
          const SizedBox(height: 14),
          Text(titre, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          if (texte != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(texte, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, height: 1.4)),
            ),
        ]),
      );

  Widget _bouton(String texte, VoidCallback? action, {bool principal = false}) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          width: double.infinity,
          child: principal
              ? FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _vert,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: action,
                  child: Text(texte, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                )
              : TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    backgroundColor: Colors.grey.withValues(alpha: 0.12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: action,
                  child: Text(texte, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
        ),
      );
}
