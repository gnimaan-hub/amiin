# Audit graphique Amiin — état des lieux pré-refonte

> Généré le 2026-07-15 sur la branche `claude/project-feedback-wmqk2o`.
> Méthode : inventaire exhaustif de `lib/theme/`, `lib/widgets/`, `lib/screens/`
> (greps quantitatifs + lecture des composants), scores type Lighthouse par
> catégorie. Ce document est la base de référence du chantier de refonte.

## 1. Architecture graphique actuelle (comment c'est construit)

### Le système de tokens — `lib/theme/`
| Fichier | Contenu | État |
|---|---|---|
| `colors.dart` | Palette Djibouti statique (`ColorsAmiin`) + `CategoryColors` (annuaire, éducation) | Sain — ne sert plus qu'aux écrans auth/splash (identité sombre fixe) et aux palettes catégorielles |
| `themes.dart` | `AmiinThemeColors` (ThemeExtension, 28 tokens) × 4 variantes (terre, ocean, foret, nuit) + `context.ac` + theming Material (appBar, card, input, dialog, snackbar, chip, switch, divider, elevatedButton) | **Le cœur sain du système** — migration `context.ac` faite sur 100 % des écrans |
| `spacing.dart` | `Spacing` (4→48), `RadiusAmiin` (6/10/14/20/full), `ShadowAmiin` (sm/md/lg) | Sain mais adoption partielle |
| `typography.dart` | 3 familles Google Fonts (Inter=geo, DM Sans=sans, Space Mono=mono), `FontSize`, `LineHeight`, `LetterSpacing`, helpers `TextStyles` | **Helpers morts et buggés** (voir §3.2) |

### La bibliothèque de composants — `lib/widgets/` (12 widgets)
`AmiinCard` (5 variantes), `AmiinButton` (5 variantes × 3 tailles), `AmiinTag`,
`AmiinHeader` (+ `HorizonLine` animée par mode), `AmiinToast`, `SkeletonBox/Card`,
`EmptyState`, `AmiinSearchBar`, `ChatNoteCard`, `ConnectivityBanner`, `AmiinLogo`.

### Les concepts d'identité conçus (mais sous-exploités)
- **Dualité sémantique** : turquoise = « secrétariat » (chat, agenda, notes),
  ocre = « information » (annuaire, démarches). Portée par les tokens
  `secretariatAccent`/`infoAccent` et par `AmiinMode` dans le header.
- **Ligne d'horizon** (`HorizonLine`) : trait animé signature sous le header,
  colorée selon le mode.
- **Hero sombre** : accueil/auth en dégradé Encre de Nuit, reste de l'app clair.

## 2. Scores Lighthouse graphique

| Catégorie | Score | Verdict en une ligne |
|---|---:|---|
| Couleurs & thèmes | **90** | Excellent : 4 variantes, 28 tokens, 0 couleur en dur restante hors palettes assumées |
| Espacements & formes | **65** | 314 usages `Spacing` mais 65 paddings en dur ; 51 `RadiusAmiin` contre 47 `circular()` en dur (12 valeurs différentes) |
| Composants partagés | **55** | Bonne bibliothèque, adoption inégale : `AmiinCard` 34✓, mais `AmiinButton` 4, `SkeletonBox` 0 dans les écrans, 75 `BoxDecoration` artisanales |
| Typographie | **45** | 3 familles bien choisies, MAIS 280 `TextStyle` inline, 17 tailles distinctes (dont 9, 10.5, 17 hors échelle), helpers `TextStyles` jamais utilisés ET cassés en sombre |
| Marque & identité | **40** | La dualité info/secrétariat n'est JAMAIS exercée (23 headers, tous en mode `neutral`) ; pack `amiin-icons` aux couleurs de l'ancienne marque « terra » |
| Feedback & dialogues | **35** | 70 `SnackBar` Material vs 9 `AmiinToast` : deux langages concurrents ; 17 `AlertDialog` bruts |
| Iconographie | **30** | 3 systèmes mélangés : 106 icônes Material distinctes + 13 SVG inline dans le code + emojis ; aucun set unifié |
| Motion & animations | **25** | 0 transition de page personnalisée (go_router par défaut), squelettes jamais branchés, micro-interactions quasi absentes hors chat |
| **Global pondéré** | **≈ 48** | Fondations solides, couche d'expression très pauvre — d'où l'impression « basique et fade » |

