# -*- coding: utf-8 -*-
"""
indexer_code_generique.py - Amiin Project v3
Script generique avec detection automatique du format d'articles.

FORMATS DETECTES :
  Format A : Art.X.-  ou  Art.X.bis.-   (CGI, Code Investissements, Zones Franches)
  Format B : Article X : texte...        (Marches Publics)
  Format C : Article X  (seul sur ligne) (Douanes, Commerce)

Configs disponibles :
  --code cgi       Code General des Impots (+ Investissements + Zones Franches)
  --code douanes   Code des Douanes
  --code marches   Code des Marches Publics
  --code commerce  Code de Commerce

Usage:
  python indexer_code_generique.py --code cgi
  python indexer_code_generique.py --code cgi --diag
"""

import re
import argparse
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

CONFIGS = {
    'cgi': {
        'pdf':        './Code_General_Impots_Djibouti.pdf',
        'source':     'Code General des Impots Djiboutien',
        'loi':        'Code General des Impots de la Republique de Djibouti 2011',
        'prefix_id':  'cgi',
        'pages_skip': 4,   # 4 pages de table des matieres
        # Le CGI contient aussi Code Investissements (p158) et Zones Franches (p168)
        # Ils seront indexes comme sections du meme document
    },
    'douanes': {
        'pdf':        './Code_des_Douanes_Djibouti.pdf',
        'source':     'Code des Douanes Djiboutien',
        'loi':        'Loi n101/AN/11/6eme L portant Code des Douanes 2011',
        'prefix_id':  'cd',
        'pages_skip': 2,
    },
    'marches': {
        'pdf':        './Code_Marches_Publics_Djibouti.pdf',
        'source':     'Code des Marches Publics Djiboutien',
        'loi':        'Code des Marches Publics de la Republique de Djibouti',
        'prefix_id':  'cmp',
        'pages_skip': 2,
    },
    'commerce': {
        'pdf':        './Code_de_Commerce_Djibouti.pdf',
        'source':     'Code de Commerce Djiboutien',
        'loi':        'Loi n134/AN/11/6eme L du 1er aout 2012',
        'prefix_id':  'cc',
        'pages_skip': 2,
    },
}

DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
MIN_MOTS  = 280
CIBLE     = 370
MAX_MOTS  = 480

# ── PATTERNS ─────────────────────────────────────────────────────────────────

# Format A : Art.1.-  Art.1 bis.-  Art.1.ter.-  (CGI et codes associes)
RE_ART_A = re.compile(
    r'^Art\.(\d+(?:\s*(?:bis|ter|quater))?)\.-\s*(.*)?$',
    re.IGNORECASE
)

# Format B : Article 1 : texte  /  Article 1er : texte  (Marches Publics)
RE_ART_B = re.compile(
    r'^Articles?\s+(\d+(?:er|eme)?)\s*:\s*(.*)?$',
    re.IGNORECASE
)

# Format C : Article 1  (seul sur sa ligne, contenu ligne suivante) (Douanes, Commerce)
RE_ART_C = re.compile(
    r'^Articles?\s+(\d+(?:er|eme)?)\s*$',
    re.IGNORECASE
)

# Format C variante : "Art. L.XXXX-X :" pour le Code de Commerce
RE_ART_C2 = re.compile(
    r'^Art(?:icle)?\.\s*([LRD]\.\d+(?:[.\-]\d+)*(?:\s+(?:bis|ter|quater))?)\s*[:\-]\s*(.*)?$',
    re.IGNORECASE
)

# Hierarchie
RE_LIVRE    = re.compile(r'^(?:LIVRE|Livre)\s+(.+)$')
RE_TITRE    = re.compile(r'^(?:TITRE|Titre)\s+(.+)$')
RE_CHAPITRE = re.compile(r'^(?:CHAPITRE|Chapitre)\s+(.+)$')
RE_SECTION  = re.compile(r'^(?:SECTION|Section)\s+(.+)$')
RE_SS_SEC   = re.compile(r'^(?:Sous-section|SOUS-SECTION)\s+(.+)$', re.IGNORECASE)
RE_PARA     = re.compile(r'^(?:PARAGRAPHE|Paragraphe)\s+(.+)$', re.IGNORECASE)
RE_PARTIE   = re.compile(r'^(?:PARTIE|Partie)\s+(.+)$')

RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |on |est |sont |peut |peuvent |'
    r'doit |doivent |nul |nulle |toute |tout |les dispositions |'
    r'le present |la presente |en cas de |si |lorsque |sous reserve )',
    re.IGNORECASE
)

# ── DETECTION DU FORMAT ───────────────────────────────────────────────────────

def detecter_format(pages_texte):
    nb_A = nb_B = nb_C = nb_C2 = 0
    for _, texte in pages_texte[:40]:
        for ligne in texte.split('\n'):
            l = ligne.strip()
            if RE_ART_A.match(l):   nb_A  += 1
            elif RE_ART_B.match(l): nb_B  += 1
            elif RE_ART_C.match(l): nb_C  += 1
            elif RE_ART_C2.match(l): nb_C2 += 1

    print(f"\n  Detection format :")
    print(f"    Format A (Art.X.-)     : {nb_A}")
    print(f"    Format B (Article X :) : {nb_B}")
    print(f"    Format C (Article X)   : {nb_C}")
    print(f"    Format C2 (Art.L.XXX:) : {nb_C2}")

    scores = {'A': nb_A, 'B': nb_B, 'C': nb_C, 'C2': nb_C2}
    fmt = max(scores, key=scores.get)
    print(f"    => Format retenu : {fmt}")
    return fmt

# ── TITRE SEMANTIQUE ──────────────────────────────────────────────────────────

def extraire_sujet(texte):
    if not texte:
        return ''
    texte_plat = ' '.join(texte.split())
    phrases = re.split(r'[.!?;]\s+', texte_plat)
    for phrase in phrases[:5]:
        phrase = phrase.strip()
        mots = phrase.split()
        if len(mots) < 5 or len(mots) > 22:
            continue
        if RE_GENERIQUE.match(phrase.lower()):
            continue
        sous = phrase.rstrip('.,;:')
        return sous[:110] if len(sous) <= 110 else ' '.join(sous.split()[:16]) + '...'
    return ' '.join(texte_plat.split()[:12]).rstrip('.,;:')


def construire_titre(ref_debut, ref_fin, chapitre, titre, livre, texte_groupe):
    plage = f"Art. {ref_debut}" if ref_debut == ref_fin else f"Art. {ref_debut} a {ref_fin}"
    ctx_brut = chapitre or titre or livre or ''
    ctx = re.sub(
        r'^(LIVRE|TITRE|CHAPITRE|SECTION|Section|Chapitre|Titre|Livre|'
        r'PARAGRAPHE|Paragraphe|PARTIE|Partie|Sous-section)\s+\S+\s*[:\-]?\s*',
        '', ctx_brut
    ).strip()
    if len(ctx) > 65:
        ctx = ctx[:62] + '...'
    sujet = extraire_sujet(texte_groupe)
    if ctx and sujet and sujet.lower() not in ctx.lower():
        return f"{plage} | {ctx} | {sujet}"
    elif ctx:
        return f"{plage} | {ctx}"
    elif sujet:
        return f"{plage} | {sujet}"
    return plage

# ── EXTRACTION PDF ────────────────────────────────────────────────────────────

