# Guide complet — Amiin

> **Amiin — Guide universel de Djibouti**
> Version du guide : juillet 2026 (état v1)

---

# PARTIE 1 — Présentation d'Amiin

## 1.1 Qu'est-ce qu'Amiin ?

Amiin est une application mobile d'assistance intelligente conçue pour Djibouti. Elle réunit en un seul endroit deux fonctions habituellement séparées :

1. **Un guide d'information fiable sur Djibouti** — démarches administratives, droit djiboutien, annuaire des services publics et privés. Amiin répond à partir d'une base de connaissances documentée et sourcée (les codes juridiques officiels du pays, les sites gouvernementaux), et non à partir de connaissances génériques d'IA qui pourraient être fausses ou datées.

2. **Un secrétariat personnel** — un assistant conversationnel (texte et voix) capable de gérer votre agenda, vos notes et vos rappels par simple demande en langage naturel : *« Ajoute un rendez-vous chez le médecin demain à 10h »*, *« Note ça : appeler le plombier jeudi »*, *« C'est quoi mon planning cette semaine ? »*.

Cette **dualité information / secrétariat** structure toute l'application, jusque dans son design : les fonctions de secrétariat (chat, agenda, notes) sont signalées en **turquoise** (Turquoise Tadjourah), les fonctions d'information (annuaire, démarches) en **ocre** (Ocre des Dunes). Une « ligne d'horizon » animée en haut de la barre de navigation change de couleur selon le mode actif.

### À qui s'adresse Amiin ?

- **Aux citoyens djiboutiens** qui veulent savoir comment obtenir un acte de naissance, renouveler un passeport, créer une entreprise, connaître leurs droits (travail, famille, pénal…) sans se déplacer ni chercher dans des PDF de 300 pages.
- **Aux résidents et nouveaux arrivants** qui découvrent l'administration djiboutienne.
- **À toute personne** qui souhaite un assistant personnel vocal en français pour organiser son quotidien (rendez-vous, notes, rappels).

## 1.2 La vision : ce qu'Amiin sera

L'objectif final est de faire d'Amiin **l'assistant de référence du quotidien à Djibouti** :

- **Le réflexe « démarche »** : avant d'aller au guichet, on demande à Amiin quels documents apporter, combien ça coûte, combien de temps ça prend — puis on suit sa démarche étape par étape dans l'app.
- **Un juriste de poche** : des réponses sourcées article par article sur l'ensemble du droit djiboutien (travail, famille, commerce, pénal, route, douanes, impôts, investissements…).
- **Un annuaire national vivant** : tous les services publics et privés, géolocalisés, avec contact direct (appel, itinéraire) et favoris.
- **Un vrai secrétaire vocal** : conversation naturelle mains libres — on parle, Amiin répond à voix haute, crée les rendez-vous, les notes et les rappels tout seul.
- **Multilingue** : l'interface existe en français et anglais ; l'assistant est prévu pour répondre aussi en **arabe** et en **somali** (options déjà présentes dans les réglages).
- **Un modèle économique durable** : une offre **Amiin Pro** (abonnement) est prévue — l'écran d'abonnement existe déjà, la souscription sera activée dans une version ultérieure.

## 1.3 Comment ça marche (architecture)

| Composant | Technologie | Rôle |
|---|---|---|
| Application mobile | Flutter (Dart) | Interface, données locales, voix |
| Backend API | FastAPI (Python), hébergé sur Render | Chat IA, RAG, annuaire, synthèse vocale, comptes |
| Intelligence | Claude (Anthropic) — modèle Haiku 4.5 | Compréhension, rédaction, appel d'outils |
| Base de connaissances | Qdrant (base vectorielle) + embeddings Jina v3 | Recherche sémantique dans les documents djiboutiens |
| Voix (sortie) | Edge TTS (voix neuronales Microsoft, cloud) + TTS local du téléphone | Lecture des réponses à voix haute |
| Voix (entrée) | Reconnaissance vocale du téléphone (speech-to-text) | Dictée des messages |
| Comptes utilisateurs | PostgreSQL + JWT | Inscription, connexion, sessions |
| Données personnelles | Hive (base locale **chiffrée** sur le téléphone) | Agenda, notes, historique de chat |

