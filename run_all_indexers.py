# -*- coding: utf-8 -*-
"""
run_all_indexers.py - Amiin Project
Lance tous les scripts d'indexation sequentiellement et verifie l'integrite
de la base ChromaDB a la fin.

Usage (depuis D:\projet\Agent Amiin) :
  & "D:\projet\Agent Amiin\amiin_env\Scripts\python.exe" .\run_all_indexers.py

Log complet dans : amiin_indexation.log
"""

import subprocess
import sys
import os
import time
import sqlite3
from datetime import datetime
from collections import Counter

# ── CONFIG ────────────────────────────────────────────────────────────────────

PYTHON    = r"D:\projet\Agent Amiin\amiin_env\Scripts\python.exe"
WORKDIR   = r"D:\projet\Agent Amiin"
DB_PATH   = r"D:\projet\Agent Amiin\amiin_db\chroma.sqlite3"
LOG_FILE  = r"D:\projet\Agent Amiin\amiin_indexation.log"

# Liste ordonnee des commandes a executer
TACHES = [
    {
        'label': 'Code de la Route',
        'cmd':   [PYTHON, 'indexer_code_route.py'],
    },
    {
        'label': 'Code des Investissements',
        'cmd':   [PYTHON, 'indexer_droit_afrique.py', '--code', 'investissements'],
    },
    {
        'label': 'Code des Zones Franches',
        'cmd':   [PYTHON, 'indexer_droit_afrique.py', '--code', 'zones_franches'],
    },
    {
        'label': 'Code des Peches',
        'cmd':   [PYTHON, 'indexer_droit_afrique.py', '--code', 'peches'],
    },
    {
        'label': 'Code Petrolier',
        'cmd':   [PYTHON, 'indexer_droit_afrique.py', '--code', 'petrolier'],
    },
    {
        'label': 'Code Minier',
        'cmd':   [PYTHON, 'indexer_droit_afrique.py', '--code', 'minier'],
    },
    {
        'label': 'Code de l Environnement',
        'cmd':   [PYTHON, 'indexer_codes_divers.py', '--code', 'environnement'],
    },
    {
        'label': 'Code d Arbitrage International',
        'cmd':   [PYTHON, 'indexer_codes_divers.py', '--code', 'arbitrage'],
    },
]

# ── LOGGING ───────────────────────────────────────────────────────────────────

log_file = open(LOG_FILE, 'w', encoding='utf-8', buffering=1)

def log(msg, also_print=True):
    ts = datetime.now().strftime('%H:%M:%S')
    ligne = f"[{ts}] {msg}"
    log_file.write(ligne + '\n')
    if also_print:
        print(ligne)

def separateur(car='=', n=65):
    log(car * n)

# ── BARRE DE PROGRESSION SIMPLE ───────────────────────────────────────────────

def barre(fait, total, largeur=40):
    pct = fait / total if total else 0
    plein = int(pct * largeur)
    return f"[{'█'*plein}{'░'*(largeur-plein)}] {fait}/{total} ({pct*100:.0f}%)"

# ── LANCEMENT SEQUENTIEL ──────────────────────────────────────────────────────

def lancer_taches():
    resultats = []
    total = len(TACHES)

    separateur()
    log(f"AMIIN - INDEXATION SEQUENTIELLE")
    log(f"Debut : {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}")
    log(f"Dossier : {WORKDIR}")
    log(f"Taches  : {total}")
    separateur()

    for idx, tache in enumerate(TACHES, 1):
        label = tache['label']
        cmd   = tache['cmd']

        separateur('-')
        log(f"TACHE {idx}/{total} : {label}")
        log(f"Commande : {' '.join(cmd)}")
        log(barre(idx - 1, total))
        separateur('-')

        debut = time.time()
        ok = False
        chunks_ajoutes = 0

        try:
            proc = subprocess.Popen(
                cmd,
                cwd=WORKDIR,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding='utf-8',
                errors='replace'
            )

            # Afficher la sortie en temps reel ET dans le log
            sortie_lignes = []
            for ligne in proc.stdout:
                ligne = ligne.rstrip()
                sortie_lignes.append(ligne)
                log(f"  | {ligne}")

                # Detecter le nombre de chunks ineres
                import re
                m = re.search(r'Ingeres:\s*(\d+)', ligne)
                if m:
                    chunks_ajoutes = int(m.group(1))
                m2 = re.search(r'TERMINE.+?:\s*(\d+)\s*chunks', ligne)
                if m2:
                    chunks_ajoutes = int(m2.group(1))

            proc.wait()
            duree = time.time() - debut
            ok = (proc.returncode == 0)

        except FileNotFoundError as e:
            log(f"  [ERREUR] Fichier introuvable : {e}")
            duree = time.time() - debut
            ok = False
        except Exception as e:
            log(f"  [ERREUR] Exception : {e}")
            duree = time.time() - debut
            ok = False

        statut = "OK" if ok else "ECHEC"
        log(f"\n  Resultat : {statut} | Duree : {duree:.1f}s | Chunks : {chunks_ajoutes}")
        log(barre(idx, total))

        resultats.append({
            'label':   label,
            'ok':      ok,
            'duree':   duree,
            'chunks':  chunks_ajoutes,
        })

        # Pause courte entre les scripts pour laisser ChromaDB se stabiliser
        if idx < total:
            log(f"  Pause 3s avant la prochaine tache...")
            time.sleep(3)

    return resultats

