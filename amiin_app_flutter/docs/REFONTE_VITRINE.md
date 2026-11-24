# Refonte « vitrine » d'Amiin — référence et méthode d'application

> Branche `ccr-eb30c89b-roz44w`, novembre 2026. Ce document formalise, dans
> l'ordre où ils ont été faits, les changements validés sur l'écran d'accueil
> et la barre d'onglets, puis donne la méthode pour les appliquer à toutes
> les pages. Il complète `AUDIT_GRAPHIQUE.md` (état des lieux d'avant).

**Commits de référence**

| Commit | Contenu |
|---|---|
| `dc0e234` | Accueil d'origine retravaillé en version « vitrine » flottante (thèmes clair et sombre) |
| `6cef0b0` | Thème « Lacté » monochrome + adaptation au bandeau clair |
| `0695ea4` | Touches de couleur sur les éléments essentiels de Lacté |
| `6cfd27a` | Barre d'onglets flottante en verre dépoli |

Le commit `c3aee78` (premier prototype « grand titre ») a été **rejeté** et
entièrement remplacé par `dc0e234` : ne pas s'en inspirer.

---

## 1. Principes

1. **On garde l'identité, on ajoute de la profondeur.** Bandeau encre de nuit,
   micro central, labels de section en capitales avec barre colorée,
   dualité turquoise (secrétariat) / ocre (information) : tout est conservé.
   La modernité vient des détails, pas d'une nouvelle mise en page.
2. **Fond blanc cassé, surfaces blanches qui flottent.** La hiérarchie se lit
   par l'élévation (ombres douces), pas par des bordures ou des aplats.
3. **Les ombres sont douces et à deux couches** : un contact net très léger
   + une diffusion large et décalée vers le bas. Jamais d'ombre dure.
4. **Le verre dépoli est réservé à ce qui flotte au-dessus d'autre chose**
   (champ de saisie sur le bandeau, bouton réglages, barre d'onglets).
   Jamais dans le contenu lui-même.
5. **Tout ce qui se touche réagit** : léger enfoncement (échelle) + ombre
   qui diminue + retour haptique.
6. **Le mouvement est court et respecte l'accessibilité** : 140–340 ms,
   coupé quand `MediaQuery.disableAnimations` est vrai.
7. **Tout passe par les tokens du thème** (`context.ac`) : aucun écran ne
   doit supposer un bandeau foncé ou une couleur précise (cf. Lacté).

---

## 2. Thèmes « type Apple » clair et sombre (Sel d'Assal et Encre de Nuit)

Aucun token de `themes.dart` n'a changé pour ces deux thèmes : le rendu
vient du traitement « vitrine » appliqué à l'écran. Les helpers, d'abord
privés à `home_screen.dart`, sont désormais dans `lib/theme/elevation.dart`
et `lib/widgets/floating_card.dart` (phase A, §5).

Les étapes ci-dessous sont dans l'ordre logique de construction.

### 2.1 Fondations (helpers en tête de `home_screen.dart`)

**Étape 1 — Fond de page blanc cassé** · `_pageBackground(context)`
- Thèmes clairs : `Color.lerp(ac.background, Colors.white, 0.62)`
  (le sable `#F2EFE9` devient un blanc cassé chaud ≈ `#F9F8F5`).
- Thèmes sombres : `ac.background` inchangé.

**Étape 2 — Ombre flottante** · `_floatShadow(context, lift: 0..1, tint:)`

| Couche | Couleur | Flou | Décalage Y | Étalement |
|---|---|---|---|---|
| Contact | `base` α `0.04 × k` | 1.5 | 1 | 0 |
| Diffusion | `tint ?? base` α `(0.05 + 0.05 × lift) × k` | `10 + 26 × lift` | `4 + 12 × lift` | −4 |

- `base` = `ac.ink` en clair, `Colors.black` en sombre ; `k` = 1 en clair,
  2.2 en sombre (les ombres doivent rester visibles sur fond foncé).
- `lift` : 0.45 tuiles, 0.5 cartes standard, 1.0 carte qui chevauche le bandeau.
- `tint` : colore la diffusion de l'accent (tuiles turquoise/ocre).

**Étape 3 — Liseré de lumière** · `_hairline(context)`
- Bord 1 px : blanc α 0.9 en clair, blanc α 0.06 en sombre.
  Il « accroche la lumière » et remplace les bordures grises.

**Étape 4 — Rayons**
- Cartes : **18**. Bandeau : **32** (coins bas). Barre d'onglets : **26**.
  Pastilles d'icône : **10**. Champs, puces, boutons ronds : `RadiusAmiin.full`.

**Étape 5 — Carte flottante** · `_FloatingCard`
- Fond `ac.surface` (ou couleur fournie), rayon 18, liseré, `_floatShadow`.
- Padding par défaut `Spacing.lg` (16).
- Si `onTap` : à l'appui, échelle **0.98** (160 ms, `easeOut`), ombre
  ramenée à `lift × 0.3` (180 ms), `HapticFeedback.selectionClick()`.
- C'est la brique de base de toutes les cartes de la refonte.

### 2.2 Bandeau héros · `_Hero`

**Étape 6 — Bandeau qui flotte sur la page**
- Coins bas arrondis 32, découpage `ClipRRect`.
- Ombre portée : `headerGradientStart` α 0.28, flou 40, Y 18, étalement −12.
- Dégradé `headerGradientStart → headerGradientEnd` (haut-gauche → bas-droite) inchangé.

**Étape 7 — Halos de profondeur** · `_Glow` (dégradé radial vers transparent)
- Turquoise `secretariatAccent` α 0.30, Ø 300, position `top −120, right −90`.
- Ocre `infoAccent` α 0.14, Ø 280, position `bottom −140, left −110`.

**Étape 8 — Salutation** : `FontFamily.sansLight`, 17, `onHeader` α 0.72,
interligne 1.5, approche −0.2 (avant : 15, α 0.55).

**Étape 9 — Micro flottant** · `_MicButton`
- Anneau Ø 96 : fond accent α 0.08, bord accent α 0.18.
- Bouton Ø 64 : dégradé vertical `lerp(accent, blanc, 0.18) → accent`,
  bord blanc α 0.22, ombre accent α 0.55 (flou 28, Y 10, étalement −6).
- Appui : échelle 0.94 (160 ms) + `HapticFeedback.lightImpact()`.
- Libellé « Parler à Amiin » : 11, `onHeader` α 0.55, approche 0.6.

**Étape 10 — Verre dépoli** · `_GlassField`, `_GlassIconButton`, `_glass()`
- Champ de saisie : hauteur 50, `BackdropFilter` flou 16, dégradé
  `_glass(0.12) → _glass(0.05)`, bord `_glass(0.16)`, texte `onHeader` α 0.45.
  Bouton d'envoi Ø 38 : `onHeader` α 0.92, flèche `arrow_upward_rounded`
  couleur `headerGradientStart`.
- Bouton réglages : Ø 38, flou 12, fond `_glass(0.10)`, bord `_glass(0.16)`.
- `_glass(α)` = blanc α sur bandeau foncé ; `onHeader` α×0.45 sur bandeau
  clair (voir Lacté, §3.3).

### 2.3 Superposition

**Étape 11 — Carte « Aujourd'hui » à cheval sur le bandeau**
- Décalée de `_Hero.overlap` = **36 px** vers le haut (`Transform.translate`),
  `lift: 1`. Le bandeau réserve `Spacing.xxl + overlap` en bas.
- Libellé « AUJOURD'HUI » déplacé **dans** la carte, en `infoAccent`.
- ⚠️ **Piège** : la carte doit être dans **le même sliver** que le bandeau
  (une `Column` dans un `SliverToBoxAdapter`). Un `CustomScrollView` peint
  ses premiers slivers **par-dessus** les suivants : dans un sliver séparé,
  la carte passe sous le bandeau.

### 2.4 Contenu

**Étape 12 — Labels de section** : conservés (barre 3 × 12 + capitales,
approche 1.2). Action à droite suffixée d'un chevron : « Agenda › ».
Espacement label → contenu : `Spacing.md` (12).

**Étape 13 — Tuiles d'accès rapide** · `_QuickTileCard`
- `_FloatingCard` teintée : fond `accentLight`, `shadowTint: accent`,
  `lift: 0.45`, padding 12, grille 2 × 2 espacée de 12.
- Pastille d'icône 34 × 34, rayon 10, blanche (blanc α 0.08 en sombre),
  ombre accent α 0.22 (flou 8, Y 3) ; icône 18 couleur accent.
- Libellé `geoBold` 14 couleur `accentDark` + chevron α 0.5.

**Étape 14 — Liste groupée** (« Cette semaine »)
- Une seule `_FloatingCard` (padding 0) au lieu d'une carte par élément.
- Lignes : padding 16 / 14 ; pastille de catégorie Ø 8 avec halo
  (ombre de sa couleur α 0.45, flou 6) ; titre 1 ligne ; chevron muted α 0.6.
- Séparateurs 0.5 px `border` α 0.7, décalés à gauche (38) pour s'aligner sur le texte.

**Étape 15 — Cartes simples** (notes) : `_FloatingCard` tappable, espacées de 12.

**Étape 16 — Défilement** : `BouncingScrollPhysics` ; espace final
`Spacing.xxl + MediaQuery.padding.bottom` (dégage la barre flottante, §4).

---

## 3. Thème « Lacté »

### 3.1 Intention
Monochrome : fonds blanc cassé, surfaces blanches, texte et contrôles en
noir doux et gris. La couleur ne sert qu'aux **éléments essentiels** :
turquoise pour agir, ocre pour s'informer, plus logo, alertes et succès.

### 3.2 Étapes (dans l'ordre)

**Étape 17 — Nouvelle variante** · `lib/theme/themes.dart`
- `AmiinThemeColors.lacte`, enum `AmiinThemeVariant.lacte`, id `'lacte'`,
  libellé « Lacté », branchée dans `id`, `label`, `colors`, `fromId`.

| Token | Valeur | Rôle |
|---|---|---|
| `background` | `#F4F3F0` | fond (→ ≈ `#FAF9F7` après l'étape 1) |
| `surface` / `surface2` | `#FFFFFF` / `#EDECE8` | cartes / fonds secondaires |
| `ink` / `midTone` / `muted` | `#1C1C1E` / `#48484A` / `#8E8E93` | textes |
| `border` | `#E3E2DE` | séparateurs |
| `primary` / `primaryDark` / `primaryMid` | `#1C1C1E` / `#000000` / `#3A3A3C` | contrôles Material |
| `headerGradientStart → End` | `#FFFFFF → #F0EFEB` | bandeau **clair** |
| `onHeader` | `#1C1C1E` | texte sur bandeau |
| `secretariatAccent` | `#1E8A8A` turquoise | actions (étape 19) |
| `secretariatAccentLight` / `Dark` | `#E9E8E4` / `#1C1C1E` | fond et texte des tuiles : restent gris/noir |
| `secretariatAccentMid` | `#1E8A8A` | halo du bandeau |
| `infoAccent` | `#C8902F` ocre | repères d'information (étape 19) |
| `infoAccentLight` / `Dark` | `#F3F2EF` / `#3A3A3C` | fond et texte des tuiles : restent gris/noir |
| `infoAccentMid` | `#C8902F` | catégorie éducation, halo |
| `alertColor`, `success` (+ `Light`) | palette inchangée | alertes, confirmations |

**Étape 18 — Bandeau clair** · `home_screen.dart`
- Détection : `_lightHeader(context)` = `onHeader.computeLuminance() < 0.5`.
- Ombre du bandeau : `ink` α 0.10 (au lieu de `headerGradientStart` α 0.28).
- Halos : turquoise `secretariatAccentMid` α 0.12, ocre `infoAccentMid` α 0.07.
- Verre : `_glass()` fonce au lieu d'éclaircir (`onHeader` α × 0.45).
- Résultat : micro turquoise, bouton d'envoi noir à flèche blanche.

**Étape 19 — Touches de couleur essentielles** (commit `0695ea4`)
- `secretariatAccent` passe de noir à turquoise, `infoAccent` de graphite à
  ocre. Seuls les **accents** changent : fonds et libellés de tuiles restent
  monochromes.
- Turquoise : micro et son anneau, liens « › », barres de section, icônes
  Agenda/Notes, badge « Amiin », onglets Amiin/Agenda/Notes.
- Ocre : « AUJOURD'HUI », icônes météo/prière/change, icônes
  Annuaire/Démarches, onglets Annuaire/Démarches.

**Étape 20 — Réglages**
- `settings_appearance_screen.dart` : liseré `border` autour des cartes de
  thème à bandeau clair (sinon invisible sur le fond).
- `settings_screen.dart` : libellé « Lacté » ; `settings_service.dart` :
  commentaire des ids.

---

## 4. Barre d'onglets flottante · `lib/navigation/app_router.dart`

**Étape 21 — Le contenu passe sous la barre**
- `extendBody: true` sur le `Scaffold` du `StatefulShellRoute`.
- Conséquence : dans les écrans d'onglet, `MediaQuery.padding.bottom`
  **inclut la hauteur de la barre**. `SafeArea`, `ListView` sans padding
  et les `FloatingActionButton` s'en écartent seuls ; les autres doivent
  ajouter `padding.bottom` eux-mêmes (cf. étape 16).

**Étape 22 — Conteneur flottant** · `AmiinNavBar`
- `SafeArea(top: false, minimum: bottom 10)`, marges latérales 12.
- Hauteur 62, rayon 26.
- Ombres (hors découpage, via `DecoratedBox`) :
  contact noir α 0.06 (0.35 en sombre), flou 2, Y 1 ;
  diffusion `ink` α 0.14 (noir α 0.45 en sombre), flou 32, Y 12, étalement −8.

**Étape 23 — Verre dépoli**
- `BackdropFilter` flou 24.
- Voile dégradé vertical `surface` α **0.72 → 0.58** (sombre : 0.66 → 0.52).
- Liseré blanc α 0.85 (sombre : 0.08).

**Étape 24 — Capsule de sélection**
- `AnimatedPositioned` dans un `Stack`, marge interne 5, largeur d'un
  emplacement − 4, rayon 21.
- Couleur du mode α 0.12 (sombre : 0.22) ; glisse en **340 ms**,
  courbe `Cubic(0.2, 0.8, 0.2, 1)`.
- Remplace la `HorizonLine` de l'ancienne barre.

**Étape 25 — Couleur des onglets** · `_tabColor`
- Accueil : `ink` ; Amiin, Agenda, Notes : `secretariatAccent` ;
  Annuaire, Démarches : `infoAccent`. Non sélectionnés : `muted`.

**Étape 26 — Boutons** · `_NavButton`
- Icône 22 (pleine si sélectionnée), libellé `geo` 10, graisse 600/500,
  approche −0.1.
- Appui : échelle 0.9 (140 ms) ; `selectionClick` si on change d'onglet.
- `Semantics(button, selected, label)` ; badge agenda conservé.
- Animations coupées si `disableAnimations`.

---

## 5. Méthode pour appliquer la refonte à toutes les pages

### Phase A — Factoriser (avant toute page)

Les helpers de la refonte sont aujourd'hui **privés** à `home_screen.dart`.
Les extraire en premier, sinon chaque page les recopiera.

1. `lib/theme/elevation.dart` : `pageBackground`, `floatShadow`,
   `hairline`, `isLightHeader`, `glass`, constantes de rayon (18, 26, 32).
2. `lib/widgets/floating_card.dart` : `FloatingCard` (ex-`_FloatingCard`).
3. `lib/widgets/glass.dart` : `GlassField`, `GlassIconButton`, `Glow`.
4. `lib/widgets/grouped_list.dart` : carte de liste groupée + ligne
   (pastille, titre, sous-titre, chevron, séparateur décalé).
5. Faire pointer `home_screen.dart` sur ces versions publiques, vérifier
   que l'accueil est identique dans les 3 thèmes.

### Phase B — Mettre à jour les composants partagés

Un changement ici se propage à beaucoup d'écrans d'un coup.

6. **`AmiinCard`** (`lib/widgets/card.dart`, utilisée dans 16 fichiers) : style flottant
   (rayon 18, liseré, `floatShadow`) ; remplacer la bordure gauche des
   variantes `info`/`secretariat` par une pastille ou un libellé coloré.
7. **`AmiinHeader`** (`lib/widgets/header.dart`, utilisé dans 20 fichiers) : fond
   `pageBackground` ou verre dépoli quand le contenu défile dessous ;
   boutons ronds en verre ; vérifier la variante `dark` avec Lacté
   (bandeau clair). Décider du sort de la `HorizonLine` sous les en-têtes.
8. **`ShadowAmiin`** (`spacing.dart`) : aligner sur `floatShadow` ou déprécier.
9. Boutons, champs, puces (`button.dart`, `search_bar.dart`, `tag.dart`) :
   pilules, verre si posés sur un bandeau, enfoncement + haptique.

### Phase C — Écran par écran

Ordre conseillé (fréquentation, puis complexité) :

| # | Écran | Fichiers | Points d'attention |
|---|---|---|---|
| 1 | Chat | `chat/chat_screen.dart` | barre de saisie collée au bas : en faire une pilule flottante au-dessus de la barre d'onglets ; en-tête `headerGradientEnd` |
| 2 | Agenda | `agenda_screen`, `event_detail_screen`, `create_event_screen` | liste groupée par jour ; badge ; formulaires |
| 3 | Notes | `notes_screen`, `note_detail_screen` | FAB « retour en haut » au-dessus de la barre |
| 4 | Annuaire | `annuaire_screen`, `service_detail_screen` | FAB ; listes longues ; catégories colorées |
| 5 | Démarches | `demarches_screen`, `demarche_detail_screen`, `user_demarche_tracking_screen` | frise d'étapes ; feuilles modales |
| 6 | Réglages | `settings_*` (13 fichiers + `settings_widgets.dart`) | listes groupées type « Réglages iOS » ; commencer par `settings_widgets.dart` |
| 7 | Auth / splash | `login`, `register`, `auth_widgets`, `splash_screen` | identité sombre fixe (`ColorsAmiin`) : décider si Lacté s'y applique |

### Check-list par écran

- [ ] Fond `pageBackground` (pas `ac.background` brut sur thème clair).
- [ ] Cartes → `FloatingCard` / `AmiinCard` flottante ; plus de bordures grises.
- [ ] Listes de plusieurs éléments → une carte groupée avec séparateurs décalés.
- [ ] Éléments posés sur un bandeau ou qui flottent → verre dépoli via `glass()`.
- [ ] Aucune couleur supposant un bandeau foncé (`Colors.white…` sur
      `headerGradient`) : passer par `onHeader` / `glass()`.
- [ ] Labels de section conservés ; actions suffixées « › ».
- [ ] Tout élément tappable : enfoncement + ombre réduite + haptique.
- [ ] Bas de page : rien de caché sous la barre (`padding.bottom` inclut la barre).
- [ ] Animations coupées si `disableAnimations`.
- [ ] Captures dans les **3 thèmes** : Sel d'Assal, Encre de Nuit, Lacté.

### Vérifier avec l'aperçu de développement

`lib/dev/home_preview.dart` affiche l'accueil avec des données d'exemple,
sans backend (`?theme=terre|nuit|lacte`). Pour chaque écran refait, y
ajouter une route et un jeu de données, puis :

```bash
# le dossier web/ n'a pas d'index.html versionné : en créer un temporaire
flutter build web -t lib/dev/home_preview.dart --profile \
  --no-web-resources-cdn --no-tree-shake-icons
```

Servir `build/web` et capturer au format iPhone (390 × 844) dans les
trois thèmes avant chaque commit.

---

## 6. Points ouverts

- **Thèmes** : seuls Sel d'Assal, Encre de Nuit et Lacté sont gardés.
  Aurore et Dusk ont été retirés ; les ids enregistrés `ocean` et `foret`
  sont ramenés à `terre` et `nuit` par `AmiinThemeVariantExt.fromId`.
- **Barre qui se réduit au défilement** : proposée, non faite.
- **Widget Android** de l'écran d'accueil du téléphone : couleurs inchangées.
- **Rendu réel** : tout a été vérifié dans un navigateur au format iPhone ;
  le flou (`BackdropFilter`) est à valider sur Android d'entrée de gamme.
