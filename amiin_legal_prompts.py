# =============================================================================
# AMIIN LEGAL — PROMPTS MOTEUR DE DOSSIERS JURIDIQUES
# Fichier : amiin_legal_prompts.py
# Version : 2.1 — Corrections : pénal délit/crime séparés, références
#                  d'articles honnêtes ("à confirmer" au lieu de placeholders)
# =============================================================================

# =============================================================================
# 1. SYSTEM PROMPT PRINCIPAL — "AVOCAT JUNIOR IA"
# =============================================================================

SYSTEM_PROMPT_LEGAL = """
Tu es AMIIN LEGAL, assistant juridique IA de rang "collaborateur junior"
au sein d'un cabinet d'avocats djiboutien.

Tu travailles EXCLUSIVEMENT pour des avocats inscrits au Barreau de Djibouti.
Tu n'interagis jamais directement avec des clients finaux.
Ton rôle : préparer le travail intellectuel et rédactionnel que l'avocat senior
validera, corrigera et signera sous sa responsabilité professionnelle.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CADRE JURIDIQUE APPLICABLE (par ordre de priorité)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. DROIT DJIBOUTIEN EN VIGUEUR
   Codes principaux :
   - Code Civil de Djibouti (CCD)
   - Code de Commerce de Djibouti (CCom)
   - Code du Travail de Djibouti (CTD)
   - Code Pénal de Djibouti (CP)
   - Code de la Famille de Djibouti (CF)
   - Code Général des Impôts (CGI)
   - Code des Douanes (CDouanes)
   - Code des Marchés Publics (CMP)
   - Code de l'Environnement
   - Code Minier
   - Code des Investissements
   - Code des Zones Franches
   - Code de l'Arbitrage
   - Code des Pêches
   - Code de la Route

2. PROCÉDURE (textes de référence à appliquer par analogie si non indexés)
   - Code de Procédure Civile (inspiré du CPC français, adaptations djiboutiennes)
   - Code de Procédure Pénale de Djibouti
   - Règlement intérieur du Barreau de Djibouti

3. SOURCES COMPLÉMENTAIRES (citer avec réserve explicite)
   - Droit français (jurisprudence Cour de Cassation, doctrine) :
     applicable UNIQUEMENT en l'absence de disposition djiboutienne,
     compte tenu de la filiation historique du droit djiboutien
   - Actes OHADA : Djibouti n'est PAS membre, mais les praticiens s'y
     réfèrent en droit des affaires — toujours signaler ce statut

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
JURIDICTIONS DE DJIBOUTI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ORDRE JUDICIAIRE :
- Tribunal de Première Instance (TPI) — Chambre Civile / Commerciale / Correctionnelle
- Tribunal du Travail de Djibouti
- Tribunal de la Famille
- Cour d'Appel de Djibouti (délai d'appel : 1 mois)
- Cour Suprême de Djibouti (pourvoi : 2 mois)

ORDRE ADMINISTRATIF :
- Tribunal Administratif de Djibouti

PROCÉDURES D'URGENCE :
- Référé devant le Président du TPI (audience sous 48-72h)
- Ordonnance sur requête (mesures conservatoires)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RÈGLES DE RAISONNEMENT JURIDIQUE (IMPÉRATIVES)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RÈGLE 1 — CITATION OBLIGATOIRE
Toute affirmation juridique DOIT être suivie de sa source : [Code, Art. X]
Si la source n'est pas disponible dans le contexte RAG :
→ écrire [source à vérifier par l'avocat] — JAMAIS inventer un numéro d'article.

RÈGLE 2 — SÉPARATION DROIT / STRATÉGIE
Marqueurs obligatoires : "En droit," / "Stratégiquement," / "Il est recommandé de,"

RÈGLE 3 — SIGNALEMENT DES LACUNES
⚠️ POINT À VÉRIFIER : [description] — jamais combler par extrapolation non signalée.

RÈGLE 4 — QUALIFICATION AVANT TOUT
Faits → Qualification → Textes applicables → Analyse → Stratégie

RÈGLE 5 — HIÉRARCHIE DES NORMES
Constitution > Loi organique > Loi ordinaire > Décret > Arrêté > Circulaire

RÈGLE 6 — DÉLAIS = LIGNE ROUGE
🔴 DÉLAI CRITIQUE : [action] avant le [DATE] (dans X jours)

RÈGLE 7 — CONFIDENTIALITÉ
Données personnelles uniquement dans le corps du dossier, jamais dans les métadonnées.

RÈGLE 8 — LETTRE CLIENT EN LANGAGE ACCESSIBLE
La Section 7 doit être rédigée en français courant, sans jargon juridique.
Objectif : que le client comprenne sa situation, les prochaines étapes,
et ce qu'il doit faire, sans avoir besoin d'explications supplémentaires.
Ton : professionnel mais accessible, rassurant sans être complaisant.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TONALITÉ ET FORME
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Langue : français juridique djiboutien pour les sections 1-6 et 8-10
- Français courant et accessible pour la Section 7 (lettre client)
- Vouvoiement systématique pour les parties dans les actes
- Concision : l'avocat senior lit vite

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AVERTISSEMENT DE RESPONSABILITÉ (à inclure dans chaque dossier)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

"Document préparé par AMIIN LEGAL — Assistant IA à usage professionnel.
Ce document est un support de travail destiné exclusivement à l'avocat mandataire.
Il ne constitue pas un avis juridique définitif et doit être vérifié, validé
et signé sous la responsabilité exclusive de l'avocat.
La lettre client (Section 7) doit être relue et signée par l'avocat avant envoi."
"""


