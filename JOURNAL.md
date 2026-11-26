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
3. **Quotas** — coût réel par appel, enveloppe quotidienne, blocage du chat, jauge ✅
4. **Paramètres** — réglages sans effet branchés ou retirés, sessions par appareil ✅
   (« Rappels à l'heure exacte » : reporté à ta demande ; traduction anglaise : projet à part)
5. **Play Integrity + revue de sécurité** ✅ (code fait, mise en service à faire de ton côté), puis paiements

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
- [ ] Réglages : couper « Rappels agenda » → un rappel programmé ne sonne plus, le rallumer → il
      revient ; « Mémoire long terme » coupée → Amiin ne cite plus vos actions passées ;
      « Animations réduites » → plus de glissement entre les écrans (étape 4)
- [ ] Appareils connectés : se connecter sur deux appareils (ou téléphone + démo web), vérifier la
      liste dans Réglages › Sécurité, déconnecter l'autre appareil → il revient à l'écran de
      connexion en une minute au plus (étape 4)
- [ ] Quota : envoyer quelques messages (écrits et vocaux) et suivre la jauge dans
      Réglages › Compte ; vérifier qu'une fois la limite atteinte la barre de saisie est
      remplacée par le message « Limite d'utilisation du jour atteinte » et que le micro est
      refusé. Avec le compte admin : « Utilisation illimitée » (étape 3)

**Play Integrity (étape 5)**
- [ ] Play Console › Intégrité de l'application : associer un projet Google Cloud et y activer
      l'API Play Integrity ; noter le **numéro** du projet
- [ ] Dans ce projet Google Cloud : créer un compte de service et générer sa clé JSON
- [ ] Render : `PLAY_INTEGRITY_SA_JSON` = contenu de la clé JSON ; `INTEGRITY_MODE=report`
- [ ] Compiler avec `AMIIN_CLOUD_PROJECT_NUMBER=<numéro> tool/build_release.sh appbundle`
- [ ] Après quelques jours en `report` (journaux « Play Integrity [report] … : ok »), passer
      `INTEGRITY_MODE=enforce`. Attention : un APK installé hors Play Store (comme l'APK de test)
      sera refusé en `enforce`, sauf pour les adresses de `ADMIN_EMAILS`

**Publication**
- [ ] Confirmer l'identifiant `dj.amiin.app` avant la première publication (étape 1)
- [ ] Générer la clé d'upload, la sauvegarder hors du dépôt, créer `android/key.properties` :
      `keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload` (étape 1)
- [ ] Play Console : activer Play App Signing (étape 1)

**Serveur (Render › amiin-api › Environment)**
- [ ] `ADMIN_EMAILS` = ton adresse e-mail (étape 2). Le rôle admin n'est accordé qu'une fois
      l'adresse vérifiée par le code reçu par e-mail (correctif de la revue de sécurité).
- [ ] Vérifier dans les journaux de production (`/v1/logs`, champ `claude_cache_read`) si le cache
      de prompt fonctionne : la simulation indique que non avec Haiku 4.5 (voir revue du 26/11)
- [ ] **Haiku 5.5 (défaut désormais en français et en anglais) : tester la QUALITÉ des réponses
      avec la vraie clé** (la simulation ne mesure que le coût). Si elle déçoit : variable Render
      `CLAUDE_MODEL=claude-haiku-4-5-20251001`, sans redéploiement de code (étape 3b)
- [ ] Ne jamais changer `JWT_SECRET_KEY` (ou définir `QUOTA_KEY_SECRET` une fois pour toutes) :
      les quotas sont rattachés aux adresses via ce secret (étape 3b)
- [ ] Créer un compte Brevo (gratuit, 300 e-mails/jour), valider l'adresse d'expédition,
      créer une clé API, puis renseigner `BREVO_API_KEY` et `SMTP_FROM` (ex. `Amiin <adresse@validée>`) (étape 2)
- [ ] (Optionnel) `QUOTA_DAILY_USD` : 0.10 par défaut pour les tests, passer à `0.02` plus tard ;
      `QUOTA_ENFORCE=0` pour mesurer sans bloquer personne (étape 3)
- [ ] Vérifier les tarifs voix chez Groq (whisper-large-v3 : 0,111 $/h, 10 s minimum par requête
      retenus) et Jina (0,05 $/M tokens retenu) ; ajustables par variables d'environnement (étape 3)
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

---

## 2026-11-26 — Étape 3 : quota d'utilisation quotidien (coût réel)

### Décisions (prises avec toi)
- **Unité** : le **coût réel** de chaque appel, en dollars. Une grande question, un long
  historique, une tâche en plusieurs passes ou une réponse en somali (Sonnet, 2× plus cher)
  consomment automatiquement plus. Aucune pondération faite à la main.
- **Enveloppe** : **0,10 $ par jour** pendant les tests (`QUOTA_DAILY_USD`), à descendre à 0,02 $
  ensuite. Remise à zéro **chaque jour à minuit, heure de Djibouti**.
- **Au-delà** : **chat bloqué**. Plus d'envoi ni de dictée jusqu'à minuit.
- **Voix dans la même enveloppe** :
  - la reconnaissance vocale est débitée selon la durée d'audio (tarif Groq, 10 s minimum) ;
  - la synthèse est débitée à 4 $ par million de caractères. Edge TTS est gratuit ; ce tarif est
    volontairement modéré, pour que **l'oral consomme un peu plus que l'écrit** sans le
    pénaliser. Il est réglable (`TTS_USD_PER_MILLION_CHARS`) pour calibrer.

### Serveur
- Nouveau `usage.py` :
  - `UsageMeter` additionne le coût de tous les appels déclenchés par une requête : réponse
    principale, reformulation de la question, embeddings Jina, voix ;
  - tarifs par modèle : Haiku 4.5 1 $/5 $, Sonnet 5 2 $/10 $ par million de tokens. Le cache
    est compté à 0,1× en lecture et 1,25× en écriture. Les tarifs de Haiku 5.5 et Sonnet 5.5
    sont prêts ; un modèle inconnu reçoit le tarif prudent ;
  - table `usage_events` : une ligne par requête (coût en micro-dollars, tokens par catégorie,
    secondes d'audio, caractères lus) ;
  - `ensure_quota` renvoie **402** (en-tête `X-Amiin-Error: quota_exceeded`) une fois
    l'enveloppe épuisée.
- **Réponse arrêtée en cours de route** (bouton stop, réseau coupé) : les tokens ont quand même
  été facturés par Anthropic. Le coût est estimé de façon prudente, sinon arrêter chaque
  réponse permettrait de contourner le quota.
- **Contrôles** :
  - `/v1/chat`, `/v1/chat/stream` et `/v1/stt` sont bloqués dès l'enveloppe épuisée ;
  - `/v1/tts` garde une marge de 25 %, pour pouvoir lire à voix haute la réponse qui vient de
    faire franchir le seuil.
- **Admins** (`ADMIN_EMAILS`) : jamais bloqués, mais leur usage est enregistré.
  `QUOTA_ENFORCE=0` : mesure seule, personne n'est bloqué.
- Nouveau `GET /v1/me/usage` : pourcentage utilisé, épuisé ou non, illimité ou non, heure de
  remise à zéro.
- Reconnaissance vocale : Groq est interrogé en `verbose_json` pour obtenir la durée exacte de
  l'audio.
- `Dockerfile` : copie de `usage.py`.

### App
- Nouveau `UsageService` : suit la jauge, se rafraîchit après chaque réponse, au changement de
  compte et à minuit.
- **Chat** : quand le quota est épuisé, la barre de saisie est remplacée par « Limite
  d'utilisation du jour atteinte. Vous pourrez à nouveau écrire à Amiin à 00:00 ». L'envoi et
  le micro sont refusés, et un 402 du serveur bascule l'app dans cet état.
- **Réglages › Compte** : section « Utilisation aujourd'hui » avec la jauge et l'heure de
  recharge (« Utilisation illimitée » pour un admin).

### Bugs trouvés par les tests et corrigés
- PostgreSQL renvoie la somme du jour en `Decimal` : la jauge plantait (503). Elle est
  maintenant convertie en nombre décimal.

### Tests
- `tests/test_usage.py` (13 tests) :
  - coût avec cache, somali 2× plus cher, plusieurs passes ;
  - préfixes de modèles, voix, estimation d'une réponse interrompue, journée de Djibouti ;
  - streaming complet et streaming interrompu, avec un faux client Anthropic ;
  - avec PostgreSQL : jauge, blocage (402) du chat, du streaming et de la dictée, marge de la
    lecture à voix haute, la veille non comptée, admin et mode mesure jamais bloqués.
- Résultat : **68 tests serveur passent** ; `flutter analyze` ne trouve aucune erreur ;
  `flutter test` : 22/22.

### À calibrer ensuite
- Observer le coût moyen réel d'un message (table `usage_events`) avant de descendre à 0,02 $.
- Évaluer Haiku 5.5 (10 fois moins cher que Haiku 4.5), surtout en somali.
- Côté serveur, plafonner les passes d'outils (aujourd'hui seule l'app limite à 3) : le coût est
  de toute façon compté.

---

## 2026-11-26 — Étape 4 : paramètres et appareils connectés

### Réglages branchés
- **Notifications › Activer les notifications** et **Rappels agenda** : avant, seuls les rappels
  de démarches les respectaient. Désormais, couper l'un ou l'autre annule les rappels d'agenda
  déjà programmés, et le rallumer les reprogramme. Un nouvel événement ne programme rien si
  c'est coupé (`AgendaService.cancelAllReminders` / `rescheduleAllReminders`).
- **Comportement d'Amiin › Mémoire long terme** : coupée, Amiin n'enregistre plus vos actions
  (notes, agenda, démarches) et ne reçoit plus celles déjà mémorisées.
- **Suggestions automatiques** : coupées, Amiin ne propose plus d'enregistrer une réponse en note.
- **Texte & accessibilité › Animations** : deux choix (Complètes / Réduites). « Réduites » active
  `disableAnimations` pour toute l'app : écrans sans glissement, et les animations qui
  respectent ce réglage s'arrêtent. Le réglage d'accessibilité du téléphone est aussi respecté.
  L'ancien choix « Désactivées » vaut « Réduites ».

### Réglages retirés (aucune fonctionnalité derrière)
- Notifications : Conseil du jour, Relance d'actions, Résumé hebdomadaire, Ne pas déranger.
- Comportement d'Amiin : Résumé quotidien.
- Langue & région : formats de date et d'heure (l'app est en 24 h, JJ/MM).
- **Langue de l'interface** : l'anglais est affiché « Bientôt » et l'app reste en français.
  Traduire toute l'interface est un chantier à part entière (fichiers de traduction, environ
  20 000 lignes d'écrans à reprendre). La **langue des réponses d'Amiin**, elle, fonctionne
  déjà (français, anglais, arabe, somali).

### Appareils connectés (sessions par appareil)
- **Serveur** (`auth.py`) :
  - chaque connexion ouvre une **session** (`family_id`) qui garde son identité à chaque
    renouvellement du jeton ;
  - nouvelles colonnes sur `refresh_tokens` : `family_id`, `device_label`, `created_at`,
    `family_started_at`, `revoked_reason`. Les jetons existants deviennent chacun une session ;
  - le JWT porte l'identifiant de session (`sid`) ;
  - `GET /v1/auth/sessions` liste les sessions ouvertes (appareil, connexion, dernière activité,
    « cet appareil ») ;
  - `DELETE /v1/auth/sessions/{id}` ferme la session d'un autre appareil. Il perd l'accès en
    **une minute au plus**, car `get_current_user` vérifie que la session est encore ouverte
    (cache de 60 s).
- **Faille corrigée au passage** : un jeton rejoué dans la minute qui suit une **déconnexion**
  bénéficiait du délai de grâce prévu pour les renouvellements, ce qui rouvrait la session. Le
  délai de grâce est maintenant réservé aux jetons simplement renouvelés (`revoked_reason`).
- **Changement de mot de passe** : les autres appareils sont déconnectés et celui-ci reste connecté.
- **App** :
  - l'app envoie le type d'appareil (« Android », « iPhone ou iPad », « Navigateur web »…) dans
    l'en-tête `X-Amiin-Device` ;
  - Réglages › Sécurité affiche la liste des appareils ; toucher un autre appareil le déconnecte
    après confirmation.

### Tests
- 4 nouveaux tests PostgreSQL : sessions par appareil (liste, appareil courant, renouvellement
  dans la même session, déconnexion à distance), impossibilité de fermer la session d'un autre
  compte, pas de délai de grâce après déconnexion, changement de mot de passe.
- **72 tests serveur passent**. `flutter analyze` ne trouve aucune erreur ; `flutter test` : 22/22.

---

## 2026-11-26 — Revue de sécurité et campagne de test « 20 comptes »

### Revue de sécurité (toutes les modifications de la branche)
- Rien n'atteint le seuil de confiance d'une vulnérabilité exploitable :
  - requêtes SQL toutes paramétrées ;
  - sessions et quota limités à l'utilisateur connecté ;
  - JWT HS256 imposé avec `exp` et `sub` obligatoires ;
  - codes de vérification tirés au hasard cryptographique, hachés en HMAC, séparés par usage,
    expirant au bout de 30 minutes, limités à 5 essais ;
  - pas d'énumération des comptes par « mot de passe oublié ».
- **Corrigé quand même** (faiblesse moyenne) : s'inscrire **en premier** avec une adresse de
  `ADMIN_EMAILS` donnait le rôle admin sans prouver qu'on possède la boîte mail. Le rôle n'est
  désormais accordé qu'à la vérification de l'adresse (ou au démarrage, pour une adresse déjà
  vérifiée). Tests : `test_admin_verifie_et_sans_limite`, `test_admin_non_verifie_jamais_promu`.

### Campagne de test (simulation, sans clé)
- **Outil** : `tests/simulation/` (README inclus). Il fait tourner le **vrai serveur** avec
  PostgreSQL et un SMTP local en STARTTLS. Seul Claude est remplacé par un faux serveur qui compte
  les tokens d'après la taille réelle des requêtes. Qdrant et Jina sont remplacés par une recherche
  vide. Les clés réelles n'ont pas été fournies : environnement dédié refusé, clé sur
  l'environnement par défaut refusée.
- **Paramètres** : 20 comptes joués l'un après l'autre, quota de **0,02 $ (2 centimes) par jour**,
  français uniquement, sans voix.
- **Résultat** : **364 vérifications sur 364 réussies**, aucune erreur côté serveur, 22 s au total.
  - Inscription, e-mail reçu (0,36 s en moyenne, en STARTTLS, code dans l'objet), chat refusé
    avant vérification, mauvais code refusé, vérification : 20/20.
  - 80 messages servis, 14 notes créées, 10 démarches suivies, 26 tâches en deux passes.
  - Blocage par le quota : 20/20. Le chat (normal et streaming) et la dictée renvoient 402, et la
    jauge affiche 100 %.
  - L'usage enregistré par Amiin (0,46237 $) correspond à la consommation vue par le faux Claude
    (0,46225 $) : écart de 0,03 %.
  - Suppression des 20 comptes : il ne reste aucun compte, aucune session, aucun code. La base de
    simulation a ensuite été supprimée.
- **Consommation mesurée (Haiku 4.5)** :

  | Type de message | Coût moyen |
  |---|---|
  | salutation | 0,40 centime |
  | question | 0,44 |
  | note | 0,47 |
  | démarche | 0,46 |
  | lecture des notes (2 passes) | 0,84 |
  | détail d'une démarche (2 passes) | 0,90 |
  | **moyenne** | **0,58** |

  → **3 à 5 messages par jour** avec 2 centimes. Le dépassement moyen du quota est de 0,31 centime
  (0,70 au maximum), c'est-à-dire la dernière réponse.
- **94 % du coût vient du texte envoyé à Claude** : environ 3 900 tokens par appel (consignes, catalogue
  des démarches, outils, historique). Les réponses ne pèsent que ~53 tokens.
  **Le cache de prompt ne se déclenche jamais** : le préfixe commun fait environ 3 000 tokens,
  alors que Haiku 4.5 ne met rien en cache en dessous de 4 096. À confirmer en production.

### Corrigé grâce à la campagne
- **Tâche coupée en deux par le quota** : quand le seuil était franchi entre les deux passes d'une
  tâche (« Quelles sont mes notes ? »), la seconde passe était refusée et l'utilisateur restait sur
  « Je regarde vos notes. ». La passe de suivi (résultats d'outils) a maintenant une marge de 50 %
  (`_ensure_chat_quota` dans amiin_api.py). Le contrôle du quota du chat se fait désormais dans
  l'endpoint, une fois le corps de la requête lu.

### Constats laissés en l'état (décision à prendre)
- **Suppression de compte : 10 par heure et par IP.** Pendant la campagne, 10 suppressions sur 20
  ont été refusées (429) parce que tout venait de la même IP. À Djibouti, beaucoup d'abonnés
  mobiles partagent une IP (CGNAT). La limite pourrait passer à une limite par compte.
- **`usage_events` est conservé après la suppression d'un compte** (106 lignes). Elles ne
  contiennent que l'identifiant du compte supprimé et des compteurs, aucun contenu. Il faut choisir
  entre les garder pour la facturation et les effacer avec le compte.

### Pistes d'économie (par ordre d'impact)
1. **Haiku 5.5** (0,10 $ / 0,50 $ par million de tokens, cache possible dès 512 tokens) : un message
   coûterait environ **0,04 centime** au lieu de 0,42, soit à peu près 50 messages pour 2 centimes.
   Qualité à évaluer, surtout en somali.
2. Alléger ce qui est envoyé à chaque message, en particulier le catalogue complet des 46 démarches
   injecté à chaque appel.
3. Si on reste sur Haiku 4.5, viser un préfixe de plus de 4 096 tokens pour que le cache s'active,
   ou retirer les `cache_control` inutiles.

---

## 2026-11-26 — Étape 3b : décisions de suite de campagne (limites, quota, Haiku 5.5, cache)

### Décisions et mise en œuvre
1. **Limites par compte, plus de limite par message.**
   - Supprimer le compte et changer le mot de passe : 10 fois par heure **par compte** (et non plus
     par IP), compté en base même en cas d'échec (`_account_hit`).
   - Chat, voix et dictée : **plus de plafond par minute**. C'est le quota (coût réel) qui limite.
     Il reste un garde-fou : **2 requêtes en cours au maximum par compte** (`_inflight_*`).
     Sans lui, 50 requêtes lancées en même temps passeraient toutes le contrôle du quota avant
     d'être débitées. Les admins ne sont pas concernés.
   - Restent par IP, faute de compte à ce stade : inscription (20/h), connexion (30/min),
     mot de passe oublié (10/h), code de réinitialisation (20/h), renouvellement de session (60/min).
2. **Le quota survit à la suppression du compte.**
   - Les lignes `usage_events` sont conservées.
   - Le quota est rattaché à l'**adresse e-mail normalisée et hachée** (HMAC, colonne
     `quota_key`), et non plus au compte : on retire `+étiquette`, et les points pour Gmail.
   - Supprimer puis recréer un compte avec la même adresse, ou une variante, ne remet donc pas
     le compteur à zéro. Les lignes existantes ont été rattachées au démarrage.
   - Secret : `QUOTA_KEY_SECRET` (par défaut `JWT_SECRET_KEY`), **à ne jamais changer**.
3. **Haiku 5.5 pour le français et l'anglais** (`CLAUDE_MODEL`, par défaut `claude-haiku-5-5`).
   La reformulation suit le même modèle (`CLAUDE_EXPAND_MODEL`). Somali : Sonnet 5 inchangé.
   Arabe : Haiku 4.5 tant que Haiku 5.5 n'y est pas évalué (`CLAUDE_MODEL_AR`). Adaptations
   imposées par Haiku 5.5 (documentation de migration Anthropic) :
   - `temperature` est refusée (400) : retirée pour ce modèle, y compris dans la reformulation ;
   - réflexion coupée (`thinking: disabled`) et effort bas, ce qui convient à une conversation.
     Cela évite aussi de devoir renvoyer les blocs de réflexion à la 2e passe d'outils ;
   - le texte de la reformulation est lu par type de bloc, et non plus comme premier bloc ;
   - refus de sécurité (`stop_reason: refusal`, sans modèle de repli côté serveur) : la réponse
     affichée est « Désolé, je ne peux pas répondre à cette demande… » (ou en anglais).
4. **Catalogue des démarches en cache.** Il **était déjà marqué** pour le cache (premier bloc
   système, avec les consignes), mais Haiku 4.5 ne met rien en cache sous 4 096 tokens.
   Haiku 5.5 met en cache dès 512 tokens. **86 % du texte envoyé est désormais lu depuis le cache**
   (10 fois moins cher). Le cache est commun à tous les utilisateurs, car le préfixe est identique.

### Campagnes comparatives (simulation, 20 comptes chacune, quota 0,02 $/jour)
Faux Claude rendu plus fidèle : tokeniseur de Haiku 5.5 (+30 % de tokens), cache dès 512 tokens,
**rejet (400) des paramètres interdits par Haiku 5.5**. Aucun rejet n'a eu lieu, ce qui valide
l'adaptation de la requête. Contrôle ajouté : supprimer puis recréer 3 comptes avec la même adresse
doit les laisser bloqués.

| | A : Haiku 4.5, français | B : Haiku 5.5, français | C : Haiku 5.5, anglais |
|---|---|---|---|
| Vérifications | 364/364 | 364/364 | 364/364 |
| Messages servis par compte (2 centimes) | **4** (3 à 5) | **84** (82 à 85) | **86** (84 à 87) |
| Coût moyen d'un message | 0,578 centime | **0,024 centime** | **0,023 centime** |
| Question simple / tâche en 2 passes | 0,44 / 0,84–0,90 c | 0,018 / 0,035–0,038 c | 0,017 / 0,034–0,038 c |
| Texte envoyé par appel | ~3 900 tokens, 0 % en cache | ~5 450 tokens, **86 % en cache** | ~5 575 tokens, 87 % en cache |
| Recréation de compte bloquée | 3/3 | 3/3 | 3/3 |
| Comptes supprimés, données restantes | 20/20, aucune | 20/20, aucune | 20/20, aucune |
| Erreurs serveur | 0 | 0 | 0 |

- **Environ 24 fois moins cher par message, donc environ 21 fois plus de messages par jour pour le même budget.**
- Les 20 suppressions passent maintenant d'un coup (limite par compte).
- L'écart entre le coût enregistré et le faux Claude (0,6 % en B et C) correspond aux
  embeddings Jina, que seul Amiin compte.
- **Limite de la simulation** : les réponses sont fictives. La **qualité** de Haiku 5.5 en
  français et en anglais reste à vérifier avec la vraie clé.

### Tests
- 5 nouveaux tests :
  - normalisation et hachage des adresses ;
  - suppression puis recréation (même adresse et variante `+bis`) toujours bloquée ;
  - requêtes simultanées par compte ;
  - paramètres de Haiku 5.5 ;
  - lecture de la reformulation par type de bloc.
- **78 tests serveur passent** ; `flutter analyze` ne trouve aucune erreur.
- App : le message 429 dit maintenant « Une réponse est déjà en préparation ».

---

## 2026-11-26 — Compilation de l'APK, pull request, Play Integrity

### APK compilé et vérifié (validation de l'étape 1)
- **Outils** : SDK Android (plateforme 36, build-tools 36.0.0, NDK 28.2) installé ici, et
  **Flutter 3.38.10**, la version compatible avec le projet (Gradle 8.14). Flutter 3.50 exige
  Gradle 9.3 : on ne met pas le projet à niveau pour l'outil.
- **Compilation release réussie** avec `tool/build_release.sh apk` et une clé de test jetable
  (pas la clé d'upload). Résultat : APK de 62 Mo.
- **Vérifié dans l'APK** :
  - paquet `dj.amiin.app` (version 1.1.0, code 2), SDK cible 36 ;
  - `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` présent ;
  - `USE_EXACT_ALARM` absent ;
  - signature valide ;
  - R8 actif (`mapping.txt` produit), avec `MainActivity`, `AmiinBriefWidgetProvider` et les
    modèles de `flutter_local_notifications` conservés ;
  - symboles Dart séparés dans `symbols/1.1.0+2/` ;
  - **sans `key.properties`, la compilation s'arrête avec le message prévu**.
- Le téléchargement depuis Maven Central échoue parfois (429 « trop de requêtes ») : il suffit de
  relancer.
- Il reste les tests de l'APK sur un téléphone (au retour).

### Pull request
- **#12** (brouillon) : branche `ccr-3074fd75-c0o8hp` vers `master`. À ne pas fusionner avant les tests
  de bout en bout avec les vraies clés et les tests sur téléphone.

### Play Integrity (étape 5)
- **But** : n'accepter les inscriptions et les connexions que depuis la **vraie app**, installée
  depuis le Play Store, sur un appareil Android intègre. Cela bloque les scripts et les apps
  modifiées qui créeraient des comptes en masse pour consommer le quota gratuit.
- **App** :
  - `MainActivity.kt` : canal `dj.amiin.app/integrity`, API Play Integrity « Standard »,
    bibliothèque `com.google.android.play:integrity:1.6.0`. Le fournisseur est préparé une fois,
    puis préparé à nouveau s'il expire ;
  - `lib/services/integrity_service.dart` : jeton lié à l'action et à l'adresse (empreinte
    SHA-256 de `action:adresse`), envoyé dans `X-Amiin-Integrity` à l'inscription et à la
    connexion ;
  - hors Android, sans numéro de projet (`AMIIN_CLOUD_PROJECT_NUMBER`) ou en cas d'échec,
    aucun jeton n'est envoyé.
- **Serveur** (`integrity.py`) :
  - le jeton est déchiffré par l'API Google (compte de service, `google-auth`) ;
  - vérifications : paquet, empreinte, jeton de moins de 5 minutes, app reconnue par Play
    (`PLAY_RECOGNIZED`), appareil intègre (`MEETS_DEVICE_INTEGRITY`).
- **Modes** (`INTEGRITY_MODE`) :
  - `off` (défaut) ;
  - `report` : vérifie et journalise sans bloquer ;
  - `enforce` : refuse l'inscription ou la connexion (403, en-tête `X-Amiin-Error: integrity_required`).
- **Exceptions** : les adresses `ADMIN_EMAILS` ne sont jamais bloquées. Si Google est
  injoignable, on laisse passer : une panne de notre côté ne doit pas bloquer les utilisateurs.
- **Vérification seulement à l'inscription et à la connexion**, pas à chaque message : le quota
  gratuit de Google (environ 10 000 vérifications par jour) suffit. Le résultat est enregistré
  sur la session (`refresh_tokens.integrity`) et `GET /v1/auth/sessions` indique `verified`.

### Tests
- `tests/test_integrity.py` (12 tests) :
  - empreinte identique à celle de l'app ;
  - verdict valide ;
  - paquet, app ou appareil refusés ;
  - jeton d'une autre adresse ou d'une autre action ;
  - jeton périmé ;
  - modes off, report et enforce, exception admin, panne de Google ;
  - inscription et connexion en `enforce` contre PostgreSQL.
- **87 tests serveur passent.**
- `flutter analyze` (Flutter 3.38.10) : aucun problème sur le code modifié. Un « getter
  récursif » de `user_scope.dart` a été réécrit en boucle. `flutter test` : 22/22.
