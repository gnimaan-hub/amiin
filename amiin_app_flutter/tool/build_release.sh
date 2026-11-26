#!/usr/bin/env bash
# ─── Build release Android d'Amiin (Play Store) ──────────────────────────────
# Usage (depuis amiin_app_flutter/) :
#   tool/build_release.sh            → app bundle (.aab) pour le Play Store
#   tool/build_release.sh apk        → APK (distribution directe / tests)
#
# Prérequis : android/key.properties (clé d'upload). Sans elle, Gradle refuse
# le build (voir android/app/build.gradle.kts).
#
# --obfuscate : noms de classes/fonctions Dart illisibles dans le binaire.
# --split-debug-info : symboles écrits dans symbols/<version>/ (ignoré par git).
#   À CONSERVER pour chaque version publiée : sans eux, les traces de plantage
#   sont indéchiffrables (flutter symbolize -i trace.txt -d symbols/<version>/…).
set -euo pipefail
cd "$(dirname "$0")/.."

target="${1:-appbundle}"
case "$target" in appbundle|apk) ;; *) echo "Cible inconnue : $target (appbundle|apk)"; exit 1;; esac

if [[ ! -f android/key.properties && "${AMIIN_ALLOW_DEBUG_SIGNING:-}" != "1" ]]; then
  echo "android/key.properties manquant : impossible de signer la release." >&2
  exit 1
fi

version="$(grep -E '^version:' pubspec.yaml | awk '{print $2}')"
symbols="symbols/${version}"
mkdir -p "$symbols"

flutter build "$target" --release \
  --obfuscate --split-debug-info="$symbols" \
  --dart-define=AMIIN_API_URL="${AMIIN_API_URL:-https://amiin.onrender.com/v1}"

echo "OK — version $version, symboles dans $symbols (à archiver)."
