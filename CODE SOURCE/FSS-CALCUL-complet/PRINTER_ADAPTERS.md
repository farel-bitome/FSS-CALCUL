# Imprimantes intégrées — adaptateurs

Le projet sépare la caisse du transport d'impression : le ticket envoyé par Flutter reste
identique, quel que soit le terminal.

## Ajouter un adaptateur

Pour un terminal qui exige un SDK propriétaire :

1. Détecter le fabricant et le modèle (`Build.MANUFACTURER`, `Build.MODEL`).
2. Si un plugin Flutter fiable existe, l'utiliser côté Dart.
3. Sinon, écrire un adaptateur natif en Kotlin (de préférence dans un fichier séparé, appelé
   depuis `MainActivity.kt` via un `MethodChannel`) qui appelle le service local du fabricant.
4. En cas d'échec, retomber sur l'impression Android.

## Familles prévues

- SDK / service constructeur (adaptateur dédié)
- ESC/POS (USB, Bluetooth, TCP)
- Système d'impression Android (secours)

## Adaptateurs existants

### SUNMI

Adaptateur natif Kotlin utilisant `com.sunmi:printerlibrary:1.0.24`, déclaré dans
`android/app/build.gradle`. Détection de tout terminal SUNMI exposant le service d'impression
interne.

### Senraise H10

Détection des modèles **H10, H10C, H10S et H10P** et impression directe via le service Android de Senraise
(`recieptservice`), appelé directement depuis `MainActivity.kt` (interface copiée dans
`android/app/src/main/java/recieptservice/`, licence BSD-3). Le H10S et le H10P ont une
imprimante thermique intégrée 58 mm.

Pour un modèle H10 personnalisé ou OEM dont le firmware expose une API différente, conserver le
secours Android ou obtenir le SDK auprès de Senraise.
