# Journal des modifications — Amiin

Suivi chronologique des changements apportés au projet (backend + app Flutter).
Chaque entrée indique **quoi**, **pourquoi**, **les fichiers touchés**, **ce qui
reste à vérifier** et **les actions manuelles** éventuelles.

Feuille de route en cours (priorités avant l'intégration des paiements) :

1. **APK publiable** — identifiant, signature, R8, sauvegardes, permissions ✅ (code fait, build à valider)
2. Comptes — vérification e-mail, contrôle `is_active`, rate limiting persistant
3. Quotas — table `usage`, colonne `plan`, `GET /v1/me/usage`, jauge dans l'app
4. Paramètres — brancher ou retirer les réglages sans effet, i18n anglais, sessions par appareil
5. Play Integrity + revue de sécurité, puis paiements

---

## 2026-11-26 — Étape 1 : rendre l'APK publiable et durcir le build Android

### 1. Identifiant d'application définitif : `dj.amiin.app`
- **Avant** : `com.example.amiin_app_flutter`, préfixe refusé par le Play Store.
- **Après** : `applicationId` et `namespace` = `dj.amiin.app`. Les sources Kotlin ont été
  déplacées de `kotlin/com/example/amiin_app_flutter/` vers `kotlin/dj/amiin/app/`
  (`MainActivity.kt`, `AmiinBriefWidgetProvider.kt`, package mis à jour).
- Même identifiant reporté sur iOS / macOS (`PRODUCT_BUNDLE_IDENTIFIER`) et Linux
  (`APPLICATION_ID`). Les mentions « com.example » ont été remplacées par « Amiin »
  (copyright macOS, Runner.rc Windows).
- ⚠️ **Irréversible après la première publication** sur le Play Store / App Store.
  À confirmer avant le premier upload (en principe on utilise un domaine qu'on
  possède, écrit à l'envers : `amiin.dj` → `dj.amiin.app`).
- ⚠️ Pour Android, c'est une **nouvelle application** : une version déjà installée
  sous l'ancien identifiant reste en place à côté de la nouvelle, et ses données
  locales ne sont pas reprises. Désinstaller l'ancienne sur les téléphones de test.

### 2. Signature release obligatoire
- **Avant** : sans `android/key.properties`, la release était signée
  **silencieusement** avec la clé debug. L'APK obtenu n'était ni publiable ni mettable
  à jour.
- **Après** : un build `*Release*` sans `key.properties` échoue avec un message clair.
  Pour un test local ponctuel, il reste une échappatoire explicite :
  `AMIIN_ALLOW_DEBUG_SIGNING=1`.
- Fichier : `amiin_app_flutter/android/app/build.gradle.kts`.

### 3. R8 : réduction et obfuscation du code natif + règles de conservation
- `isMinifyEnabled = true`, `isShrinkResources = true` et
  `proguard-android-optimize.txt` sont désormais explicites. Le plugin Flutter les
  active déjà par défaut ; l'écrire évite une désactivation silencieuse.
- Nouveau `android/app/proguard-rules.pro` :
  - règles Gson + `com.dexterous.**`, requises par `flutter_local_notifications` (sans
    elles, les rappels d'agenda planifiés peuvent casser en release) ;
  - conservation du widget ;
  - `dontwarn` Play Core.
- Nouveau `android/app/src/main/res/raw/keep.xml` : empêche la suppression de l'icône
  de notification (résolue par son nom à l'exécution) et des ressources du widget.

### 4. Obfuscation du code Dart — script de build
- Nouveau `amiin_app_flutter/tool/build_release.sh` (`appbundle` par défaut ou `apk`) :
  `--obfuscate --split-debug-info=symbols/<version>` et URL de l'API de production.
- `symbols/` est ajouté au `.gitignore`. **Archiver ce dossier pour chaque version
  publiée** : sans lui, les traces de plantage sont illisibles.

### 5. Sauvegardes Android désactivées
- `android:allowBackup="false"`, `android:fullBackupContent="false"` et
  `android:dataExtractionRules="@xml/data_extraction_rules"` (nouveau fichier qui exclut
  tout du cloud et du transfert entre appareils, Android 12+).
- **Pourquoi** : les données locales (Hive) et les jetons sont chiffrés avec une clé du
  Keystore Android, propre à l'appareil. Une fois restaurées sur un autre téléphone,
  elles seraient illisibles (boîtes recréées vides, session corrompue). Cela évite aussi
  que les jetons de session partent dans Google Drive.

### 6. Alarmes exactes : retrait de `USE_EXACT_ALARM`
- **Avant** : `USE_EXACT_ALARM` + `SCHEDULE_EXACT_ALARM`. Google Play réserve
  `USE_EXACT_ALARM` aux applis de réveil ou de calendrier, avec une déclaration
  obligatoire et un risque de refus.
- **Après** : seule `SCHEDULE_EXACT_ALARM` est conservée. Dans
  `lib/services/notification_service.dart`, `_scheduleMode()` vérifie
  `canScheduleExactNotifications()` et passe en `inexactAllowWhileIdle` si
  l'autorisation manque, au lieu de lever une exception et de perdre le rappel.
- **Effet** : sur Android 14+, l'autorisation est refusée par défaut, donc les rappels
  d'agenda peuvent arriver **quelques minutes en retard**. À traiter à l'étape 4
  (paramètres) : un bouton « Rappels à l'heure exacte » qui appelle
  `requestExactAlarmsPermission()`.

### À vérifier localement (pas de SDK Flutter ni Android dans l'environnement où ces changements ont été faits)
- [ ] `flutter clean && flutter pub get && flutter analyze`
- [ ] `flutter run` en debug : démarrage, widget d'accueil, notification d'agenda
- [ ] `tool/build_release.sh apk` avec `key.properties` : le build R8 passe, l'app
      démarre, un rappel d'agenda programmé s'affiche bien (avec son icône)
- [ ] Sans `key.properties` : le build release doit **échouer** avec le message prévu
- [ ] Ajouter le widget sur l'écran d'accueil après installation (le nom du package a changé)

### Actions manuelles
- [ ] Confirmer l'identifiant `dj.amiin.app` avant la première publication
- [ ] Générer la clé d'upload, la sauvegarder hors du dépôt et créer `android/key.properties` :
      `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
- [ ] Play Console : activer la signature par Google Play (Play App Signing)
