# Imprimantes intégrées — adaptateurs

Le projet sépare la caisse du transport d'impression.

Pour chaque famille de terminal qui exige un SDK propriétaire, ajouter un adaptateur natif dans
`MainActivity.kt` (ou un fichier Kotlin séparé), détecter le fabricant/modèle, puis appeler son
service local. Le ticket envoyé par Flutter reste identique.

Familles génériques prévues :
- Android Print Framework
- ESC/POS (USB / Bluetooth / TCP)
- Services d'impression constructeur
- SDK constructeur (adaptateur dédié)


### Senraise H10

Détection automatique des modèles **H10 / H10C / H10S / H10P** et impression directe via le plugin `senraise_printer`. Le H10S et H10P utilisent une imprimante thermique intégrée 58 mm selon Senraise. Pour un modèle H10 personnalisé/OEM dont le firmware expose une API différente, conserver le fallback Android ou fournir le SDK constructeur.