## 3. Incohérences détaillées

### 3.1 Deux arrondis de carte différents
`AmiinCard` code `BorderRadius.circular(12)` en dur alors que le token carte
est `RadiusAmiin.lg = 14`. Les cartes faites à la main utilisent tantôt 10,
tantôt 12, tantôt 14 → trois générations d'arrondis coexistent à l'écran.

### 3.2 `TextStyles` : helpers morts et dangereux
`TextStyles.screenTitle/body/label…` : **0 usage** dans l'app, et ils
référencent `ColorsAmiin.ink/muted` statiques → les utiliser tels quels
casserait le mode sombre. À réécrire theme-aware (`context.ac`) puis à imposer.

### 3.3 Échelle typographique non respectée
Distribution réelle des tailles inline : 12(×57), 13(×49), 11(×35), 14(×32),
10(×28), 15(×20)… plus 9, 10.5, 17, 26 hors de l'échelle `FontSize`.
`FontSize.*` : 3 usages au total. Chaque écran redéclare famille+taille+couleur
à la main → dérive inévitable.

### 3.4 Feedback : SnackBar partout, Toast nulle part
70 `SnackBar` Material (verts/roses système, plein écran bas) contre 9
`AmiinToast` (pilule flottante de la marque). Le pire écran : note_detail (11).
Un seul canal devrait exister.

### 3.5 Le header n'exprime jamais la dualité de marque
`AmiinHeader(mode: …)` accepte `secretariat`/`info`/`neutral` et colore la
ligne d'horizon en conséquence — **aucun des 23 écrans ne passe le paramètre**.
Annuaire et démarches devraient être ocre, agenda/notes/chat turquoise.

### 3.6 Iconographie éclatée
- 106 icônes Material différentes (mélange `_outlined`, `_rounded`, sans suffixe) ;
- 13 SVG dessinés à la main en constantes chaîne dans 7 fichiers d'écrans ;
- emojis comme icônes (widget Android, catégories annuaire).
Aucune règle de style (grosseur de trait, coins) → texture visuelle hétérogène.

