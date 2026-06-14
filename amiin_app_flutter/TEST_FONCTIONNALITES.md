# Document de test — Amiin App
> Version post-refactoring tool-first (2026-06-09)

Légende : ✅ Passé | ❌ Échoué | ⚠️ Partiel | 🔁 À retester

---

## 1. Chat — Interface de base

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 1.1 | Envoi message texte | Taper un message, appuyer Envoyer | Message utilisateur s'affiche, état "Recherche…" puis "Amiin réfléchit…", réponse streame | |
| 1.2 | Annulation mid-stream | Envoyer un message, appuyer Stop pendant le stream | Stream s'arrête, bouton Send réapparaît | |
| 1.3 | Annulation en phase loading | Envoyer un message, appuyer Stop avant le 1er token | État revient à l'état initial | |
| 1.4 | Long press → Copier | Long press sur n'importe quel message | Bottom sheet s'ouvre avec option "Copier", toast "Message copié" | |
| 1.5 | Long press → Retenter | Long press sur un message **utilisateur** | Option "Retenter" visible, tap remplit le champ et renvoie | |
| 1.6 | Long press message agent | Long press sur une bulle Amiin | Option "Retenter" **non visible** (seulement sur messages user) | |
| 1.7 | Scroll automatique | Réponse longue | La liste scroll automatiquement vers le bas au fur et à mesure | |
| 1.8 | Scroll initial | Ouvrir l'écran avec historique | Scroll positionné sur le dernier message dès l'ouverture | |
| 1.9 | Message vide | Appuyer Envoyer sans texte | Rien ne se passe | |
| 1.10 | Double envoi | Appuyer deux fois rapidement sur Envoyer | Un seul message envoyé | |
| 1.11 | Séparateur de date | Messages de jours différents dans l'historique | Séparateur "lundi 9 juin 2026" visible entre les groupes | |

---

## 2. Entrée/Sortie vocale

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 2.1 | Activation micro | Tap sur l'icône micro | Animation pulsation rouge, état "Écoute…" | |
| 2.2 | Désactivation micro | Tap à nouveau sur micro | Animation s'arrête | |
| 2.3 | Reconnaissance parole | Parler après activation | Texte transcrit dans le champ | |
| 2.4 | Silence → arrêt auto | Rester silencieux 10s | Le micro s'arrête automatiquement | |
| 2.5 | Envoi après vocal | Taper micro, parler, appuyer Envoyer | Message vocal envoyé correctement | |
| 2.6 | TTS réponse | Recevoir une réponse d'Amiin | Réponse lue à voix haute en français | |
| 2.7 | TTS interrompu | Tap micro pendant que TTS parle | TTS s'arrête | |
| 2.8 | TTS contenu markdown | Réponse avec `**gras**` ou `## titre` | Markdown nettoyé, TTS lit le texte brut | |

---

## 3. Agenda — Création d'événements (via IA)

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 3.1 | Créer RDV simple | "Ajoute un RDV chez le médecin demain à 10h" | Amiin confirme, toast "Événement créé : …", chip `create_event` visible | |
| 3.2 | Créer avec lieu | "Réunion au bureau lundi 14h, salle A" | Événement avec location créé | |
| 3.3 | Créer avec description | "RDV préfecture jeudi 9h, apporter CNI et justificatif domicile" | Événement avec description détaillée | |
| 3.4 | Créer avec rappel | "Rappel dans 30 minutes avant le RDV" | reminder_minutes = 30 | |
| 3.5 | Créer événement passé | "J'avais un RDV hier à 14h" | Créé avec date passée (pas de blocage) | |
| 3.6 | Catégorie auto | "Rendez-vous médecin" vs "Réunion administrative" | Catégorie health vs admin correcte | |

---

## 4. Agenda — Consultation (get_events — NOUVEAU)