# =============================================================================
# 2. PROMPT D'EXPANSION DE REQUÊTE JURIDIQUE
# =============================================================================

PROMPT_EXPANSION_JURIDIQUE = """
Tu es un assistant de recherche juridique. À partir de la situation décrite,
génère exactement 4 requêtes de recherche optimisées pour interroger une base
de données juridique djiboutienne (codes de loi, procédures, jurisprudence).

Situation : {situation}
Type d'affaire : {type_affaire}

Génère 4 requêtes distinctes :
1. Requête sur les TEXTES DE LOI applicables (codes, articles)
2. Requête sur la PROCÉDURE applicable (délais, juridiction, forme des actes)
3. Requête sur les ÉLÉMENTS DE PREUVE et conditions de fond
4. Requête sur les SANCTIONS / RÉPARATIONS / EFFETS juridiques possibles

Réponds UNIQUEMENT avec un JSON valide, sans markdown :
{{
  "requete_textes": "...",
  "requete_procedure": "...",
  "requete_preuve": "...",
  "requete_sanctions": "..."
}}
"""


# =============================================================================
# 3. PROMPT DE GÉNÉRATION DU DOSSIER COMPLET (v2 — avec Section 7 lettre client)
# =============================================================================

PROMPT_GENERATION_DOSSIER = """
CONTEXTE JURIDIQUE RÉCUPÉRÉ (base de connaissances djiboutienne) :
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
{contexte_rag}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DOSSIER À TRAITER :
Type d'affaire   : {type_affaire}
Date des faits   : {date_saisine}
Instructions     : {instructions}

PARTIES :
{parties}

EXPOSÉ DES FAITS :
{faits}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PRODUIS LE DOSSIER COMPLET EN RESPECTANT STRICTEMENT CETTE STRUCTURE :
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# DOSSIER AMIIN LEGAL
## {type_affaire_label} — {nom_affaire}
*Préparé le : [DATE_GENERATION] | Avocat responsable : [À COMPLÉTER]*
*Document de travail — validation obligatoire avant tout usage*

---

## SECTION 1 — RÉSUMÉ EXÉCUTIF
[3 à 5 lignes : enjeu principal, position juridique du client, action prioritaire,
délai le plus urgent s'il existe]

---

## SECTION 2 — IDENTIFICATION DES PARTIES

| Rôle | Identité | Qualité juridique | Domicile/Siège |
|------|----------|-------------------|----------------|
| Demandeur / Client | ... | ... | ... |
| Défendeur | ... | ... | ... |

---

## SECTION 3 — QUALIFICATION JURIDIQUE DES FAITS

### 3.1 Exposé chronologique des faits
[Reformulation factuelle neutre et précise, en ordre chronologique, numérotée]

### 3.2 Qualification juridique
**Qualification retenue** : [NOM JURIDIQUE]
**Fondement principal** : [Code + Article]
**Fondements subsidiaires** : [si plusieurs qualifications possibles]

### 3.3 Éléments constitutifs vérifiés

| Élément constitutif | Requis par | Présent en l'espèce | Preuve disponible |
|--------------------|------------|--------------------|--------------------|
| [Élément 1] | [Art. X] | ✅ Oui / ⚠️ Partiel / ❌ Non | [Type de preuve] |

---

## SECTION 4 — ANALYSE JURIDIQUE APPROFONDIE

### 4.1 Textes applicables
[Pour chaque texte pertinent identifié dans le contexte RAG :]

**[Code + Article + Intitulé]**
> [Texte ou paraphrase précise de l'article]
Analyse d'application : [En quoi cet article s'applique aux faits]

### 4.2 Points de droit soulevés
**Question 1** : [Intitulé]
Réponse : [Analyse argumentée avec sources]

### 4.3 Jurisprudence et doctrine pertinentes
[Jurisprudence djiboutienne en priorité, française par analogie signalée]

⚠️ POINTS À VÉRIFIER PAR L'AVOCAT :
[Points non couverts par la base indexée]

---

## SECTION 5 — ANALYSE DES RISQUES

| Risque | Probabilité | Impact | Mesure d'atténuation |
|--------|-------------|--------|----------------------|
| [Risque 1] | Élevée/Moyenne/Faible | Fort/Moyen/Faible | [Mesure] |

**Solidité juridique de la position client** : [Forte / Moyenne / Fragile]
**Motif** : [Explication brève]

---

## SECTION 6 — STRATÉGIE ET OPTIONS

### Option A — [Nom] ⭐ RECOMMANDÉE
**Objectif** : [Ce que cette option vise]
**Fondement** : [Base juridique]
**Démarche** :
  1. [Étape 1]
  2. [Étape 2]
**Avantages** : [Points forts]
**Risques** : [Points faibles]
**Délai estimé** : [Durée]
**Coût estimé** : [Frais en FDJ indicatifs]

### Option B — [Nom alternatif]
[Structure identique à Option A]

### Option C — Règlement amiable / Négociation (si applicable)
**Opportunité** : [Évaluer si une transaction est envisageable]
**Base de négociation** : [Montant ou termes plancher/plafond]

---

## SECTION 7 — LETTRE DE SYNTHÈSE POUR LE CLIENT

<!-- DEBUT_LETTRE_CLIENT -->

⚠️ À RELIRE ET SIGNER PAR L'AVOCAT RESPONSABLE AVANT ENVOI AU CLIENT ⚠️

---

[Ville], le [DATE]

Madame, Monsieur [NOM DU CLIENT],

[PARAGRAPHE 1 — Votre situation en quelques mots]
Expliquer en français simple ce qui s'est passé, ce que cela signifie
juridiquement, et si la position du client est favorable ou non.
Pas de jargon. Pas d'article de loi cité. Le client doit comprendre.

[PARAGRAPHE 2 — Ce que nous allons faire]
Décrire concrètement les prochaines étapes : mise en demeure, dépôt de requête,
audience, délai approximatif. En langage courant. "Nous allons envoyer une lettre
officielle", "Nous allons saisir le tribunal", etc.

[PARAGRAPHE 3 — Ce que vous devez faire]
Liste claire des documents à rassembler et des actions du client.
Format bullet points, verbes d'action simples.

[PARAGRAPHE 4 — Ce que vous pouvez attendre]
Estimation honnête du résultat possible (fourchette en FDJ si applicable),
délai réaliste, et ce qui pourrait compliquer les choses.

[PARAGRAPHE 5 — Prochaine étape concrète]
Une seule action claire : "Merci de nous apporter [document] avant le [date]."

Nous restons à votre disposition pour toute question.

Cordialement,

Maître [NOM DE L'AVOCAT]
Avocat au Barreau de Djibouti
[Adresse du cabinet]
[Téléphone]

<!-- FIN_LETTRE_CLIENT -->

---

## SECTION 8 — CALENDRIER PROCÉDURAL

[Calculé à partir de la date des faits : {date_saisine}]

| Étape | Action | Date limite | Responsable | Statut |
|-------|--------|-------------|-------------|--------|
| 1 | [Mise en demeure] | [DATE] | Avocat | ⬜ À faire |
| 2 | [Dépôt requête] | [DATE] | Avocat | ⬜ À faire |
| 3 | [Première audience] | [DATE estimée] | — | ⬜ À planifier |

🔴 DÉLAIS CRITIQUES :
[Lister les délais inférieurs à 30 jours ou à risque de forclusion]

---

## SECTION 9 — DOCUMENTS À PRODUIRE

### 9.1 Documents rédigés par Amiin Legal (joints en annexe)

| # | Document | Type | Statut |
|---|----------|------|--------|
| 1 | [Document] | [Type] | ✅ Généré |

### 9.2 Pièces à rassembler par le client

| # | Pièce | Pourquoi nécessaire | Obtenue |
|---|-------|---------------------|---------|
| 1 | [Pièce] | [Raison] | ⬜ |

### 9.3 Pièces à obtenir par voie judiciaire (si nécessaire)

| # | Pièce | Mode d'obtention | Fondement |
|---|-------|-----------------|-----------|
| 1 | [Pièce] | [Mode] | [Art. X] |

---

## SECTION 10 — CHIFFRAGE ET PRÉTENTIONS

### 10.1 Prétentions chiffrées

| Poste | Base de calcul | Montant FDJ | Montant USD | Fondement |
|-------|----------------|-------------|-------------|-----------|
| [Poste 1] | [Calcul] | [Montant] | [Montant] | [Art. X] |
| **TOTAL** | | **[TOTAL FDJ]** | **[TOTAL USD]** | |

*Taux de conversion : 1 USD = 177,72 FDJ*

### 10.2 Fourchette réaliste
- **Scénario favorable** : [Montant FDJ]
- **Scénario médian** : [Montant FDJ]
- **Scénario défavorable** : [Montant FDJ]

---

## SECTION 11 — ACTES RÉDIGÉS (ANNEXES)

### ANNEXE A — [TYPE] : [TITRE]

<!-- DEBUT_DOCUMENT_A -->

[En-tête de cabinet — à compléter par l'avocat]
Maître [NOM AVOCAT]
Avocat au Barreau de Djibouti

Djibouti, le [DATE]

**ENVOI PAR LETTRE RECOMMANDÉE AVEC ACCUSÉ DE RÉCEPTION**

À l'attention de [DESTINATAIRE]

**OBJET : [OBJET]**

[Corps du document rédigé en style acte de procédure djiboutien]

Fait à Djibouti, le [DATE]
*Signature et sceau de Maître [NOM]*

<!-- FIN_DOCUMENT_A -->

---

## NOTE FINALE POUR L'AVOCAT SENIOR

**Points nécessitant votre attention particulière** :
1. [Point 1]
2. [Point 2]

**Décisions à prendre avant de procéder** :
- [ ] Valider la qualification juridique retenue
- [ ] Confirmer l'option stratégique (A / B / C)
- [ ] Relire et signer la lettre client (Section 7)
- [ ] Vérifier et signer les actes en annexe
- [ ] Confirmer les prétentions chiffrées avec le client

---
*Dossier généré par AMIIN LEGAL v2.0 — {date_generation}*
*Ce document est un support de travail. Validation obligatoire par l'avocat responsable.*
"""


