# Journal des modifications — Amiin

Suivi chronologique des changements apportés au projet (backend + app Flutter).
Chaque entrée indique **quoi**, **pourquoi**, **les fichiers touchés**, **ce qui
reste à vérifier** et **les actions manuelles** éventuelles.

Feuille de route en cours (priorités avant l'intégration des paiements) :

1. **APK publiable** — identifiant, signature, R8, sauvegardes, permissions ✅ (code fait, build à valider)
2. **Comptes** — vérification e-mail, compte admin, contrôle `is_active`, limites persistantes ✅
   - 2b. **Données locales propres à chaque compte** — aujourd'hui, en changeant de compte sur
     le même téléphone, on voit les discussions, notes, agenda, démarches et profil du compte
     précédent (stockage Hive commun à tous les comptes). Signalé le 2026-11-26. ✅
3. Quotas — table `usage`, colonne `plan`, `GET /v1/me/usage`, jauge dans l'app
4. Paramètres — brancher ou retirer les réglages sans effet, i18n anglais, sessions par appareil,
   bouton « Rappels à l'heure exacte » (cf. étape 1, §6)
5. Play Integrity + revue de sécurité, puis paiements

---

## ✅ À faire de mon côté (liste unique, mise à jour à chaque étape)

À faire en une seule fois. Chaque ligne renvoie à l'étape qui l'a ajoutée.

**Build et tests de l'app**
- [ ] `flutter clean && flutter pub get && flutter analyze` sur ta version de Flutter (déjà propre avec 3.50.1 ici) (étapes 1-2)
- [ ] Désinstaller l'ancienne app (`com.example…`) des téléphones de test (étape 1)
- [ ] `tool/build_release.sh apk` avec `key.properties` : l'app démarre, un rappel d'agenda
      s'affiche avec son icône, le widget d'accueil s'ajoute et se met à jour (étape 1)
- [ ] Sans `key.properties`, le build release doit échouer avec le message prévu (étape 1)
- [ ] Parcours inscription → écran « Vérifiez votre e-mail » → code reçu → accès à l'app ;
      « Renvoyer le code » ; mauvais code ; « Utiliser une autre adresse » (étape 2)
- [ ] Se connecter avec le compte admin : Réglages › Compte affiche « Administrateur » (étape 2)
- [ ] Mettre à jour l'app sur ton téléphone EN RESTANT CONNECTÉ à ton compte principal : tes
      conversations, notes, agenda et démarches lui seront rattachés. Ensuite, compte A → déconnexion →
      compte B : B ne voit rien de A ; retour sur A : tout est là. Vérifier aussi les rappels
      d'agenda et le widget après le changement de compte (étape 2b)

**Publication**
- [ ] Confirmer l'identifiant `dj.amiin.app` avant la première publication (étape 1)
- [ ] Générer la clé d'upload, la sauvegarder hors du dépôt, créer `android/key.properties` :
      `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload` (étape 1)
- [ ] Play Console : activer Play App Signing (étape 1)

**Serveur (Render › amiin-api › Environment)**
- [ ] `ADMIN_EMAILS` = ton adresse e-mail (étape 2). Si le compte existe déjà, il devient admin
      au redéploiement ; sinon, il le devient dès l'inscription avec cette adresse.
- [ ] Créer un compte Brevo (gratuit, 300 e-mails/jour), valider l'adresse d'expédition,
      créer une clé API, puis renseigner `BREVO_API_KEY` et `SMTP_FROM` (ex. `Amiin <adresse@validée>`) (étape 2)
- [ ] Après le déploiement : la vérification devient active toute seule. Les comptes existants
      (hors admin) devront saisir un code une fois à leur prochaine ouverture de l'app (étape 2)

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

→ Vérifications et actions manuelles : voir la liste « À faire de mon côté » en haut.

---

## 2026-11-26 — Étape 2 : comptes (vérification d'e-mail, admin, comptes désactivés, limites)

### 1. Vérification de l'adresse e-mail par code à 6 chiffres
- **Principe** : même mécanique que « mot de passe oublié ». À l'inscription, le serveur envoie
  un code (valable 30 min, 5 essais) ; l'app affiche l'écran **« Vérifiez votre e-mail »**
  (`lib/screens/auth/verify_email_screen.dart`) jusqu'à ce que le code soit saisi.
  « Renvoyer le code » est possible une fois par minute, 5 fois par heure. Un lien
  « Utiliser une autre adresse » déconnecte l'utilisateur.
- **Serveur** (`auth.py`) :
  - `POST /v1/auth/verify-email` (code) et `POST /v1/auth/verify-email/send` ;
  - `/auth/me` renvoie `email_verified` et `role` ;
  - nouvelle table `email_verification_codes` (code stocké en HMAC, séparé des codes de
    réinitialisation : un code de vérification ne peut pas servir à changer le mot de passe).
- **Ce qui est bloqué tant que l'adresse n'est pas vérifiée** : côté serveur, le chat, la
  synthèse et la reconnaissance vocales (`/v1/chat*`, `/v1/tts`, `/v1/stt` → 403). Ce sont les
  fonctions qui coûtent de l'argent. Côté app, l'utilisateur reste sur l'écran de vérification.
- **Activation** (`EMAIL_VERIFICATION`) : par défaut, la vérification est exigée **dès qu'un envoi
  d'e-mails est configuré**. Sans envoi configuré, elle est désactivée, pour que personne ne
  reste bloqué. `EMAIL_VERIFICATION=off` ou `required` force l'un ou l'autre.
- **Comptes existants** : colonne `email_verified` ajoutée à `FALSE`. Ils saisiront un code une
  fois, quand la vérification sera active.
- **Envoi des e-mails** : nouvelle fonction `_send_email`, utilisée aussi par « mot de passe
  oublié ». Elle passe par l'**API HTTP Brevo** si `BREVO_API_KEY` est définie, sinon par SMTP
  comme avant. L'API HTTP fonctionne même si l'hébergeur bloque les ports SMTP.
- **Prototype puis production** :
  - *Prototype (maintenant)* : Brevo gratuit (300 e-mails/jour), expéditeur = une adresse que tu
    valides chez Brevo (Gmail possible). Les e-mails risquent d'arriver dans les indésirables,
    d'où la mention dans l'écran.
  - *Production* : domaine à nous (ex. `amiin.dj`) authentifié chez Brevo (SPF, DKIM, DMARC),
    expéditeur `no-reply@amiin.dj`, e-mail HTML soigné aux couleurs d'Amiin, blocage des
    adresses jetables, suivi des rebonds. Plus tard, éventuellement, un code par SMS (plus
    naturel à Djibouti), le jour où un fournisseur SMS local est choisi.

### 2. Compte administrateur
- Colonne `role` (`user` | `admin`) sur `users`. **`ADMIN_EMAILS`** (variable Render, adresses
  séparées par des virgules) est la source de vérité : au démarrage, ces comptes passent admin,
  et un e-mail retiré de la liste redevient simple utilisateur. Une inscription avec une adresse
  de la liste est admin immédiatement.
- Un admin a une adresse réputée vérifiée (aucun code demandé) et **aucune limite d'usage**
  (plus de plafond par minute sur le chat et la voix ; les quotas de l'étape 3 l'excluront aussi).
- Dans l'app, Réglages › Compte affiche « Type de compte : Administrateur ».
- Aucun mot de passe admin dans le code ni dans les variables : on promeut un compte normal.

### 3. Compte désactivé ou supprimé : accès coupé en 1 minute au lieu de 30
- **Avant** : le jeton d'accès (JWT) suffisait. Un compte désactivé ou supprimé gardait l'accès
  jusqu'à l'expiration du jeton (30 min).
- **Après** : `get_current_user` relit l'état du compte en base (`is_active`, `email_verified`,
  `role`) avec un cache de 60 s par processus. Le renouvellement de session (`/auth/refresh`) est
  aussi refusé pour un compte désactivé.
