#!/usr/bin/env python3
"""Met une build Flutter web de la démo Amiin au « format téléphone ».

Usage : python3 apply_phone_format.py <dossier demo-amiin>

- index.html : ajoute un conteneur #amiin-phone. Sur ordinateur, l'app
  s'affiche dans un cadre de téléphone (390 × 844, réduit si l'écran est
  moins haut), centré sur un fond neutre ; sur téléphone et tablette
  étroite, elle occupe tout l'écran comme avant.
- flutter_bootstrap.js : demande à Flutter de dessiner dans ce conteneur
  (option hostElement du loader) au lieu de toute la page.
Idempotent : sans effet sur une build déjà traitée.
"""
import pathlib, sys

root = pathlib.Path(sys.argv[1])
index = root / "index.html"
boot = root / "flutter_bootstrap.js"

CSS = """
  <!-- Flutter n'ajoute pas cette balise quand il dessine dans un conteneur :
       sans elle, un téléphone afficherait la page en largeur « ordinateur ». -->
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
  <!-- Format téléphone : sur grand écran, l'app tient dans un cadre de
       téléphone centré ; sur mobile, elle occupe tout l'écran. -->
  <style id="amiin-phone-format">
    #amiin-phone { position: fixed; inset: 0; }
    @media (min-width: 600px) and (min-height: 560px) {
      html, body { background: radial-gradient(circle at 30% 20%, #FFFFFF 0%, #ECE9E2 60%, #E2DED5 100%); }
      #amiin-phone {
        inset: auto;
        top: 50%; left: 50%;
        transform: translate(-50%, -50%);
        height: min(844px, calc(100vh - 48px));
        /* proportions d'un iPhone, mais jamais moins large qu'un petit
           téléphone (360 px) sur les écrans peu hauts */
        width: max(360px, calc(min(844px, calc(100vh - 48px)) * 390 / 844));
        border-radius: 44px;
        overflow: hidden;
        background: #F2EFE9;
        box-shadow:
          0 0 0 10px #14213D,
          0 0 0 11px rgba(255, 255, 255, 0.08),
          0 40px 80px -20px rgba(20, 33, 61, 0.45),
          0 12px 30px -10px rgba(20, 33, 61, 0.30);
      }
    }
    @media (min-width: 600px) and (min-height: 560px) and (prefers-color-scheme: dark) {
      html, body { background: radial-gradient(circle at 30% 20%, #22335A 0%, #14213D 60%, #0D1526 100%); }
      #amiin-phone { box-shadow: 0 0 0 10px #05080F, 0 0 0 11px rgba(255,255,255,0.10), 0 40px 80px -20px rgba(0,0,0,0.6); }
    }
  </style>
"""

html = index.read_text(encoding="utf-8")
if 'id="amiin-phone-format"' not in html:
    html = html.replace("</head>", CSS + "</head>", 1)
    html = html.replace('<script src="flutter_bootstrap.js" async></script>',
                        '<div id="amiin-phone"></div>\n  <script src="flutter_bootstrap.js" async></script>', 1)
    index.write_text(html, encoding="utf-8")

js = boot.read_text(encoding="utf-8")
marker = "hostElement: document.getElementById('amiin-phone')"
if marker not in js:
    old = "_flutter.loader.load({"
    assert js.count(old) == 1, "appel _flutter.loader.load introuvable"
    js = js.replace(old, "_flutter.loader.load({\n  config: { " + marker + " },", 1)
    boot.write_text(js, encoding="utf-8")
print("format téléphone appliqué à", root)