# =============================================================================
# 4. PROMPTS SPÉCIALISÉS PAR TYPE D'AFFAIRE
# =============================================================================

PROMPTS_SPECIALISES = {

    "licenciement_abusif": """
INSTRUCTIONS SPÉCIFIQUES — CONTENTIEUX DU TRAVAIL (LICENCIEMENT)

Vérifier et traiter obligatoirement :
□ Nature du contrat (CDI / CDD / stage / intérim)
□ Ancienneté exacte (jours/mois/années) pour l'indemnité
□ Motif invoqué par l'employeur : réel et sérieux ?
□ Respect de la procédure (convocation, entretien, lettre motivée)
□ Calcul des indemnités légales :
    - Indemnité de licenciement [formule CTD]
    - Indemnité de préavis [durée selon ancienneté]
    - Congés payés non pris
    - Dommages-intérêts pour licenciement abusif
□ Affiliation CNSS (rappel de cotisations éventuelles)
□ Délai de prescription de l'action prud'homale : 3 ans [CTD]
□ Juridiction : Tribunal du Travail de Djibouti
□ Tentative de conciliation obligatoire préalable ? [vérifier CTD]

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Expliquer simplement que le licenciement était irrégulier
- Mentionner que le client a droit à des indemnités
- Demander contrat de travail + bulletins de salaire + lettres reçues
- Préciser le délai approximatif (3-6 mois de procédure)

Documents à générer : Lettre de mise en demeure + Requête Tribunal du Travail
""",

    "recouvrement_creance": """
INSTRUCTIONS SPÉCIFIQUES — RECOUVREMENT DE CRÉANCE

Vérifier et traiter obligatoirement :
□ Nature de la créance (contractuelle / délictuelle / fiscale)
□ Existence d'un titre (contrat, facture, reconnaissance de dette)
□ Montant exact + intérêts de retard [CCD ou CCom]
□ Prescription de la créance [délais selon nature]
□ Mise en demeure préalable (obligatoire + point de départ intérêts)
□ Procédure adaptée selon montant :
    - Petites créances → Injonction de payer
    - Créances importantes → Assignation au fond
    - Urgence → Référé provision
□ Mesures conservatoires à anticiper

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Confirmer que la créance est bien récupérable
- Expliquer la mise en demeure en termes simples
- Préciser que si refus, on saisit le juge
- Demander tous les documents prouvant la dette

Documents à générer : Mise en demeure + [Requête injonction OU Assignation OU Référé]
""",

    "divorce": """
INSTRUCTIONS SPÉCIFIQUES — DIVORCE ET DROIT DE LA FAMILLE

Vérifier et traiter obligatoirement :
□ Date et lieu du mariage — durée de l'union
□ Régime matrimonial applicable [CF Djibouti]
□ Type de divorce :
    - Pour faute / Consentement mutuel / Rupture de la vie commune
□ Enfants mineurs : âge(s), garde, droit de visite, pension alimentaire
□ Pension alimentaire pour l'époux(se) : conditions et calcul
□ Partage des biens communs
□ Sort du logement familial
□ Juridiction : Tribunal de la Famille de Djibouti

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Expliquer calmement les étapes du divorce
- Rassurer sur les droits concernant les enfants
- Expliquer simplement ce qu'est la pension alimentaire
- Lister les documents à apporter : acte de mariage, actes de naissance enfants, justificatifs de revenus

Documents à générer : Requête en divorce + Convention parentale provisoire
""",

    "creation_societe": """
INSTRUCTIONS SPÉCIFIQUES — CRÉATION DE SOCIÉTÉ

Vérifier et traiter obligatoirement :
□ Forme juridique (SARL / SA / Entreprise individuelle / Zone franche)
□ Capital social minimum requis
□ Nombre et identité des associés / actionnaires
□ Répartition du capital et des droits de vote
□ Objet social (rédaction précise)
□ Siège social (domiciliation légale à Djibouti)
□ Dirigeants : pouvoirs et limitations
□ Procédure d'immatriculation au RCCM
□ Obligations fiscales initiales (CGI)
□ Autorisations sectorielles spécifiques

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Confirmer la forme juridique choisie et pourquoi elle est adaptée
- Expliquer les étapes concrètes jusqu'à l'immatriculation
- Préciser les délais et coûts approximatifs
- Lister les documents à fournir

Documents à générer : Statuts constitutifs + PV d'Assemblée Constitutive + Liste formalités
""",

    "contentieux_commercial": """
INSTRUCTIONS SPÉCIFIQUES — CONTENTIEUX COMMERCIAL

Vérifier et traiter obligatoirement :
□ Qualification commerciale du litige
□ Contrat en cause : existence, validité, exécution
□ Manquement(s) : inexécution, mauvaise exécution, retard
□ Mise en demeure préalable et réponse adverse
□ Clause de résiliation / résolution contractuelle
□ Clause pénale ou d'intérêts de retard contractuelle
□ Clause attributive de compétence (arbitrage ?)
□ Prescription commerciale [CCom Djibouti]
□ Juridiction : TPI Chambre Commerciale ou Tribunal Arbitral
□ Préjudice : direct + indirect + perte de chance

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Expliquer en termes simples le manquement contractuel adverse
- Préciser la stratégie (mise en demeure d'abord, puis justice)
- Donner une estimation du résultat possible
- Demander tous les documents contractuels et échanges écrits

Documents à générer : Mise en demeure + Assignation TPI Commercial
""",

    "penal_defense": """
INSTRUCTIONS SPÉCIFIQUES — DÉFENSE PÉNALE

Vérifier et traiter obligatoirement :
□ Qualification de l'infraction reprochée [CP Djibouti]
□ Éléments constitutifs : légal + matériel + moral
□ Stade de la procédure (garde à vue / instruction / jugement)
□ Arguments de défense :
    - Fond (absence d'élément constitutif)
    - Procédure (nullités, violations des droits)
    - Circonstances atténuantes [CP Djibouti]
    - Causes d'irresponsabilité pénale [CP Djibouti]
□ Peine encourue (principale + complémentaires)
□ Partie civile éventuelle
□ Détention provisoire : durée maximale légale

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Rassurer sans minimiser la gravité
- Expliquer simplement les faits reprochés et les droits du client
- Préciser ce que l'avocat va faire concrètement
- NE PAS mentionner les risques de peine dans la lettre client — à expliquer oralement

Documents à générer : Mémoire de défense + Requête en nullité (si applicable)
""",

    "contentieux_administratif": """
INSTRUCTIONS SPÉCIFIQUES — CONTENTIEUX ADMINISTRATIF

Vérifier et traiter obligatoirement :
□ Nature de l'acte contesté
□ Auteur de l'acte (ministère, établissement public, commune)
□ Recours administratif préalable obligatoire (RAPO) :
    - Gracieux / Hiérarchique
    - Rejet implicite (généralement 2 mois)
□ Délai de recours contentieux (généralement 2 mois)
□ Recevabilité : intérêt à agir, capacité, délai
□ Moyens de légalité externe et interne
□ Juridiction : Tribunal Administratif de Djibouti
□ Référé suspension possible ?

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Expliquer que l'administration a commis une erreur ou un excès de pouvoir
- Préciser qu'il faut d'abord faire une réclamation administrative avant le juge
- Donner les délais précis de façon compréhensible
- Rassurer sur le fait que le client a des droits face à l'administration

Documents à générer : Recours administratif préalable + Requête Tribunal Administratif
""",

    "refere_urgence": """
INSTRUCTIONS SPÉCIFIQUES — PROCÉDURE DE RÉFÉRÉ (URGENCE)

Vérifier et traiter obligatoirement :
□ Conditions du référé (URGENCE + absence de contestation sérieuse OU trouble illicite)
□ Type de référé :
    - Provision (avance sur somme non sérieusement contestable)
    - Mesures conservatoires (faire cesser un trouble)
    - Injonction (ordonner une mesure urgente)
□ Juridiction : Président du TPI de Djibouti
□ Délai audience : sous 48-72h possible
□ Caractère provisoire de l'ordonnance
□ Suite au fond nécessaire

LETTRE CLIENT — POINTS À ABORDER (Section 7) :
- Expliquer l'urgence et pourquoi on agit vite
- Préciser que le référé est une mesure provisoire (pas le jugement final)
- Rassurer que le juge peut être saisi très rapidement
- Préciser ce que le client doit apporter immédiatement

Documents à générer : Assignation en référé
""",
}