**Points d'architecture importants :**

- **Architecture « tool-first »** : l'IA dispose d'outils (créer/lire/modifier/supprimer un événement ou une note, rechercher dans l'annuaire, lancer une démarche) qu'elle appelle elle-même quand la demande l'exige. Une question simple ne déclenche qu'un seul appel (réponse rapide, < 3 s au premier mot) ; une question sur l'agenda déclenche la récupération des données puis la réponse.
- **RAG sourcé** : pour les questions juridiques et administratives, le backend cherche d'abord les passages pertinents dans la base vectorielle (codes, sites officiels), puis l'IA rédige à partir de ces extraits. Si l'information n'est pas dans la base, Amiin le dit plutôt que d'inventer.
- **Vie privée** : agenda, notes et historique de conversation restent **sur le téléphone** (Hive chiffré via le stockage sécurisé du système). Le serveur ne stocke pas votre agenda.
- **Contexte injecté** : Amiin connaît la date, l'heure et la météo locale, ce qui lui permet de répondre à « on est quel jour ? » ou « il fait chaud aujourd'hui ? » sans outil.

## 1.4 La base de connaissances

La base documentaire indexée couvre notamment :

- **Codes juridiques djiboutiens** : Code civil (2018), Code de la famille, Code du travail, Code pénal, Code de procédure civile (2018), Code de commerce, Code de la route, Code des douanes, Code général des impôts, Code des marchés publics, Code de l'environnement, Code des investissements, Code des pêches, Code des zones franches, Code minier, Code pétrolier, Code de l'arbitrage international.
- **Contenus officiels en ligne** : portail e-gouvernement (fiches démarches), Banque centrale de Djibouti, réglementation des métiers.
- **Annuaire enrichi** : services publics et privés avec catégories, adresses, contacts et coordonnées GPS.
- **Catalogue de démarches** : fiches structurées (étapes, documents requis, délais, coûts) embarquées dans l'app.

## 1.5 État d'avancement (juillet 2026)

### ✅ Fonctionnel aujourd'hui (v1 finalisée)

- Chat IA complet : texte, streaming des réponses, annulation en cours, copie, renvoi d'un message, historique persistant, séparateurs de date.
- Entrée vocale (dictée) et sortie vocale : TTS local ou voix cloud Edge TTS, lecture automatique configurable, mode conversationnel.
- Agenda : création manuelle et via l'IA, consultation, modification, suppression, catégories, rappels par notifications locales, badge du nombre d'événements du jour.
- Notes : création manuelle et via l'IA, tags, épinglage, recherche ; suggestion automatique de note après une réponse procédurale (ex. les étapes d'un renouvellement de passeport).
- Annuaire : navigation par catégories, recherche, services à proximité (géolocalisation), favoris, fiche détaillée avec actions de contact.
- Démarches : catalogue consultable, fiche détaillée, lancement et suivi d'une démarche personnelle.
- Comptes : inscription, connexion, déconnexion (JWT, base PostgreSQL).
- Personnalisation : 4 thèmes, taille de texte, langue de l'interface (fr/en), langue de l'assistant (fr/en/ar/so), réglages de l'assistant (suggestions, mode vocal, vitesse, choix de la voix cloud).
- Robustesse : bannière de connectivité, messages d'erreur en français, timeout géré, backend surveillé par health check.
- Design finalisé : refonte complète « palette Djibouti » (juin 2026) — Encre de Nuit, Sel d'Assal, Turquoise Tadjourah, Ocre des Dunes, Corail ; typographies Inter, DM Sans et Space Mono.

### 🚧 Présent mais non activé (« bientôt disponible »)

- **Amiin Pro** : l'écran d'abonnement/facturation existe, la souscription n'est pas encore ouverte.
- Certaines options du compte (gestion avancée) et de la sécurité affichent « fonctionnalité à venir ».
- Le guide intégré dans « À propos » renvoie « Guide bientôt disponible » — ce document a vocation à le remplir.

### 🔮 Prévu ensuite

- Réponses de l'assistant en arabe et en somali (les options existent, la qualité doit être validée).
- Enrichissement continu de la base (nouvelles fiches démarches, annuaire élargi aux régions).
- Publication sur les stores (l'app se distribue pour l'instant en APK).

