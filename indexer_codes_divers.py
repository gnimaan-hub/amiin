# -*- coding: utf-8 -*-
"""
indexer_codes_divers.py - Amiin Project
Script pour le Code de l'Environnement et le Code d'Arbitrage International.

  --code environnement   (41p, ARTICLE Xer : inline, CHAPITRE I : DES DEFINITIONS)
  --code arbitrage       (8p,  Article X : inline, pas de hierachie Livre/Titre)

Usage:
  python indexer_codes_divers.py --code environnement
  python indexer_codes_divers.py --code arbitrage
  python indexer_codes_divers.py --code environnement --diag
"""

import re, argparse, chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

CONFIGS = {
    'environnement': {
        'pdf':       './code-de-l-environnement.pdf',
        'source':    'Code de l Environnement Djiboutien',
        'loi':       'Loi n106/AN/00/4eme L du 29 octobre 2000 portant Loi-Cadre sur l Environnement',
        'prefix_id': 'ce',
        'pages_skip': 3,   # 3 pages de vus/visas avant le contenu
    },
    'arbitrage': {
        'pdf':       './code-djiboutien-de-larbitrage-international.pdf',
        'source':    'Code Djiboutien de l Arbitrage International',
        'loi':       'Code Djiboutien de l Arbitrage International',
        'prefix_id': 'cai',
        'pages_skip': 1,
    },
}

DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
MIN_MOTS, CIBLE, MAX_MOTS = 250, 350, 450

# Code de l'Environnement : ARTICLE 1er :  /  ARTICLE 2 :
RE_ART_ENV = re.compile(r'^ARTICLE\s+(\d+(?:er|eme)?)\s*[:\-]\s*(.*)?$', re.IGNORECASE)

# Code Arbitrage : Article 1 :  /  Article 6 :
RE_ART_ARB = re.compile(r'^Article\s+(\d+)\s*[:\-]\s*(.*)?$', re.IGNORECASE)

# Hierarchie environnement
RE_CHAPITRE = re.compile(r'^CHAPITRE\s+([IVXivx]+|[0-9]+)\s*[:\-]?\s*(.*)?$', re.IGNORECASE)
RE_SECTION  = re.compile(r'^(?:SECTION|Section)\s+([IVXivx]+|[0-9]+)\s*[:\-]?\s*(.*)?$', re.IGNORECASE)
RE_TITRE    = re.compile(r'^(?:TITRE|Titre)\s+(.+)$', re.IGNORECASE)

RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |est |sont |peut |toute |tout |nul |au sens)',
    re.IGNORECASE
)


def extraire_sujet(texte):
    for phrase in re.split(r'[.!?;]\s+', ' '.join(texte.split()))[:5]:
        mots = phrase.strip().split()
        if 5 <= len(mots) <= 22 and not RE_GENERIQUE.match(phrase.strip().lower()):
            s = phrase.strip().rstrip('.,;:')
            return s[:110] if len(s) <= 110 else ' '.join(s.split()[:16]) + '...'
    return ' '.join(texte.split()[:12]).rstrip('.,;:')


def construire_titre(ref_debut, ref_fin, chapitre, titre_sec, texte):
    plage = f"Article {ref_debut}" if ref_debut == ref_fin else f"Articles {ref_debut} a {ref_fin}"
    ctx_brut = chapitre or titre_sec or ''
    ctx = re.sub(r'^(CHAPITRE|SECTION|TITRE|Titre|Chapitre|Section)\s+\S+\s*[:\-]?\s*', '', ctx_brut).strip()
    if len(ctx) > 65: ctx = ctx[:62] + '...'
    sujet = extraire_sujet(texte)
    if ctx and sujet and sujet.lower() not in ctx.lower():
        return f"{plage} | {ctx} | {sujet}"
    elif ctx: return f"{plage} | {ctx}"
    elif sujet: return f"{plage} | {sujet}"
    return plage