# ── VERIFICATION DE LA BASE ───────────────────────────────────────────────────

def verifier_base():
    separateur()
    log("VERIFICATION INTEGRITE ET QUALITE DE LA BASE CHROMADB")
    separateur()

    if not os.path.exists(DB_PATH):
        log(f"[ERREUR] Base introuvable : {DB_PATH}")
        return False

    taille_mo = os.path.getsize(DB_PATH) / (1024 * 1024)
    log(f"Fichier : {DB_PATH}")
    log(f"Taille  : {taille_mo:.1f} Mo")

    try:
        conn = sqlite3.connect(DB_PATH)
        cur  = conn.cursor()

        # 1. Nombre total de chunks
        cur.execute("SELECT COUNT(*) FROM embeddings")
        total = cur.fetchone()[0]
        log(f"\nTotal chunks en base : {total}")

        # 2. Chunks par source
        cur.execute("""
            SELECT em.string_value, COUNT(DISTINCT e.id) as n
            FROM embeddings e
            JOIN embedding_metadata em ON e.id = em.id
            WHERE em.key = 'source'
            GROUP BY em.string_value
            ORDER BY n DESC
        """)
        sources = cur.fetchall()
        log(f"\nChunks par source ({len(sources)} sources) :")
        for src, n in sources:
            log(f"  {src:<55} {n:>5} chunks")

        # 3. Chunks par categorie
        cur.execute("""
            SELECT em.string_value, COUNT(DISTINCT e.id) as n
            FROM embeddings e
            JOIN embedding_metadata em ON e.id = em.id
            WHERE em.key = 'category'
            GROUP BY em.string_value
            ORDER BY n DESC
        """)
        cats = cur.fetchall()
        log(f"\nChunks par categorie :")
        for cat, n in cats:
            log(f"  {cat:<30} {n:>5} chunks")

        # 4. Chunks sans embedding (anomalie)
        cur.execute("""
            SELECT COUNT(*) FROM embeddings e
            WHERE NOT EXISTS (
                SELECT 1 FROM embedding_fulltext_search efs WHERE efs.rowid = e.rowid
            )
        """)
        # Note : cette table peut ne pas exister selon la version de ChromaDB
        # On verifie autrement
        cur.execute("SELECT COUNT(*) FROM embeddings")
        nb_embeddings = cur.fetchone()[0]

        # 5. Verifier que chaque chunk a un titre (metadonnee 'title')
        cur.execute("""
            SELECT COUNT(DISTINCT e.id) FROM embeddings e
            WHERE NOT EXISTS (
                SELECT 1 FROM embedding_metadata em
                WHERE em.id = e.id AND em.key = 'title'
            )
        """)
        sans_titre = cur.fetchone()[0]

        # 6. Chunks trop courts (document < 50 mots)
        cur.execute("""
            SELECT COUNT(*) FROM embeddings e
            JOIN embedding_metadata em ON e.id = em.id
            WHERE em.key = 'chroma:document'
              AND LENGTH(em.string_value) - LENGTH(REPLACE(em.string_value, ' ', '')) < 50
        """)
        trop_courts = cur.fetchone()[0]

        # 7. Chunks tres longs (document > 3000 caracteres)
        cur.execute("""
            SELECT COUNT(*) FROM embeddings e
            JOIN embedding_metadata em ON e.id = em.id
            WHERE em.key = 'chroma:document'
              AND LENGTH(em.string_value) > 3000
        """)
        tres_longs = cur.fetchone()[0]

        # 8. Doublons d'IDs (ne devrait pas arriver)
        cur.execute("""
            SELECT id, COUNT(*) as n FROM embeddings
            GROUP BY id HAVING n > 1
        """)
        doublons = cur.fetchall()

        # 9. Sources manquantes (chunks sans source)
        cur.execute("""
            SELECT COUNT(DISTINCT e.id) FROM embeddings e
            WHERE NOT EXISTS (
                SELECT 1 FROM embedding_metadata em
                WHERE em.id = e.id AND em.key = 'source'
            )
        """)
        sans_source = cur.fetchone()[0]

        conn.close()

        # ── RAPPORT QUALITE ──────────────────────────────────────────────────

        separateur('-')
        log("RAPPORT QUALITE")
        separateur('-')

        alertes = []

        log(f"Total chunks          : {total}")
        log(f"Chunks sans titre     : {sans_titre}" + (" [ALERTE]" if sans_titre > 0 else " [OK]"))
        log(f"Chunks sans source    : {sans_source}" + (" [ALERTE]" if sans_source > 0 else " [OK]"))
        log(f"Chunks trop courts    : {trop_courts}" + (" [ATTENTION]" if trop_courts > 20 else " [OK]"))
        log(f"Chunks tres longs     : {tres_longs}" + (" [ATTENTION]" if tres_longs > 10 else " [OK]"))
        log(f"IDs en doublon        : {len(doublons)}" + (" [ALERTE]" if doublons else " [OK]"))

        if sans_titre > 0:
            alertes.append(f"{sans_titre} chunks sans titre")
        if sans_source > 0:
            alertes.append(f"{sans_source} chunks sans source")
        if doublons:
            alertes.append(f"{len(doublons)} IDs en doublon")
        if trop_courts > 50:
            alertes.append(f"{trop_courts} chunks tres courts (<50 mots)")

        separateur('-')
        if alertes:
            log("ALERTES DETECTEES :")
            for a in alertes:
                log(f"  [!] {a}")
        else:
            log("Aucune alerte - Base en bon etat")
        separateur('-')

        return len(alertes) == 0

    except Exception as e:
        log(f"[ERREUR] Impossible de lire la base : {e}")
        return False