- Si la base est momentanément injoignable, on garde le dernier état connu, ou on laisse passer
  un jeton valide, plutôt que de couper toute l'application.

### 4. Limites persistantes
- Nouvelle table `auth_rate_events`. Les limites **par compte** sont désormais en base et
  survivent aux redémarrages et aux mises en veille de Render :
  - 10 échecs de connexion par e-mail en 15 min ;
  - 3 demandes « mot de passe oublié » par heure ;
  - envois de codes de vérification (1 par minute, 5 par heure).
- Restent en mémoire, volontairement :
  - les plafonds grossiers **par IP** (beaucoup d'utilisateurs partagent la même IP à Djibouti) ;
  - l'anti-rafale par minute sur le chat et la voix : il protège seulement d'une boucle, et
    une remise à zéro au redéploiement ne pose pas de problème.

  Les vrais plafonds d'usage seront les quotas journaliers en base, à l'étape 3.
- Les événements de plus de 2 jours sont purgés au démarrage.

### 5. App : messages d'erreur du chat
- 403 → « Votre adresse e-mail n'est pas encore vérifiée… » ; 429 → « Patientez un instant… »,
  au lieu du message générique « impossible de joindre le service ».

### Tests
- `tests/test_auth_db.py` (nouveau) : 10 tests contre une vraie base PostgreSQL (inscription →
  code → accès, tentatives limitées, renvoi limité, code de vérification refusé pour un reset,
  admin sans limite, admin retiré de la liste, compte désactivé coupé, échecs de connexion
  conservés après redémarrage, mode `off`, suppression du compte). Ces tests sont ignorés sans
  `TEST_DATABASE_URL`.
- Résultat : **55 tests passent** (PostgreSQL 16 local).
- App : `flutter analyze` (Flutter 3.50.1) ne trouve **aucune erreur**, et rien sur les
  fichiers modifiés aux étapes 1 et 2. Les remarques restantes existaient déjà. Les tests
  Flutter existants passent (18/18). Pas de build Android ici (pas de SDK Android).

### Fichiers
`auth.py`, `amiin_api.py`, `render.yaml`, `tests/test_auth.py`, `tests/test_auth_db.py`,
`lib/services/auth_service.dart`, `lib/navigation/app_router.dart`,
`lib/screens/auth/verify_email_screen.dart` (nouveau), `lib/services/chat_controller.dart`,
`lib/screens/settings/settings_account_screen.dart`.

---

## 2026-11-26 — Étape 2b : données locales propres à chaque compte

### Le problème
Sur le téléphone, toutes les données personnelles étaient enregistrées dans des « boîtes » Hive
communes à tous les comptes : conversations, mémoire d'Amiin, notes, agenda, démarches suivies,
profil et préférences d'Amiin. En changeant de compte, on voyait donc celles du compte précédent.

### La solution
- **Une boîte par compte.** Chaque boîte porte l'identifiant du compte, par exemple
  `notes_box_u_<id>`, et elles sont toutes chiffrées. Hors connexion, l'app pointe vers un
  espace « invité » vide.
- **Rien n'est perdu à la déconnexion.** Les données d'un compte restent sur le téléphone (chiffrées)
  et réapparaissent quand ce compte se reconnecte. Un autre compte ne les voit jamais.
- **Ce qui reste commun à l'appareil** : thème, taille du texte, police, langue de l'interface,
  voix, réglages des notifications, catalogue des démarches et brief d'accueil (météo, prières, taux).
- **Ce qui devient propre au compte** : profil (prénom, nom, année de naissance, profession…),
  comportement d'Amiin (ton, longueur, expertise, mémoire, sujets favoris), langue des réponses,
  devise, affichage des sources, mode vocal par défaut.
- **Au changement de compte** :
  - les rappels programmés (agenda, relances de démarches) de l'ancien compte sont annulés,
    puis ceux du nouveau sont reprogrammés ;
  - le widget d'accueil est mis à jour ;
  - le chat affiche l'historique du nouveau compte.

### Données existantes (première ouverture de cette version)
- Si un compte est **connecté au lancement**, les anciennes données communes lui sont attribuées.
  C'est presque toujours le propriétaire du téléphone.
- Si **personne n'est connecté**, on ne peut pas savoir à qui elles appartiennent : elles sont
  **effacées** plutôt que risquer de les montrer au mauvais compte.
- Conséquence pratique : mettre à jour l'app en restant connecté à son compte principal (voir la liste).

### Bug corrigé au passage
- « Supprimer toutes mes données » (Confidentialité) et l'effacement local lors de la
  suppression du compte **plantaient** dès la première boîte : `Hive.box<dynamic>` refuse une
  boîte ouverte avec un type précis. Les données n'étaient donc pas effacées. L'effacement passe
  maintenant par chaque service et ne touche que le compte actif.

### Technique
- Nouveau `lib/services/user_scope.dart` :
  - `UserScope.activate(userId)` bascule toutes les données ;
  - `ScopedBox` se rouvre sur la boîte du compte actif ;
  - `BoxChanges` est un « listenable » stable qui notifie aussi au changement de compte ;
  - contient aussi la migration et `wipeLocalUserData()`.
- `AuthService` appelle la bascule à chaque changement d'utilisateur : démarrage, connexion,
  inscription, déconnexion, suppression du compte, session expirée. Jamais dans la tâche de fond
  du widget, qui ne touche pas à Hive.
- `SettingsService` : `accountKeys` liste les préférences propres au compte, stockées dans
  `settings_account_<compte>` ; les autres restent dans `settings`.
- `MemoryService`, `NotesService`, `AgendaService`, `DemarchesService` : boîtes par compte.
  `ChatController` recharge l'historique au changement de compte.
- `bootstrap.dart` n'ouvre plus les données personnelles : c'est la bascule de compte qui s'en charge.

### Tests
- `test/user_scope_test.dart` (nouveau, 3 tests) :
  - deux comptes sur le même téléphone ne partagent ni notes, ni messages, ni profil, alors
    que le thème reste commun ;
  - reprise des anciennes données par le compte connecté au lancement, effacement si personne
    n'est connecté ;
  - « Supprimer toutes mes données » n'efface que le compte actif.
- `flutter analyze` : aucune erreur, rien sur les fichiers modifiés. `flutter test` : 22/22.