# =============================================================================
# 5. TABLES DE PRESCRIPTION PAR TYPE D'AFFAIRE
# =============================================================================
# Utilisées par l'API pour calculer et afficher les alertes de prescription
# sans appeler Claude — calcul côté serveur, instantané.
# =============================================================================

PRESCRIPTIONS = {
    "licenciement_abusif": {
        "delai_label":  "3 ans",
        "delai_jours":  3 * 365,
        "action":       "Saisine du Tribunal du Travail de Djibouti",
        "article":      "CTD Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 90,   # jours restants avant alerte rouge
        "alerte_orange": 180,
    },
    "recouvrement_creance": {
        "delai_label":  "5 ans",
        "delai_jours":  5 * 365,
        "action":       "Assignation au fond ou injonction de payer",
        "article":      "CCD/CCom Djibouti — réf. exacte à confirmer (l'Art. 2224 est une réf. du Code civil français)",
        "alerte_rouge": 90,
        "alerte_orange": 180,
    },
    "divorce": {
        "delai_label":  "Pas de prescription — mais délais procéduraux à respecter",
        "delai_jours":  None,
        "action":       "Requête au Tribunal de la Famille",
        "article":      "CF Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": None,
        "alerte_orange": None,
    },
    "creation_societe": {
        "delai_label":  "Immatriculation RCCM dans les 30 jours suivant la constitution",
        "delai_jours":  30,
        "action":       "Dépôt des statuts et immatriculation au Registre du Commerce",
        "article":      "CCom Djibouti / RCCM — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 7,
        "alerte_orange": 15,
    },
    "contentieux_commercial": {
        "delai_label":  "5 ans",
        "delai_jours":  5 * 365,
        "action":       "Mise en demeure + assignation au fond",
        "article":      "CCom Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 90,
        "alerte_orange": 180,
    },
    # ── Pénal : délais distincts délit / crime (correction v2.1) ────────────
    # IMPORTANT : "penal_defense" est conservé comme alias rétrocompatible
    # et applique le délai DÉLIT (3 ans). Pour un crime, utiliser "penal_crime".
    "penal_delit": {
        "delai_label":  "3 ans (délits)",
        "delai_jours":  3 * 365,
        "action":       "Prescription de l'action publique — délit",
        "article":      "CPP Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 60,
        "alerte_orange": 120,
    },
    "penal_crime": {
        "delai_label":  "10 ans (crimes)",
        "delai_jours":  10 * 365,
        "action":       "Prescription de l'action publique — crime",
        "article":      "CPP Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 180,
        "alerte_orange": 365,
    },
    "penal_defense": {
        "delai_label":  "3 ans (délit) — ⚠️ si crime, sélectionner 'Défense pénale (crime)'",
        "delai_jours":  3 * 365,
        "action":       "Prescription de l'action publique — délai délit appliqué par défaut",
        "article":      "CPP Djibouti — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 60,
        "alerte_orange": 120,
    },
    "contentieux_administratif": {
        "delai_label":  "2 mois après notification ou rejet implicite",
        "delai_jours":  60,
        "action":       "Recours administratif préalable puis Tribunal Administratif",
        "article":      "Procédure administrative djiboutienne — réf. exacte à confirmer",
        "alerte_rouge": 15,
        "alerte_orange": 30,
    },
    "refere_urgence": {
        "delai_label":  "URGENCE — assignation à déposer immédiatement",
        "delai_jours":  2,
        "action":       "Assignation en référé devant le Président du TPI",
        "article":      "CPC Djibouti (référé) — réf. exacte à confirmer par l'avocat",
        "alerte_rouge": 2,
        "alerte_orange": 5,
    },
    "autre": {
        "delai_label":  "À déterminer selon la nature de l'affaire",
        "delai_jours":  None,
        "action":       "Consulter un avocat pour les délais applicables",
        "article":      "Variable selon les codes applicables",
        "alerte_rouge": None,
        "alerte_orange": None,
    },
}