def extraire_texte_pdf(pdf_path, pages_skip=0):
    pages = []
    with pdfplumber.open(pdf_path) as pdf:
        total = len(pdf.pages)
        print(f"PDF: {total} pages | Debut: page {pages_skip + 1}")
        for i, page in enumerate(pdf.pages):
            if i < pages_skip:
                continue
            texte = page.extract_text()
            if texte:
                # Supprimer numeros de page seuls et pied de page repete
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                texte = re.sub(r'\n\d+\n', '\n', texte)
                # Supprimer lignes de pied de page type "Djibouti - Code... 2011  5"
                texte = re.sub(r'^Djibouti\s*-\s*.+\d{4}\s+\d+\s*$', '',
                               texte, flags=re.MULTILINE | re.IGNORECASE)
                pages.append((i + 1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages

# ── PARSER ────────────────────────────────────────────────────────────────────

def normaliser_ref(ref_brut, fmt):
    """Normalise la reference pour l'ID."""
    if fmt in ('A', 'C2'):
        return re.sub(r'\s+', '_', ref_brut.strip())
    else:
        return re.sub(r'[^0-9]', '', ref_brut) or ref_brut


def parser_articles(pages_texte, fmt):
    livre = titre = chapitre = section = ss_sec = paragraphe = partie = ''
    articles = []
    art_ref = None
    art_lignes = []
    art_ctx = {}

    def ctx_full():
        parts = [p for p in [livre, partie, titre, chapitre, section, ss_sec, paragraphe] if p]
        return ' > '.join(parts)

    def ctx_court():
        return chapitre or section or ss_sec or titre or livre or partie or ''

    def sauver():
        nonlocal art_ref, art_lignes
        if art_ref is not None and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 3:
                articles.append({
                    'ref':       art_ref,
                    'texte':     texte,
                    'livre':     art_ctx.get('livre', ''),
                    'titre':     art_ctx.get('titre', ''),
                    'chapitre':  art_ctx.get('chapitre', ''),
                    'section':   art_ctx.get('section', ''),
                    'contexte':  art_ctx.get('contexte', ''),
                    'ctx_court': art_ctx.get('ctx_court', ''),
                })

    def is_struct(l):
        return bool(RE_LIVRE.match(l) or RE_TITRE.match(l) or RE_CHAPITRE.match(l)
                    or RE_SECTION.match(l) or RE_SS_SEC.match(l) or RE_PARA.match(l)
                    or RE_PARTIE.match(l))

    def is_art(l):
        return bool(RE_ART_A.match(l) or RE_ART_B.match(l) or
                    RE_ART_C.match(l) or RE_ART_C2.match(l))

    def maj_struct(ligne):
        nonlocal livre, titre, chapitre, section, ss_sec, paragraphe, partie
        m = RE_LIVRE.match(ligne)
        if m and not is_art(ligne):
            livre = f"Livre {m.group(1).strip()}"
            titre = chapitre = section = ss_sec = paragraphe = partie = ''; return True
        m = RE_PARTIE.match(ligne)
        if m and not is_art(ligne):
            partie = f"Partie {m.group(1).strip()}"
            titre = chapitre = section = ss_sec = paragraphe = ''; return True
        m = RE_TITRE.match(ligne)
        if m and not is_art(ligne):
            titre = f"Titre {m.group(1).strip()}"
            chapitre = section = ss_sec = paragraphe = ''; return True
        m = RE_CHAPITRE.match(ligne)
        if m and not is_art(ligne):
            chapitre = f"Chapitre {m.group(1).strip()}"
            section = ss_sec = paragraphe = ''; return True
        m = RE_SECTION.match(ligne)
        if m and not is_art(ligne):
            section = f"Section {m.group(1).strip()}"
            ss_sec = paragraphe = ''; return True
        m = RE_SS_SEC.match(ligne)
        if m:
            ss_sec = f"Sous-section {m.group(1).strip()}"; return True
        m = RE_PARA.match(ligne)
        if m:
            paragraphe = f"Paragraphe {m.group(1).strip()}"; return True
        return False

    texte_complet = '\n'.join(t for _, t in pages_texte)
    lignes = texte_complet.split('\n')
    n = len(lignes)
    i = 0

    while i < n:
        ligne = lignes[i].strip()

        if not ligne or re.match(r'^\d+$', ligne):
            i += 1; continue

        # Structure hierarchique
        if maj_struct(ligne):
            sauver(); art_ref = None; art_lignes = []
            # Absorber libelle sur ligne suivante si court
            if i + 1 < n:
                pr = lignes[i+1].strip()
                if pr and not is_struct(pr) and not is_art(pr) and len(pr.split()) <= 10:
                    # Ajouter au dernier element de hierarchie modifie
                    if paragraphe:
                        paragraphe += ' ' + pr
                    elif ss_sec:
                        ss_sec += ' ' + pr
                    elif section:
                        section += ' ' + pr
                    elif chapitre:
                        chapitre += ' ' + pr
                    elif titre:
                        titre += ' ' + pr
                    elif livre:
                        livre += ' ' + pr
                    i += 1
            i += 1; continue

        # Format A : Art.X.-
        if fmt == 'A':
            m2 = RE_ART_A.match(ligne)
            if m2:
                sauver()
                art_ref = normaliser_ref(m2.group(1), fmt)
                contenu = (m2.group(2) or '').strip()
                art_lignes = [contenu] if contenu else []
                art_ctx = {'livre': livre, 'titre': titre, 'chapitre': chapitre,
                           'section': section, 'contexte': ctx_full(), 'ctx_court': ctx_court()}
                i += 1; continue

        # Format B : Article X : texte
        elif fmt == 'B':
            m2 = RE_ART_B.match(ligne)
            if m2:
                sauver()
                art_ref = normaliser_ref(m2.group(1), fmt)
                contenu = (m2.group(2) or '').strip()
                art_lignes = [contenu] if contenu else []
                art_ctx = {'livre': livre, 'titre': titre, 'chapitre': chapitre,
                           'section': section, 'contexte': ctx_full(), 'ctx_court': ctx_court()}
                i += 1; continue

        # Format C : Article X seul
        elif fmt == 'C':
            m2 = RE_ART_C.match(ligne)
            if m2:
                sauver()
                art_ref = normaliser_ref(m2.group(1), fmt)
                art_lignes = []
                art_ctx = {'livre': livre, 'titre': titre, 'chapitre': chapitre,
                           'section': section, 'contexte': ctx_full(), 'ctx_court': ctx_court()}
                i += 1; continue

        # Format C2 : Art. L.XXX-X :
        elif fmt == 'C2':
            m2 = RE_ART_C2.match(ligne)
            if m2:
                sauver()
                art_ref = normaliser_ref(m2.group(1), fmt)
                contenu = (m2.group(2) or '').strip()
                art_lignes = [contenu] if contenu else []
                art_ctx = {'livre': livre, 'titre': titre, 'chapitre': chapitre,
                           'section': section, 'contexte': ctx_full(), 'ctx_court': ctx_court()}
                i += 1; continue

        # Corps de l'article
        if art_ref is not None and ligne and len(ligne) > 2:
            art_lignes.append(ligne)

        i += 1

    sauver()
    return articles

# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return (a['livre'] == b['livre'] and a['titre'] == b['titre']
            and a['chapitre'] == b['chapitre'])


def ref_to_id(ref):
    return re.sub(r'[^a-zA-Z0-9]', '_', str(ref))


def emettre_chunk(groupe, source, loi, prefix_id):
    if not groupe:
        return None
    premier, dernier = groupe[0], groupe[-1]
    lignes = []
    for art in groupe:
        lignes += [f"Article {art['ref']}", art['texte'], '']
    texte_groupe = '\n'.join(lignes).strip()
    titre = construire_titre(premier['ref'], dernier['ref'],
                             premier['chapitre'], premier['titre'],
                             premier['livre'], texte_groupe)
    cid = (f"{prefix_id}_{ref_to_id(premier['ref'])}" if premier['ref'] == dernier['ref']
           else f"{prefix_id}_{ref_to_id(premier['ref'])}_{ref_to_id(dernier['ref'])}")
    return {
        'id': cid, 'titre': titre,
        'document': f"{titre}\n\n{texte_groupe}",
        'metadata': {
            'article_ref': str(premier['ref']), 'article_ref_fin': str(dernier['ref']),
            'livre': premier['livre'], 'titre': premier['titre'],
            'chapitre': premier['chapitre'], 'section': premier['section'],
            'contexte': premier['contexte'],
            'source': source, 'loi': loi, 'category': CATEGORIE,
            'title': titre, 'url': source,
        }
    }


def regrouper_articles(articles, source, loi, prefix_id):
    chunks = []
    i = 0
    while i < len(articles):
        art = articles[i]
        mots = len(art['texte'].split())
        if mots > MAX_MOTS:
            tous = art['texte'].split()
            step = MAX_MOTS - 50
            for k in range(0, len(tous), step):
                sous = ' '.join(tous[k:k+MAX_MOTS])
                if len(sous.split()) < 20:
                    continue
                part = k // step
                tp = construire_titre(art['ref'], art['ref'], art['chapitre'],
                                      art['titre'], art['livre'], sous)
                if part > 0:
                    tp += f' (suite {part+1})'
                chunks.append({
                    'id': f"{prefix_id}_{ref_to_id(art['ref'])}_p{part}",
                    'titre': tp,
                    'document': f"{tp}\n\nArticle {art['ref']}\n{sous}",
                    'metadata': {
                        'article_ref': str(art['ref']), 'article_ref_fin': str(art['ref']),
                        'livre': art['livre'], 'titre': art['titre'],
                        'chapitre': art['chapitre'], 'section': art['section'],
                        'contexte': art['contexte'],
                        'source': source, 'loi': loi, 'category': CATEGORIE,
                        'title': tp, 'url': source,
                    }
                })
            i += 1; continue

        groupe = [art]
        mg = mots
        j = i + 1
        while j < len(articles):
            s = articles[j]
            ms = len(s['texte'].split())
            if not meme_ctx(art, s):
                break
            if mg + ms > MAX_MOTS:
                if mg < MIN_MOTS:
                    groupe.append(s); mg += ms; j += 1
                break
            groupe.append(s); mg += ms; j += 1
            if mg >= CIBLE:
                break
        c = emettre_chunk(groupe, source, loi, prefix_id)
        if c:
            chunks.append(c)
        i = j
    return chunks

# ── SUPPRESSION + INGESTION ───────────────────────────────────────────────────

def supprimer_anciens(collection, source):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == source]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"[OK] {len(ids)} anciens supprimes")
    else:
        print("[INFO] Aucun ancien chunk")