---

# PARTIE 2 — Guide d'utilisation

## 2.1 Installation

### Prérequis

- Un téléphone **Android 5.0 ou plus récent** (min SDK 21). Le projet compile aussi pour iOS, web et Windows, mais Android est la cible principale.
- Une **connexion Internet** pour le chat, l'annuaire distant, la voix cloud et le compte. (Agenda et notes fonctionnent hors ligne : ils sont stockés sur le téléphone.)
- Pour l'entrée vocale : autoriser le **micro**. Pour « services à proximité » : autoriser la **localisation**.

### Installer depuis l'APK

1. Récupérez le fichier APK fourni par l'équipe Amiin.
2. Sur le téléphone, autorisez l'installation de sources inconnues si demandé.
3. Ouvrez l'APK et installez.

### Compiler soi-même (développeurs)

```bash
cd amiin_app_flutter
flutter pub get
flutter run                     # debug, backend de production par défaut
# ou pour un APK de production :
flutter build apk --dart-define=AMIIN_API_URL=https://amiin.onrender.com/v1
```

Le backend par défaut est `https://amiin.onrender.com/v1`. Pour pointer vers un serveur local pendant le développement : `--dart-define=AMIIN_API_URL=http://10.0.2.2:8000/v1` (émulateur Android).

> Note : le backend est hébergé sur l'offre gratuite de Render — après une période d'inactivité, la **première requête peut prendre 30–60 s** (réveil du serveur). Les suivantes sont rapides.

## 2.2 Premier lancement : créer son compte

1. L'app s'ouvre sur l'**écran de démarrage** (logo Amiin), puis vous dirige vers la **connexion**.
2. Pas encore de compte ? Touchez **Créer un compte** : nom, e-mail, mot de passe.
3. Une fois connecté, vous arrivez sur l'**Accueil**. Vous restez connecté d'une session à l'autre ; la déconnexion se fait dans Paramètres → Compte.

## 2.3 Se repérer : la navigation

La barre du bas comporte **6 onglets** :

| Onglet | Couleur | Rôle |
|---|---|---|
| 🏠 **Accueil** | neutre | Vue d'ensemble : salutation, accès rapides, prochains rendez-vous, dernières notes |
| 💬 **Amiin** | turquoise | Le chat avec l'assistant (cœur de l'app) |
| 📅 **Agenda** | turquoise | Vos rendez-vous et rappels (badge rouge = nombre d'événements aujourd'hui) |
| 📝 **Notes** | turquoise | Vos notes personnelles |
| 👥 **Annuaire** | ocre | Les services de Djibouti (contacts, adresses, favoris) |
| 📋 **Démarches** | ocre | Le catalogue des démarches administratives et vos démarches en cours |

- La **ligne d'horizon** colorée au-dessus de la barre indique le mode : turquoise = secrétariat, ocre = information.
- Le bouton **retour** du téléphone ramène toujours à l'Accueil depuis un autre onglet ; depuis l'Accueil, il ferme l'app.
- L'engrenage en haut de l'Accueil ouvre les **Paramètres**.
- Une **bannière corail** apparaît en haut de l'écran si la connexion Internet est perdue.

## 2.4 Le chat Amiin (onglet « Amiin »)

C'est l'interface principale : presque tout ce que fait l'app peut se faire en le demandant ici.

### Écrire ou parler

- **Texte** : tapez votre message, touchez Envoyer. La réponse s'affiche en streaming (mot à mot). Pendant la génération, le bouton devient **Stop** : touchez-le pour interrompre.
- **Voix** : touchez l'icône **micro** — animation de pulsation, état « Écoute… ». Parlez : le texte se transcrit dans le champ. Le micro s'arrête seul après ~10 s de silence, ou touchez-le à nouveau. Envoyez ensuite normalement.
- **Réponse vocale** : selon vos réglages (voir 2.9), Amiin peut lire ses réponses à voix haute — pour toutes les réponses (« Lecture auto ») ou seulement quand vous lui avez parlé au micro (« Conversationnel »). Toucher le micro pendant la lecture l'interrompt.

### Gestes utiles