# =============================================================================
# 6. MAPPING TYPE_AFFAIRE → PROMPT SPÉCIALISÉ + LABEL
# =============================================================================

TYPES_AFFAIRES = {
    "licenciement_abusif":       {"label": "Contentieux du Travail — Licenciement Abusif",      "prompt_key": "licenciement_abusif"},
    "recouvrement_creance":      {"label": "Recouvrement de Créance",                            "prompt_key": "recouvrement_creance"},
    "divorce":                   {"label": "Droit de la Famille — Divorce",                      "prompt_key": "divorce"},
    "creation_societe":          {"label": "Droit des Sociétés — Création",                      "prompt_key": "creation_societe"},
    "contentieux_commercial":    {"label": "Contentieux Commercial",                             "prompt_key": "contentieux_commercial"},
    "penal_defense":             {"label": "Défense Pénale",                                     "prompt_key": "penal_defense"},
    "penal_delit":               {"label": "Défense Pénale — Délit",                             "prompt_key": "penal_defense"},
    "penal_crime":               {"label": "Défense Pénale — Crime",                             "prompt_key": "penal_defense"},
    "contentieux_administratif": {"label": "Contentieux Administratif",                          "prompt_key": "contentieux_administratif"},
    "refere_urgence":            {"label": "Procédure d'Urgence — Référé",                       "prompt_key": "refere_urgence"},
    "autre":                     {"label": "Affaire Juridique",                                  "prompt_key": None},
}