> Ces tests valident la nouvelle architecture tool-first. Observer : état "Récupération des données…" entre les deux appels.

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 4.1 | Agenda aujourd'hui (vide) | "C'est quoi mon agenda aujourd'hui ?" (aucun RDV) | "Aucun événement pour cette période" | |
| 4.2 | Agenda aujourd'hui (avec RDV) | Créer un RDV aujourd'hui, puis demander l'agenda | Amiin liste les RDV avec heure et titre | |
| 4.3 | Agenda cette semaine | "Qu'est-ce que j'ai cette semaine ?" | get_events appelé sur 7 jours, liste correcte | |
| 4.4 | Prochain RDV | "Quel est mon prochain rendez-vous ?" | get_events appelé, retourne le prochain événement | |
| 4.5 | Agenda du mois | "C'est quoi mon planning ce mois-ci ?" | get_events sur ~30 jours | |
| 4.6 | Disponibilité | "Suis-je libre vendredi après-midi ?" | Amiin vérifie get_events et répond en fonction | |
| 4.7 | Agenda après création | Créer un RDV puis demander l'agenda | Le nouveau RDV apparaît (données fraîches de Hive) | |
| 4.8 | Status intermédiaire | Observer pendant une requête agenda | "Récupération des données…" visible entre les deux appels | |

---