- **Appui long sur un message** → menu : **Copier** (n'importe quel message) ; **Retenter** (sur vos propres messages : remplit le champ et renvoie).
- L'**historique est conservé** après fermeture de l'app, avec des séparateurs de date entre les journées. Amiin garde le contexte des derniers échanges : vous pouvez enchaîner « *Et pour un renouvellement ?* » après une première question.

### Ce que vous pouvez demander — panorama complet

**S'informer (mode information — réponses sourcées) :**
- Démarches : « Comment obtenir un acte de naissance ? », « Quels documents pour renouveler mon passeport ? », « Combien coûte la création d'une SARL et combien de temps ça prend ? »
- Droit : « C'est quoi la durée légale du travail à Djibouti ? », « À quel âge peut-on se marier ? », « Quelles sont les règles de licenciement ? », « Que dit le code de la route sur… ? »
- Services : « Quel est le numéro de la mairie de Djibouti ? », « Où est l'hôpital le plus proche ? »
- Contexte : « On est quel jour ? », « Il fait chaud aujourd'hui ? » (Amiin connaît la date et la météo locale).

**Gérer son agenda (mode secrétariat) :**
- Créer : « Ajoute un RDV chez le médecin demain à 10h », « Réunion au bureau lundi 14h, salle A », « RDV préfecture jeudi 9h, apporter CNI et justificatif de domicile », « Mets un rappel 30 minutes avant ».
- Consulter : « C'est quoi mon agenda aujourd'hui ? », « Qu'est-ce que j'ai cette semaine ? », « Quel est mon prochain rendez-vous ? », « Suis-je libre vendredi après-midi ? »
- Modifier / supprimer : « Décale mon RDV du 10 juin à 15h », « Change le lieu de mon RDV de demain », « Supprime mon RDV de demain matin ». S'il y a ambiguïté, Amiin demande lequel.
- Chaque action réussie est confirmée par un **toast** (« Événement créé : … ») et une **puce d'action** dans la conversation.

**Gérer ses notes :**
- « Note ça : appeler le plombier jeudi », « Fais-moi une note avec les étapes pour renouveler mon passeport », « Crée une note “Budget vacances” avec le tag finance », « Épingle cette note ».
- Consulter : « Montre-moi mes notes », « Dans mes notes, j'ai quelque chose sur le passeport ? », « Mes notes avec le tag finances ».
- Modifier / supprimer : « Ajoute à ma note passeport qu'il faut 2 photos », « Supprime la note sur le budget ».
- Les notes créées ou modifiées apparaissent sous forme de **carte** directement dans la bulle de réponse.

**Suggestion automatique de note :** après une réponse longue et procédurale (ex. les étapes d'une démarche), Amiin propose « Je peux créer une note avec ces étapes ». **Oui** → la note est créée instantanément ; **Non** → la suggestion disparaît. (Désactivable dans les réglages de l'assistant.)

**Lancer une démarche :** « Lance la démarche de renouvellement de passeport » → la démarche apparaît dans votre suivi (onglet Démarches).

## 2.5 L'Agenda

- **Vue calendrier** de vos événements, avec catégories (santé, administratif, travail…) attribuées automatiquement ou manuellement.
- **Créer à la main** : bouton de création → titre, date/heure, lieu, description, rappel. (Ou passez par le chat, c'est souvent plus rapide.)
- **Fiche événement** : touchez un événement pour voir le détail, le modifier ou le supprimer.
- **Rappels** : notifications locales du téléphone à l'heure choisie (ex. 30 min avant).
- **Badge** : l'icône Agenda de la barre de navigation affiche en rouge le nombre d'événements du jour.
- Les données restent **sur votre téléphone** (stockage chiffré), disponibles hors ligne.

## 2.6 Les Notes

- **Liste** de vos notes avec recherche ; les notes **épinglées** remontent en tête.
- **Créer / éditer à la main** : bouton de création → titre, contenu, **tags** pour classer (finance, santé, démarches…).
- **Fiche note** : lecture, édition, épinglage, suppression.
- Comme l'agenda : stockage local chiffré, utilisable hors ligne, et entièrement pilotable par le chat.

## 2.7 L'Annuaire

- **Parcourir par catégories** (santé, administration, éducation, etc.) ou **rechercher** un service par nom.
- **À proximité** : avec la localisation activée, affiche les services proches de vous.
- **Fiche service** : adresse, téléphone, catégorie — avec actions directes (appeler, ouvrir l'itinéraire).
- **Favoris** : marquez vos services fréquents pour les retrouver en un geste.
- Astuce : demander au chat (« le numéro de la pharmacie de garde ? ») interroge le même annuaire.

## 2.8 Les Démarches

- **Catalogue** de fiches démarches : pour chacune, les **étapes**, les **documents requis**, les **délais** et **coûts** connus.
- **Fiche démarche** : consultez le détail avant de vous déplacer.
- **Lancer une démarche** : depuis la fiche ou via le chat. Elle passe dans **vos démarches en cours** avec un écran de **suivi** où vous avancez étape par étape (documents réunis, dépôt du dossier, retrait…).

## 2.9 Les Paramètres (engrenage sur l'Accueil)

| Section | Contenu |
|---|---|
| **Profil** | Vos informations personnelles |
| **Compte** | Gestion du compte, **déconnexion** (certaines options avancées : à venir) |
| **Sécurité** | Mot de passe et options de sécurité (partiellement à venir) |
| **Assistant** | Suggestions automatiques de notes ; **mode vocal** : Aucun / Lecture auto (chaque réponse est lue) / Conversationnel (Amiin ne parle que si vous avez parlé) ; **vitesse de lecture** (×0,5–×2) ; **voix cloud Edge TTS** : voix neuronales Microsoft, plus naturelles que celles du téléphone (compter 2–5 s de délai avant la lecture) avec choix de la voix |
| **Apparence** | 4 thèmes : **Sel d'Assal** (clair turquoise), **Aurore** (clair ocre), **Dusk** (sombre ocre), **Encre de Nuit** (sombre turquoise) |
| **Texte** | Taille du texte |
| **Notifications** | Rappels d'agenda et alertes |
| **Langue** | Interface : français / anglais. Réponses de l'assistant : français / anglais / arabe / somali |
| **Confidentialité** | Gestion des données personnelles |
| **Abonnement** | Offre **Amiin Pro** — bientôt disponible |
| **À propos** | Version, informations sur l'app |

## 2.10 Hors ligne, erreurs et limites

- **Sans Internet** : agenda et notes restent consultables et modifiables (manuellement) ; le chat, l'annuaire distant, la voix cloud et les démarches nécessitent une connexion. Une bannière corail vous prévient.
- **Serveur lent au réveil** : première requête après une longue inactivité = 30–60 s (hébergement gratuit). Réessayez, puis tout est fluide.
- **Timeout** : au-delà de 90 s sans réponse, un message d'erreur clair s'affiche ; votre message peut être renvoyé (appui long → Retenter).
- **Fiabilité des réponses** : sur le droit et les démarches, Amiin s'appuie sur des textes officiels indexés. Hors de sa base, il le signale plutôt que d'inventer. Ses réponses restent **informatives** : pour un litige, consultez un professionnel.
- **Style des réponses** : volontairement courtes et directes (style messagerie), avec listes numérotées uniquement quand des étapes le justifient.

## 2.11 Récapitulatif : 10 usages types

1. « Comment renouveler mon passeport ? » → étapes sourcées + proposition de note.
2. « Lance la démarche » → suivi étape par étape dans l'onglet Démarches.
3. « Ajoute le RDV préfecture jeudi 9h avec rappel 1h avant » → événement + notification.
4. « Suis-je libre vendredi après-midi ? » → vérification réelle de votre agenda.
5. « Note : acheter 2 photos d'identité et timbre fiscal » → note créée, retrouvable par recherche.
6. « Le numéro de la mairie ? » → contact direct, appel en un geste depuis l'annuaire.
7. « L'hôpital le plus proche ? » → géolocalisation + fiche service.
8. « C'est quoi la durée légale du travail ? » → réponse sourcée du Code du travail.
9. Mains libres : micro + mode Conversationnel → vous parlez, Amiin répond à voix haute.
10. « Qu'est-ce que j'ai aujourd'hui ? » chaque matin → votre journée résumée (aussi visible d'un coup d'œil sur l'Accueil).

---

*Document rédigé à partir du code source de l'application (v1, juillet 2026). À mettre à jour à chaque évolution majeure.*