# =============================================================================
# 7. FONCTION UTILITAIRE — CALCUL DE PRESCRIPTION
# =============================================================================

def calculer_alerte_prescription(type_affaire: str, date_faits_str: str) -> dict:
    """
    Calcule l'alerte de prescription pour un type d'affaire donné.

    Args:
        type_affaire   : code du type d'affaire (ex: "licenciement_abusif")
        date_faits_str : date des faits au format "YYYY-MM-DD"

    Returns:
        {
            "delai_label":    str,   # Libellé du délai ("3 ans", etc.)
            "action":         str,   # Action à effectuer avant prescription
            "article":        str,   # Référence légale
            "jours_ecoules":  int,   # Jours écoulés depuis les faits
            "jours_restants": int | None,  # Jours avant prescription (None si pas applicable)
            "date_limite":    str | None,  # Date limite au format "DD/MM/YYYY"
            "niveau_alerte":  str,   # "rouge", "orange", "vert", "info"
            "message":        str,   # Message d'alerte formaté
        }
    """
    from datetime import datetime, timedelta

    presc = PRESCRIPTIONS.get(type_affaire, PRESCRIPTIONS["autre"])

    try:
        date_faits = datetime.strptime(date_faits_str, "%Y-%m-%d")
    except (ValueError, TypeError):
        return {
            "delai_label":    presc["delai_label"],
            "action":         presc["action"],
            "article":        presc["article"],
            "jours_ecoules":  None,
            "jours_restants": None,
            "date_limite":    None,
            "niveau_alerte":  "info",
            "message":        f"Prescription : {presc['delai_label']} — {presc['action']} [{presc['article']}]",
        }

    aujourd_hui   = datetime.now()
    jours_ecoules = (aujourd_hui - date_faits).days

    if presc["delai_jours"] is None:
        return {
            "delai_label":    presc["delai_label"],
            "action":         presc["action"],
            "article":        presc["article"],
            "jours_ecoules":  jours_ecoules,
            "jours_restants": None,
            "date_limite":    None,
            "niveau_alerte":  "info",
            "message":        f"{presc['delai_label']} — {presc['action']} [{presc['article']}]",
        }

    date_limite    = date_faits + timedelta(days=presc["delai_jours"])
    jours_restants = (date_limite - aujourd_hui).days
    date_limite_str = date_limite.strftime("%d/%m/%Y")

    # Déterminer le niveau d'alerte
    if jours_restants <= 0:
        niveau  = "expiree"
        message = f"⛔ PRESCRIPTION EXPIRÉE le {date_limite_str} — Action requise d'urgence [{presc['article']}]"
    elif presc["alerte_rouge"] and jours_restants <= presc["alerte_rouge"]:
        niveau  = "rouge"
        message = f"🔴 DÉLAI CRITIQUE : {presc['action']} avant le {date_limite_str} (dans {jours_restants} jours) [{presc['article']}]"
    elif presc["alerte_orange"] and jours_restants <= presc["alerte_orange"]:
        niveau  = "orange"
        message = f"🟡 Délai à surveiller : {presc['action']} avant le {date_limite_str} (dans {jours_restants} jours) [{presc['article']}]"
    else:
        niveau  = "vert"
        message = f"✅ Prescription : {presc['delai_label']} — Délai expire le {date_limite_str} (dans {jours_restants} jours) [{presc['article']}]"

    return {
        "delai_label":    presc["delai_label"],
        "action":         presc["action"],
        "article":        presc["article"],
        "jours_ecoules":  jours_ecoules,
        "jours_restants": jours_restants,
        "date_limite":    date_limite_str,
        "niveau_alerte":  niveau,
        "message":        message,
    }


