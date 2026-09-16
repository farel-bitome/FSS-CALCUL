# FSS-CALCUL — Android multi-terminaux

Cette version prépare FSS-CALCUL pour les terminaux Android avec imprimante intégrée.

## Architecture d'impression
- Imprimante intégrée via service/SDK constructeur : point d'extension dans `MainActivity.kt`.
- Système d'impression Android : fallback générique.
- ESC/POS USB/Bluetooth/Wi-Fi : couche d'adaptation à ajouter selon le matériel.
- Ticket thermique prévu pour 58 mm.

## Important
Il n'existe pas de protocole unique pour toutes les imprimantes intégrées. Certains fabricants
imposent leur propre SDK/service Android. Le moteur de caisse est indépendant du pilote : on peut
ajouter un adaptateur par famille de terminaux sans modifier les tickets ou la comptabilité.

## Lancer
Installer Flutter, puis :
`flutter pub get`
`flutter run`

Pour produire l'APK :
`flutter build apk --release`

## H10S et autres terminaux
Le branchement direct à l'imprimante intégrée d'un modèle précis nécessite de vérifier son
service/SDK disponible. Cette base fournit déjà le ticket 58 mm et le fallback Android.


## SUNMI V2 PRO — intégré

Le projet inclut maintenant un chemin d'impression natif SUNMI pour les terminaux V2 PRO.
L'application détecte SUNMI/V2 PRO et tente d'utiliser le service d'impression intégré avant
de retomber sur le système d'impression Android.

Le V2 PRO possède une imprimante thermique intégrée 58 mm. L'intégration utilise la bibliothèque
officielle SUNMI `com.sunmi:printerlibrary:1.0.15` et le service d'impression intégré.

## Compatibilité SUNMI élargie

Le moteur SUNMI est maintenant **générique** : il ne dépend plus uniquement du V2 PRO.
Il détecte les terminaux SUNMI et utilise le service d'imprimante interne lorsqu'il est exposé
par le système.

Familles ciblées : V1/V1s, V2/V2 Pro/V2s, V3, P1/P1 4G et gammes POS T1/T2/T2 mini/T2s,
D2 et S2, sous réserve que le modèle dispose bien d'une imprimante intégrée et que son firmware
expose le service SUNMI correspondant.

SUNMI indique que son service d'impression interne couvre plusieurs familles mobiles, paiement,
desktop POS et POS scale, avec des imprimantes intégrées en 58 mm ou 80 mm selon le modèle.
Le SDK officiel prévoit aussi des différences d'API selon certains modèles. 


## Senraise H10 — toutes les variantes

L'application détecte automatiquement les terminaux Senraise H10/H10C/H10S/H10P et utilise l'intégration Flutter `senraise_printer` pour l'imprimante thermique intégrée. Le H10S et le H10P disposent officiellement d'une imprimante thermique intégrée 58 mm à 80 mm/s; la documentation Senraise actuelle confirme Android 13 pour H10S et Android 14 pour H10P.

Variantes ciblées : **H10, H10C, H10S, H10P**. Les anciennes variantes peuvent avoir un firmware ou un SDK différent : dans ce cas, FSS-CALCUL conserve le mécanisme d'impression Android de secours.


### Devise configurable
- La devise peut être modifiée depuis **Paramètres > Devise**.
- Choix inclus : FCFA, EUR, USD, GBP, CHF, MAD, XOF et XAF.
- Le choix est mémorisé localement sur chaque terminal et appliqué aux montants et aux tickets imprimés.

### Paramètres société
Un écran **Paramètres > Paramètres société** permet de renseigner :
- Nom de la société
- Adresse
- Téléphone
- E-mail
- Identifiant fiscal / NIF
- Registre de commerce / RCCM
- Site web
- Pied de ticket

Les informations sont sauvegardées localement et reprises automatiquement sur les tickets imprimés.

### Logo
Le logo fourni pour FSS-CALCUL est intégré comme ressource de l'application et affiché dans l'en-tête, les paramètres et l'écran d'accueil.