# ── RESUME FINAL ──────────────────────────────────────────────────────────────

def afficher_resume(resultats, base_ok):
    separateur()
    log("RESUME FINAL")
    separateur()

    ok_count   = sum(1 for r in resultats if r['ok'])
    fail_count = sum(1 for r in resultats if not r['ok'])
    total_chunks = sum(r['chunks'] for r in resultats)
    duree_totale = sum(r['duree'] for r in resultats)

    log(f"Taches reussies   : {ok_count}/{len(resultats)}")
    log(f"Taches echouees   : {fail_count}/{len(resultats)}")
    log(f"Chunks ajoutes    : {total_chunks}")
    log(f"Duree totale      : {duree_totale/60:.1f} minutes")
    log(f"Integrite base    : {'OK' if base_ok else 'PROBLEMES DETECTES'}")
    log(f"Log complet       : {LOG_FILE}")

    if fail_count > 0:
        log("\nTaches echouees :")
        for r in resultats:
            if not r['ok']:
                log(f"  [ECHEC] {r['label']}")

    log("\nDetail par tache :")
    for r in resultats:
        statut = "[OK]   " if r['ok'] else "[ECHEC]"
        log(f"  {statut} {r['label']:<45} {r['chunks']:>4} chunks  {r['duree']:>6.1f}s")

    separateur()
    fin = datetime.now().strftime('%d/%m/%Y %H:%M:%S')
    log(f"Fin : {fin}")
    log("Indexation terminee.")
    separateur()

# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    try:
        resultats = lancer_taches()
        base_ok   = verifier_base()
        afficher_resume(resultats, base_ok)
    except KeyboardInterrupt:
        log("\n[INTERRUPTION] Arret demande par l utilisateur (Ctrl+C)")
        log("La base ChromaDB peut etre dans un etat intermediaire.")
    finally:
        log_file.close()