# =============================================================================
# 8. FONCTION UTILITAIRE — ASSEMBLAGE DU PROMPT FINAL
# =============================================================================

def build_legal_prompt(
    type_affaire: str,
    faits: str,
    parties: dict,
    date_saisine: str,
    contexte_rag: str,
    instructions: str = "Aucune instruction spécifique.",
    date_generation: str = "",
) -> dict:
    """
    Assemble le system prompt + le user prompt pour un dossier juridique.

    Returns:
        {
            "system": str,
            "user":   str,
        }
    """
    import json
    from datetime import datetime

    if not date_generation:
        date_generation = datetime.now().strftime("%d/%m/%Y à %Hh%M")

    affaire_info   = TYPES_AFFAIRES.get(type_affaire, TYPES_AFFAIRES["autre"])
    label          = affaire_info["label"]
    prompt_key     = affaire_info["prompt_key"]
    prompt_special = PROMPTS_SPECIALISES.get(prompt_key, "") if prompt_key else ""

    if isinstance(parties, dict):
        parties_str = json.dumps(parties, ensure_ascii=False, indent=2)
    else:
        parties_str = str(parties)

    nom_affaire = "Dossier en cours"
    if isinstance(parties, dict):
        demandeur = parties.get("demandeur", {})
        if isinstance(demandeur, dict):
            nom_affaire = demandeur.get("nom", "Dossier en cours")

    user_prompt = PROMPT_GENERATION_DOSSIER.format(
        contexte_rag=contexte_rag,
        type_affaire=type_affaire,
        type_affaire_label=label,
        nom_affaire=nom_affaire,
        date_saisine=date_saisine,
        parties=parties_str,
        faits=faits,
        instructions=instructions,
        date_generation=date_generation,
    )

    if prompt_special:
        user_prompt += f"\n\n━━━━ INSTRUCTIONS COMPLÉMENTAIRES ━━━━\n{prompt_special}"

    return {
        "system": SYSTEM_PROMPT_LEGAL,
        "user":   user_prompt,
    }


# =============================================================================
# 9. EXEMPLE D'UTILISATION
# =============================================================================
#
# from amiin_legal_prompts import (
#     build_legal_prompt,
#     calculer_alerte_prescription,
#     PROMPT_EXPANSION_JURIDIQUE,
#     TYPES_AFFAIRES,
#     PRESCRIPTIONS,
# )
#
# # Calcul prescription instantané (sans Claude)
# alerte = calculer_alerte_prescription("licenciement_abusif", "2022-11-15")
# # → {"niveau_alerte": "vert", "jours_restants": 412, "message": "✅ ..."}
#
# # Construction du prompt dossier complet
# prompts = build_legal_prompt(
#     type_affaire  = "licenciement_abusif",
#     faits         = "...",
#     parties       = {"demandeur": {...}, "defendeur": {...}},
#     date_saisine  = "2022-11-15",
#     contexte_rag  = contexte_rag,
# )
# =============================================================================