### 3.7 Marque désynchronisée
`amiin-icons/` (pack launcher/store) est resté aux couleurs de l'ancienne
identité « terra » (#B85530) alors que l'app est turquoise/ocre. L'icône
d'app ne correspond plus à l'interface.

### 3.8 Motion inexistante
- Transitions de pages : celles par défaut de la plateforme, aucune
  `CustomTransitionPage` dans le routeur.
- `SkeletonBox`/`SkeletonCard` existent, thémés, animés — et ne sont montés
  nulle part (les écrans affichent spinner ou rien pendant les chargements).
- Aucune micro-interaction au tap (scale/opacity) sur cartes et tuiles.

### 3.9 Divers
- 75 `BoxDecoration` à la main dans les écrans (cartes, chips, badges
  artisanaux) qui dupliquent des variantes possibles d'`AmiinCard`/`AmiinTag`.
- `EmptyState` : bon composant, mais icônes passées en `Opacity(0.5)` sans
  illustration — états vides tristes.
- 2 ombres portées dans toute l'app : interface très « plate » sans hiérarchie
  de profondeur.

## 4. Plan de refonte proposé (4 phases)

### Phase 1 — Fondations typographiques et formes (le plus rentable)
1. Réécrire `TextStyles` theme-aware (`context.ac`) : ~8 styles nommés
   (displayTitle, screenTitle, sectionLabel, cardTitle, body, bodyMuted,
   caption, sourceRef) et **migrer les 280 TextStyle inline**.
2. Normaliser l'échelle : plus aucune taille hors `FontSize`.
3. Unifier les rayons : cartes = `RadiusAmiin.lg` partout (fix `AmiinCard`
   inclus), chips = `full`, inputs = `md` ; éliminer les 47 `circular()` en dur.
4. Absorber les 65 paddings en dur dans `Spacing`.

### Phase 2 — Composants uniques
1. Un seul canal de feedback : étendre `AmiinToast` (variantes info/succès/
   erreur + action optionnelle) et remplacer les 70 SnackBar.
2. `AmiinDialog` de marque (remplace les 17 AlertDialog bruts).
3. Brancher `SkeletonCard` sur tous les chargements de listes (annuaire,
   agenda, démarches, notes).
4. Généraliser `AmiinButton` (4 usages aujourd'hui) et créer `AmiinListTile`
   pour absorber les 75 décorations artisanales.

### Phase 3 — Identité et iconographie
1. Exercer la dualité : passer `mode:` sur les 23 headers (ocre = annuaire/
   démarches, turquoise = chat/agenda/notes, neutral = réglages/accueil).
2. Choisir UN langage d'icônes : `Icons.*_rounded` systématique (option
   simple) ou set custom SVG (option marque) ; sortir les 13 SVG inline dans
   un fichier d'icônes unique.
3. Regénérer le pack `amiin-icons` aux couleurs actuelles (Encre de Nuit +
   turquoise) et mettre à jour l'icône launcher.
4. Illustrations d'états vides (style ligne, palette Djibouti).

### Phase 4 — Motion (ce qui fera « waouh »)
1. Transitions de pages go_router : fade-through 250 ms entre onglets,
   slide-up pour les écrans de création.
2. Micro-interactions : scale 0.98 au tap des cartes/tuiles, haptique légère.
3. Entrées en cascade des listes (stagger 40 ms).
4. Profondeur : appliquer `ShadowAmiin` de façon systématique (cartes sm,
   éléments flottants md, modales lg).

---
*Chiffres mesurés par grep sur l'arbre `lib/` au moment de l'audit ; ils
serviront de baseline pour mesurer la progression de chaque phase.*

---

## 5. État d'avancement de la refonte (mise à jour post-exécution)

| Phase | Fait | Reste |
|---|---|---|
| P1 Fondations | TextStyles réécrits theme-aware (8 styles) ; AmiinCard sur RadiusAmiin.lg ; 33 rayons + 36 paddings + 9 tailles hors échelle normalisés | Migration progressive des ~280 TextStyle inline vers TextStyles (écran par écran, lors des retouches) |
| P2 Composants | 31 SnackBar → AmiinToast ; skeletons déjà branchés sur les 4 listes (correction de baseline : l'audit cherchait SkeletonBox, les écrans utilisent SkeletonList) | 7 SnackBar complexes (action/duration) ; AmiinDialog dédié (AlertDialog reste thémé via dialogTheme) ; AmiinListTile |
| P3 Identité | Dualité activée sur 10 headers (ocre = annuaire/démarches, turquoise = agenda/notes) ; 12 SVG centralisés dans widgets/amiin_svg_icons.dart | Choix d'un langage d'icônes Material unique ; regénération du pack amiin-icons aux couleurs actuelles (nécessite un outil graphique) |
| P4 Motion | Press 0.98 + haptique sur toutes les AmiinCard ; transitions fondu+glissement sur les 18 sous-routes ; EmptyState avec pastille teintée | Entrées en cascade des listes ; hero du logo splash→accueil |

**Mesures après refonte** : 14 rayons en dur restants (valeurs 2-4 pour les
indicateurs, assumées) ; 7 SnackBar restants (complexes) ; 10 headers colorés ;
0 SVG inline dans les écrans ; 18 transitions de pages actives.