def ingerer(chunks, collection, model):
    print(f"Ingestion {len(chunks)} chunks...")
    ingeres = doublons = 0
    for k, chunk in enumerate(chunks):
        emb = model.encode(chunk['document']).tolist()
        try:
            collection.add(ids=[chunk['id']], embeddings=[emb],
                           documents=[chunk['document']], metadatas=[chunk['metadata']])
            ingeres += 1
        except Exception:
            doublons += 1
        if (k+1) % 100 == 0:
            print(f"  {k+1}/{len(chunks)}...")
    print(f"[OK] Ingeres: {ingeres} | Doublons: {doublons}")
    return ingeres

# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--code', required=True, choices=list(CONFIGS.keys()))
    ap.add_argument('--diag', action='store_true')
    args = ap.parse_args()

    cfg = CONFIGS[args.code]
    SOURCE, LOI, PREFIX_ID = cfg['source'], cfg['loi'], cfg['prefix_id']

    print("=" * 65)
    print(f"INDEXATION : {SOURCE}")
    print("=" * 65)

    print("\n[1/5] Extraction PDF...")
    pages = extraire_texte_pdf(cfg['pdf'], cfg['pages_skip'])

    if args.diag:
        print("\n=== DIAGNOSTIC : 50 premieres lignes ===")
        txt = '\n'.join(t for _, t in pages[:4])
        for j, l in enumerate(txt.split('\n')[:50]):
            print(f"  [{j:02d}] {repr(l.strip())}")
        print("=== FIN DIAGNOSTIC ===\n")

    print("\n[2/5] Detection format + parsing...")
    fmt = detecter_format(pages)
    articles = parser_articles(pages, fmt)
    print(f"Articles detectes: {len(articles)}")

    if len(articles) == 0:
        print("\n[ERREUR] 0 articles. Lance avec --diag pour voir le format brut.")
        exit(1)

    for livre, n in Counter(a['livre'] for a in articles).most_common(6):
        print(f"  {livre[:60]:<60} {n}")

    print("\n[3/5] Regroupement...")
    chunks = regrouper_articles(articles, SOURCE, LOI, PREFIX_ID)
    ml = [len(c['document'].split()) for c in chunks]
    if ml:
        print(f"Chunks: {len(chunks)} | Moy: {sum(ml)//len(ml)}m | Min: {min(ml)}m | Max: {max(ml)}m")
        dist = Counter()
        for w in ml:
            b = '<100' if w<100 else '100-200' if w<200 else '200-300' if w<300 else '300-400' if w<400 else '400-500' if w<500 else '500+'
            dist[b] += 1
        for k in ['<100','100-200','200-300','300-400','400-500','500+']:
            print(f"  {k:<10} {dist[k]:>4}  {'#'*(dist[k]//3)}")

    print("\nExemples de titres:")
    step = max(1, len(chunks)//8)
    for c in chunks[::step][:8]:
        print(f"  [{len(c['document'].split()):>3}m] {c['titre']}")

    print("\n[4/5] ChromaDB...")
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"Base avant: {collection.count()} chunks")
    supprimer_anciens(collection, SOURCE)

    print("\n[5/5] Ingestion...")
    nb = ingerer(chunks, collection, model)
    print(f"\n{'='*65}")
    print(f"TERMINE | {SOURCE}: {nb} chunks | Base: {collection.count()} total")