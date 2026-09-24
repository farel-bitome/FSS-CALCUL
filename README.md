# FSS-CALCUL — Caisse Android multi-terminaux

FSS-CALCUL est une application de caisse Android (Flutter) conçue pour les terminaux
de paiement avec imprimante thermique intégrée.

## Lancer le projet

Installer Flutter, puis :

```bash
flutter pub get
flutter run
```

Pour produire l'APK :

```bash
flutter build apk --release
```

## Architecture d'impression

Le moteur de caisse est indépendant du pilote d'impression : le ticket est construit une seule
fois côté Flutter, puis envoyé à l'adaptateur correspondant au terminal détecté. On peut donc
ajouter un adaptateur par famille de terminaux sans modifier les tickets ni la comptabilité.

Il n'existe pas de protocole unique pour toutes les imprimantes intégrées : certains fabricants
imposent leur propre SDK ou service Android.

Ordre de priorité à l'impression :

1. **SDK / service constructeur** (SUNMI, Senraise) si le terminal est reconnu
2. **ESC/POS** (USB, Bluetooth, TCP/Wi-Fi) — couche d'adaptation à ajouter selon le matériel
3. **Système d'impression Android** — solution de secours générique

Le ticket est prévu pour du papier thermique **58 mm**.

Détails techniques des adaptateurs : voir `PRINTER_ADAPTERS.md`.

## Terminaux pris en charge

### SUNMI

Le moteur SUNMI est générique : il détecte les terminaux SUNMI (par le fabricant, pas par le nom du modèle) et utilise le service
d'impression interne lorsque le système l'expose, avant de retomber sur l'impression Android.

- Bibliothèque officielle : `com.sunmi:printerlibrary:1.0.24`
  (dépendance Gradle, déclarée dans `android/app/build.gradle`, pas dans `pubspec.yaml`)
- Familles ciblées : V1/V1s, V2/V2 Pro/V2s, V3, P1/P1 4G, T1/T2/T2 mini/T2s, D2, S2
- Condition : le modèle doit avoir une imprimante intégrée et son firmware doit exposer le
  service SUNMI. Selon le modèle, l'imprimante est en 58 mm ou 80 mm, et certaines API
  diffèrent d'un modèle à l'autre.

Le V2 Pro a été la première cible (imprimante thermique intégrée 58 mm).

### Senraise H10

Détection automatique des modèles **H10, H10C, H10S et H10P**, avec impression via le plugin
Flutter `senraise_printer`.

- Le H10S et le H10P disposent d'une imprimante thermique intégrée 58 mm.
- Les anciennes variantes ou les modèles OEM peuvent avoir un firmware ou un SDK différent :
  dans ce cas, FSS-CALCUL bascule sur l'impression Android de secours.
- Le plugin `senraise_printer` n'est pas publié par Senraise (éditeur non vérifié) : à tester
  sur un vrai terminal avant livraison. En cas d'échec, demander le SDK officiel au support
  Senraise.

## Paramètres

### Devise

Modifiable dans **Paramètres > Devise**. Choix disponibles :

| Code | Devise |
|------|--------|
| XAF  | Franc CFA (CEMAC — Gabon, Cameroun, Congo…) — **par défaut** |
| XOF  | Franc CFA (UEMOA — Sénégal, Côte d'Ivoire…) |
| EUR  | Euro |
| USD  | Dollar américain |
| GBP  | Livre sterling |
| CHF  | Franc suisse |
| MAD  | Dirham marocain |

Sur les tickets et à l'écran, XAF et XOF s'affichent « FCFA ».

Le choix est mémorisé localement sur chaque terminal : il faut donc le régler sur chaque
appareil.

### Historique des tickets

Les tickets validés et le compteur de numérotation sont enregistrés sur le terminal (500 derniers
tickets) : la numérotation continue après un redémarrage de l'application.

### Paramètres société

**Paramètres > Paramètres société** permet de renseigner :

- Nom de la société
- Adresse
- Téléphone
- E-mail
- NIF (identifiant fiscal)
- RCCM (registre de commerce)
- Site web
- Pied de ticket

Ces informations sont enregistrées localement et reprises automatiquement sur les tickets
(nom, adresse, téléphone, e-mail, site web, NIF, RCCM et pied de ticket).

### Logo

Le logo FSS-CALCUL (`assets/fss_logo.png`) est affiché dans l'en-tête, les paramètres et
l'écran d'accueil.