def extraire_texte_pdf(pdf_path, pages_skip):
    pages = []
    with pdfplumber.open(pdf_path) as pdf:
        print(f"PDF: {len(pdf.pages)} pages | Corps: page {pages_skip+1}")
        for i, page in enumerate(pdf.pages):
            if i < pages_skip: continue
            texte = page.extract_text() or ''
            texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
            if texte.strip(): pages.append((i+1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


def parser_articles(pages_texte, code):
    titre = chapitre = section = ''
    articles = []
    art_ref = None; art_num = None; art_lignes = []; art_ctx = {}

    RE_ART = RE_ART_ENV if code == 'environnement' else RE_ART_ARB

    def ctx_court():
        return chapitre or section or titre or ''

    def sauver():
        nonlocal art_ref, art_num, art_lignes
        if art_ref is not None and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 3:
                articles.append({'ref': art_ref, 'num': art_num, 'texte': texte,
                                 'chapitre': art_ctx.get('chapitre',''),
                                 'section': art_ctx.get('section',''),
                                 'ctx_court': art_ctx.get('ctx_court','')})

    texte_complet = '\n'.join(t for _, t in pages_texte)
    for ligne in texte_complet.split('\n'):
        l = ligne.strip()
        if not l or re.match(r'^\d+$', l): continue

        m = RE_TITRE.match(l)
        if m and not RE_ART.match(l):
            sauver(); art_ref = None; art_lignes = []
            titre = f"Titre {m.group(1).strip()}"; chapitre = section = ''; continue

        m = RE_CHAPITRE.match(l)
        if m and not RE_ART.match(l):
            sauver(); art_ref = None; art_lignes = []
            num = m.group(1).strip(); lib = (m.group(2) or '').strip()
            chapitre = f"Chapitre {num}" + (f" : {lib}" if lib else '')
            section = ''; continue

        m = RE_SECTION.match(l)
        if m and not RE_ART.match(l):
            sauver(); art_ref = None; art_lignes = []
            num = m.group(1).strip(); lib = (m.group(2) or '').strip()
            section = f"Section {num}" + (f" : {lib}" if lib else '')
            continue

        m = RE_ART.match(l)
        if m:
            sauver()
            ref_brut = m.group(1).strip()
            # Normaliser : "1er" -> 1
            num_str = re.sub(r'[^0-9]', '', ref_brut)
            art_num = int(num_str) if num_str else 0
            art_ref = ref_brut
            contenu = (m.group(2) or '').strip()
            art_lignes = [contenu] if contenu else []
            art_ctx = {'chapitre': chapitre, 'section': section, 'ctx_court': ctx_court()}
            continue

        if art_ref is not None and l and len(l) > 2:
            art_lignes.append(l)

    sauver()
    return articles


def meme_ctx(a, b):
    return a['chapitre'] == b['chapitre']

def ref_to_id(ref): return re.sub(r'[^a-zA-Z0-9]', '_', str(ref))

def emettre_chunk(groupe, source, loi, prefix_id):
    premier, dernier = groupe[0], groupe[-1]
    lignes = []
    for art in groupe:
        lignes += [f"Article {art['ref']}", art['texte'], '']
    texte_groupe = '\n'.join(lignes).strip()
    titre = construire_titre(premier['ref'], dernier['ref'],
                             premier['chapitre'], premier['section'], texte_groupe)
    cid = (f"{prefix_id}_{ref_to_id(premier['ref'])}" if premier['ref'] == dernier['ref']
           else f"{prefix_id}_{ref_to_id(premier['ref'])}_{ref_to_id(dernier['ref'])}")
    return {
        'id': cid, 'titre': titre,
        'document': f"{titre}\n\n{texte_groupe}",
        'metadata': {'article_ref': str(premier['ref']), 'article_ref_fin': str(dernier['ref']),
                     'article_num': premier['num'], 'article_num_fin': dernier['num'],
                     'chapitre': premier['chapitre'], 'section': premier['section'],
                     'ctx_court': premier['ctx_court'],
                     'source': source, 'loi': loi, 'category': CATEGORIE,
                     'title': titre, 'url': source}
    }

def regrouper(articles, source, loi, prefix_id):
    chunks = []; i = 0
    while i < len(articles):
        art = articles[i]; mots = len(art['texte'].split())
        if mots > MAX_MOTS:
            tous = art['texte'].split(); step = MAX_MOTS - 40
            for k in range(0, len(tous), step):
                sous = ' '.join(tous[k:k+MAX_MOTS])
                if len(sous.split()) < 20: continue
                part = k // step
                tp = construire_titre(art['ref'], art['ref'], art['chapitre'], art['section'], sous)
                if part > 0: tp += f' (suite {part+1})'
                chunks.append({'id': f"{prefix_id}_{ref_to_id(art['ref'])}_p{part}",
                               'titre': tp, 'document': f"{tp}\n\nArticle {art['ref']}\n{sous}",
                               'metadata': {'article_ref': str(art['ref']), 'article_ref_fin': str(art['ref']),
                                            'article_num': art['num'], 'article_num_fin': art['num'],
                                            'chapitre': art['chapitre'], 'section': art['section'],
                                            'ctx_court': art['ctx_court'],
                                            'source': source, 'loi': loi, 'category': CATEGORIE,
                                            'title': tp, 'url': source}})
            i += 1; continue

        groupe = [art]; mg = mots; j = i + 1
        while j < len(articles):
            s = articles[j]; ms = len(s['texte'].split())
            if not meme_ctx(art, s): break
            if mg + ms > MAX_MOTS:
                if mg < MIN_MOTS: groupe.append(s); mg += ms; j += 1
                break
            groupe.append(s); mg += ms; j += 1
            if mg >= CIBLE: break
        c = emettre_chunk(groupe, source, loi, prefix_id)
        if c: chunks.append(c)
        i = j
    return chunks


def supprimer_anciens(collection, source):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, m in zip(data['ids'], data['metadatas']) if m.get('source') == source]
    if ids:
        for k in range(0, len(ids), 500): collection.delete(ids=ids[k:k+500])
        print(f"[OK] {len(ids)} anciens supprimes")
    else: print("[INFO] Aucun ancien chunk")

def ingerer(chunks, collection, model):
    print(f"Ingestion {len(chunks)} chunks...")
    ok = dup = 0
    for k, c in enumerate(chunks):
        emb = model.encode(c['document']).tolist()
        try: collection.add(ids=[c['id']], embeddings=[emb], documents=[c['document']], metadatas=[c['metadata']]); ok += 1
        except: dup += 1
        if (k+1) % 50 == 0: print(f"  {k+1}/{len(chunks)}...")
    print(f"[OK] Ingeres: {ok} | Doublons: {dup}")
    return ok


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

    pages = extraire_texte_pdf(cfg['pdf'], cfg['pages_skip'])

    if args.diag:
        print("\n=== DIAGNOSTIC : 50 premieres lignes ===")
        txt = '\n'.join(t for _, t in pages[:4])
        for j, l in enumerate(txt.split('\n')[:50]):
            print(f"  [{j:02d}] {repr(l.strip())}")
        print("=== FIN ===\n")

    articles = parser_articles(pages, args.code)
    print(f"Articles detectes: {len(articles)}")

    if not articles:
        print("0 articles. Lance avec --diag pour voir le format brut.")
        exit(1)

    for chap, n in Counter(a['chapitre'] for a in articles).most_common():
        print(f"  {chap[:60]:<60} {n}")

    chunks = regrouper(articles, SOURCE, LOI, PREFIX_ID)
    ml = [len(c['document'].split()) for c in chunks]
    if ml:
        print(f"Chunks: {len(chunks)} | Moy: {sum(ml)//len(ml)}m | Min: {min(ml)}m | Max: {max(ml)}m")

    print("\nExemples de titres:")
    for c in chunks[::max(1,len(chunks)//6)][:6]:
        print(f"  [{len(c['document'].split()):>3}m] {c['titre']}")

    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"\nBase avant: {collection.count()}")
    supprimer_anciens(collection, SOURCE)
    nb = ingerer(chunks, collection, model)
    print(f"\nTERMINE | {SOURCE}: {nb} chunks | Base: {collection.count()} total")