## 5. Agenda — Modification et suppression

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 5.1 | Modifier heure | "Décale mon RDV du 10 juin à 15h au lieu de 10h" | update_event avec bon ID, toast "Événement modifié" | |
| 5.2 | Modifier lieu | "Change le lieu de mon RDV de demain" | Location mise à jour | |
| 5.3 | Supprimer événement | "Supprime mon RDV de demain matin" | Amiin consulte agenda, identifie l'ID, delete_event, toast "Événement supprimé" | |
| 5.4 | Supprimer événement ambigu | "Supprime mon RDV" (plusieurs candidats) | Amiin demande lequel | |
| 5.5 | Supprimer événement inexistant | "Supprime le RDV du 1er mars" (n'existe pas) | Amiin indique qu'il n'existe pas | |

---

## 6. Notes — Création et modification (via IA)

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 6.1 | Créer note simple | "Note ça : appeler le plombier jeudi" | create_note, ChatNoteCard apparaît dans la bulle | |
| 6.2 | Créer note structurée | "Fais-moi une note avec les étapes pour renouveler mon passeport" | Note créée avec contenu structuré, ChatNoteCard visible | |
| 6.3 | Note avec tags | "Crée une note 'Budget vacances' avec le tag finance" | tags: ["finance"] | |
| 6.4 | Note épinglée | "Épingle cette note" | is_pinned: true | |
| 6.5 | Modifier note | "Mets à jour ma note sur le passeport, ajoute qu'il faut 2 photos" | update_note avec bon ID | |
| 6.6 | Supprimer note | "Supprime la note sur le budget" | delete_note, toast "Note supprimée" | |
| 6.7 | ChatNoteCard — update | Modifier une note existante | Badge "Modifiée" visible dans la ChatNoteCard | |

---

## 7. Notes — Consultation (get_notes — maintenant fonctionnel)

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 7.1 | Lister toutes les notes (vide) | "Quelles sont mes notes ?" (aucune note) | "Aucune note trouvée" | |
| 7.2 | Lister toutes les notes | Créer 2-3 notes, puis "Montre-moi mes notes" | Amiin liste les titres et aperçus | |
| 7.3 | Recherche par mot-clé | "Dans mes notes, est-ce que j'ai quelque chose sur le passeport ?" | get_notes avec query="passeport" | |
| 7.4 | Recherche par tag | "Mes notes avec le tag finances" | get_notes avec tag="finances" | |
| 7.5 | Note après création | Créer une note puis demander la liste | La nouvelle note apparaît | |

---

## 8. Suggestion automatique de note

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 8.1 | Réponse procédurale longue | "Comment renouveler mon passeport ?" | Suggestion "Je peux créer une note avec ces étapes" apparaît sous la réponse | |
| 8.2 | Accepter la suggestion | Tap "Oui" sur la suggestion | Note créée, ChatNoteCard apparaît, suggestion disparaît | |
| 8.3 | Refuser la suggestion | Tap "Non" sur la suggestion | Suggestion disparaît, pas de note créée | |
| 8.4 | Pas de suggestion pour courte réponse | "C'est quoi la capitale de Djibouti ?" | Aucune suggestion de note | |
| 8.5 | Pas de suggestion si note déjà créée | Amiin crée lui-même une note | Suggestion ne s'affiche pas (hasNoteAction = true) | |

---

## 9. Démarches administratives

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 9.1 | Info démarche | "Comment faire pour obtenir un acte de naissance ?" | Réponse RAG avec les étapes | |
| 9.2 | Lancer démarche | "Lance la démarche de renouvellement de passeport" | start_demarche appelé, confirmation | |
| 9.3 | Documents requis | "Quels documents pour créer une entreprise à Djibouti ?" | Réponse RAG précise | |
| 9.4 | Délais et coûts | "Combien ça coûte et combien de temps ça prend ?" | Données RAG si disponibles | |

---

## 10. Annuaire des services

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 10.1 | Recherche service | "Quel est le numéro de la mairie de Djibouti ?" | search_services + réponse directe avec contact | |
| 10.2 | Recherche par catégorie | "Où est l'hôpital le plus proche ?" | search_services category=sante | |
| 10.3 | Service inexistant | "Numéro du consulat de Chine" | Amiin indique ne pas avoir l'info ou suggère une alternative | |

---

## 11. Base de connaissances RAG

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 11.1 | Question juridique simple | "C'est quoi la durée légale du travail à Djibouti ?" | Réponse sourcée du Code du Travail | |
| 11.2 | Question Code de la famille | "À quel âge peut-on se marier ?" | Réponse du Code de la Famille | |
| 11.3 | Question droit commercial | "Comment créer une SARL à Djibouti ?" | Réponse du Code de Commerce | |
| 11.4 | Question hors base | "Quel est le PIB de Djibouti en 2025 ?" | Amiin répond avec ses connaissances, n'invente pas | |
| 11.5 | Question question ambiguë | "C'est quoi la loi ?" | Amiin demande précision | |

---

## 12. Comportement conversationnel

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 12.1 | Question de suivi | "Et pour un renouvellement ?" (après une 1re question) | Amiin garde le contexte des 10 derniers messages | |
| 12.2 | Contexte météo | "Est-ce qu'il fait chaud aujourd'hui ?" | Amiin utilise la météo injectée dans le system prompt | |
| 12.3 | Question heure/date | "On est quel jour ?" | Amiin répond avec la date correcte du system prompt | |
| 12.4 | Réponse courte (style WhatsApp) | Question simple | Réponse en 2-3 phrases max, pas de bullet points ni de titres | |
| 12.5 | Exception liste numérotée | "Quelles sont les étapes pour obtenir un visa ?" | Liste numérotée ≤4 items si vraiment nécessaire | |
| 12.6 | Historique persistant | Fermer et rouvrir l'app | Historique des conversations conservé (Hive) | |

---

## 13. Architecture tool-first — Tests de performance

| # | Scénario | Mesure | Attendu | Statut |
|---|---|---|---|---|
| 13.1 | Question sans agenda | "C'est quoi le droit de grève ?" | 1 seul appel API (pas de get_events) | |
| 13.2 | Question avec agenda | "C'est quoi mon planning demain ?" | 2 appels API, status "Récupération…" visible | |
| 13.3 | Latence 1er appel (sans agenda) | Mesurer depuis envoi → 1er token | < 3s (pas de 42K tokens de contexte) | |
| 13.4 | Latence 2e appel (avec agenda) | Mesurer durée totale | < 6s total (RAG + tool exec + 2e appel) | |
| 13.5 | Prompt system minimal | Activer logs réseau | system envoyé = ~35 tokens (date+météo seulement) | |

---

## 14. Gestion des erreurs

| # | Scénario | Action | Résultat attendu | Statut |
|---|---|---|---|---|
| 14.1 | Serveur hors ligne | Couper le réseau, envoyer message | Message d'erreur gracieux en français | |
| 14.2 | Timeout | Connexion très lente | Message d'erreur après 90s | |
| 14.3 | ID invalide (delete) | Demander à supprimer un événement avec mauvais ID | Erreur catchée, snackbar "Erreur lors de l'action" | |
| 14.4 | Annulation puis renvoi | Annuler → renvoyer le même message | Deuxième envoi fonctionne normalement | |

---

## Checklist rapide pré-release

```
□ Créer un RDV → il apparaît quand on demande l'agenda
□ Modifier un RDV → changements visibles
□ Supprimer un RDV → plus dans l'agenda
□ Créer une note → visible dans la liste des notes
□ Modifier une note → contenu mis à jour
□ Supprimer une note → plus dans la liste
□ Question juridique → réponse sourcée
□ Question agenda sans RDV → "aucun événement"
□ Question agenda avec RDV → liste correcte
□ Suggestion note → accepter crée la note
□ Historique conservé après redémarrage
□ Status "Récupération des données…" visible (agenda)
□ Entrée vocale → message envoyé
□ TTS → réponse lue correctement
□ Annulation → app reste stable
```
