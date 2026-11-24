# Démo web Amiin (`/demo-amiin` sur WebSense)

Procédure pour recompiler la démo publiée dans le dépôt WebSense, dossier
`public/demo-amiin/`.

## 1. Compiler

- **Flutter 3.44.6** (moteur `83675ed276`), la version de la démo publiée.
  Avec Flutter 3.50, le démarrage web n'a pas été validé.
- Le dossier `web/` n'a pas d'`index.html` versionné (ignoré par `.gitignore`) :
  partir de celui de la démo en ligne (`public/demo-amiin/index.html` dans
  WebSense, avec le pré-loader « AMIIN » et `noindex`), en remettant
  `<base href="$FLUTTER_BASE_HREF">`.
- `--dart-define=AMIIN_DEMO=true` active le mode démo (`lib/config/demo.dart`) :
  inscription fermée, mention « Version de démonstration — accès sur
  invitation » sur la connexion, `/register` renvoyé vers `/login`.
- Les adaptations au navigateur sont automatiques (`kIsWeb`) : dictée vocale
  envoyée depuis l'URL « blob: » de l'enregistrement, export « Mes données »
  créé en mémoire, notifications locales et « Vider le cache » désactivés.

```bash
flutter build web --release --base-href /demo-amiin/ \
  --dart-define=AMIIN_DEMO=true -o /tmp/demo/demo-amiin
```

## 2. Alléger (comme la démo publiée)

```bash
cd /tmp/demo/demo-amiin
rm -f canvaskit/skwasm* canvaskit/wimp* flutter.js.map
rm -rf canvaskit/webparagraph canvaskit/experimental_webparagraph
find . -name "*.symbols" -delete
```

## 3. Format téléphone

```bash
python3 tool/demo_web/apply_phone_format.py /tmp/demo/demo-amiin
```

Sur ordinateur, l'app s'affiche dans un cadre de téléphone centré (390 × 844,
réduit sur les écrans peu hauts, jamais moins de 360 px de large) ; sur
téléphone, elle occupe tout l'écran. Le script est idempotent.

## 4. Publier

Remplacer `public/demo-amiin/` dans WebSense par le dossier obtenu, vérifier
que seuls les fichiers attendus changent, puis commiter.

## Vérifier avant de publier

Dans un navigateur : la démo doit arriver à l'écran de connexion pour un
nouveau visiteur et pour un visiteur de la version précédente (même origine,
même profil). Hors ligne ou derrière un proxy qui bloque `www.gstatic.com`,
ajouter **dans une copie de test uniquement**
`canvasKitBaseUrl: '/demo-amiin/canvaskit/'` dans la `config` de
`flutter_bootstrap.js`.
