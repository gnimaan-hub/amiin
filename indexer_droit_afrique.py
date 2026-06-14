# -*- coding: utf-8 -*-
"""
indexer_droit_afrique.py - Amiin Project
Script pour les codes PDF Droit-Afrique.com (format 2 colonnes).

Couvre :
  --code investissements  (8p,  Art.X.-)
  --code zones_franches   (7p,  Art.X.-)
  --code peches           (6p,  Art.X.-)
  --code petrolier        (11p, Art.X.-)
  --code minier           (15p, structure narrative)

SPECIFICITE : extraction par colonnes (bbox) pour eviter le melange
gauche/droite de pdfplumber sur les PDFs 2 colonnes Droit-Afrique.com.
Header "www.Droit-Afrique.com Djibouti" filtre automatiquement.

Usage:
  python indexer_droit_afrique.py --code investissements
  python indexer_droit_afrique.py --code zones_franches
  python indexer_droit_afrique.py --code peches
  python indexer_droit_afrique.py --code petrolier
  python indexer_droit_afrique.py --code minier
  python indexer_droit_afrique.py --code investissements --diag
"""

import re, argparse, chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

CONFIGS = {
    'investissements': {
        'pdf':       './code-des-investissements.pdf',
        'source':    'Code des Investissements Djiboutien',
        'loi':       'Loi n88/AN du 13 fevrier 1984 modifiee - Code des investissements',
        'prefix_id': 'ci',
        'pages_skip': 1,
    },
    'zones_franches': {
        'pdf':       './code-des-zones-franches.pdf',
        'source':    'Code des Zones Franches Djiboutien',
        'loi':       'Loi n53/AN/04 du 17 mai 2004 - Code des zones franches',
        'prefix_id': 'czf',
        'pages_skip': 1,
    },
    'peches': {
        'pdf':       './code-des-peches.pdf',
        'source':    'Code des Peches Djiboutien',
        'loi':       'Code des Peches de la Republique de Djibouti',
        'prefix_id': 'cp',
        'pages_skip': 1,
    },
    'petrolier': {
        'pdf':       './code-petrolier.pdf',
        'source':    'Code Petrolier Djiboutien',
        'loi':       'Code Petrolier de la Republique de Djibouti',
        'prefix_id': 'cpet',
        'pages_skip': 1,
    },
    'minier': {
        'pdf':       './code-minier.pdf',
        'source':    'Code Minier Djiboutien',
        'loi':       'Code Minier de la Republique de Djibouti',
        'prefix_id': 'cm',
        'pages_skip': 1,
    },
}

DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
MIN_MOTS, CIBLE, MAX_MOTS = 260, 360, 460

# Format Art.X.- commun a tous ces codes
RE_ART = re.compile(r'^Art\.(\d+(?:\s*(?:bis|ter|quater))?)\.-\s*(.*)?$', re.IGNORECASE)
# Variante sans tiret pour certains articles
RE_ART2 = re.compile(r'^Art\.(\d+(?:\s*(?:bis|ter|quater))?)\.\s*[-–]\s*(.*)?$', re.IGNORECASE)

RE_TITRE    = re.compile(r'^Titre\s+(\d+|[IVXivx]+)\s*[-–:]?\s*(.*)?$', re.IGNORECASE)
RE_CHAPITRE = re.compile(r'^Chapitre\s+(\d+|[IVXivx]+)\s*[-–:]?\s*(.*)?$', re.IGNORECASE)
RE_SECTION  = re.compile(r'^Section\s+(\d+|[IVXivx]+)\s*[-–:]?\s*(.*)?$', re.IGNORECASE)

RE_HEADER   = re.compile(r'^www\.Droit-Afrique\.com|^Droit-Afrique', re.IGNORECASE)

RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |est |sont |peut |toute |tout |nul |nulle )',
    re.IGNORECASE
)

# ── EXTRACTION 2 COLONNES ────────────────────────────────────────────────────

def extraire_page_2colonnes(page):
    """
    Extrait le texte d'une page 2 colonnes en separant gauche et droite.
    Concatene colonne gauche PUIS colonne droite.
    """
    try:
        words = page.extract_words()
        if not words:
            return page.extract_text() or ''

        largeur = page.width
        milieu  = largeur / 2

        gauche = [w for w in words if w['x0'] < milieu]
        droite = [w for w in words if w['x0'] >= milieu]

        def words_to_text(ws):
            if not ws: return ''
            # Trier par y (ligne) puis x (position)
            lignes = {}
            for w in ws:
                y = round(w['top'] / 5) * 5  # quantifier par paliers de 5pt
                lignes.setdefault(y, []).append(w)
            result = []
            for y in sorted(lignes.keys()):
                ligne_mots = sorted(lignes[y], key=lambda w: w['x0'])
                result.append(' '.join(w['text'] for w in ligne_mots))
            return '\n'.join(result)

        texte_g = words_to_text(gauche)
        texte_d = words_to_text(droite)
        return texte_g + '\n' + texte_d

    except Exception:
        return page.extract_text() or ''


def extraire_texte_pdf(pdf_path, pages_skip=1):
    pages = []
    with pdfplumber.open(pdf_path) as pdf:
        total = len(pdf.pages)
        print(f"PDF: {total} pages | Extraction 2 colonnes depuis page {pages_skip+1}")
        for i, page in enumerate(pdf.pages):
            if i < pages_skip: continue
            texte = extraire_page_2colonnes(page)
            if texte:
                # Filtrer le header Droit-Afrique.com
                lignes_filtrees = [l for l in texte.split('\n')
                                   if not RE_HEADER.match(l.strip()) and l.strip()]
                texte = '\n'.join(lignes_filtrees)
                # Supprimer numeros de page seuls
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                if texte.strip():
                    pages.append((i+1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


# ── TITRE SEMANTIQUE ──────────────────────────────────────────────────────────

def extraire_sujet(texte):
    for phrase in re.split(r'[.!?;]\s+', ' '.join(texte.split()))[:5]:
        mots = phrase.strip().split()
        if 5 <= len(mots) <= 22 and not RE_GENERIQUE.match(phrase.strip().lower()):
            s = phrase.strip().rstrip('.,;:')
            return s[:110] if len(s) <= 110 else ' '.join(s.split()[:16]) + '...'
    return ' '.join(texte.split()[:12]).rstrip('.,;:')


def construire_titre(ref_debut, ref_fin, chapitre, titre, texte):
    plage = f"Art. {ref_debut}" if ref_debut == ref_fin else f"Art. {ref_debut} a {ref_fin}"
    ctx_brut = chapitre or titre or ''
    ctx = re.sub(r'^(Titre|Chapitre|Section)\s+\S+\s*[-–:]?\s*', '', ctx_brut).strip()
    if len(ctx) > 60: ctx = ctx[:57] + '...'
    sujet = extraire_sujet(texte)
    if ctx and sujet and sujet.lower() not in ctx.lower():
        return f"{plage} | {ctx} | {sujet}"
    elif ctx: return f"{plage} | {ctx}"
    elif sujet: return f"{plage} | {sujet}"
    return plage


# ── PARSER ────────────────────────────────────────────────────────────────────

def parser_articles(pages_texte):
    titre = chapitre = section = ''
    articles = []
    art_ref = None; art_lignes = []; art_ctx = {}

    def ctx_court():
        return chapitre or section or titre or ''
    def sauver():
        nonlocal art_ref, art_lignes
        if art_ref and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 3:
                articles.append({'ref': art_ref, 'texte': texte,
                                 'titre': art_ctx.get('titre',''),
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
            num = m.group(1).strip(); lib = (m.group(2) or '').strip()
            titre = f"Titre {num}" + (f" - {lib}" if lib else '')
            chapitre = section = ''; continue

        m = RE_CHAPITRE.match(l)
        if m and not RE_ART.match(l):
            sauver(); art_ref = None; art_lignes = []
            num = m.group(1).strip(); lib = (m.group(2) or '').strip()
            chapitre = f"Chapitre {num}" + (f" - {lib}" if lib else '')
            section = ''; continue

        m = RE_SECTION.match(l)
        if m and not RE_ART.match(l):
            sauver(); art_ref = None; art_lignes = []
            num = m.group(1).strip(); lib = (m.group(2) or '').strip()
            section = f"Section {num}" + (f" - {lib}" if lib else '')
            continue

        # Article
        m = RE_ART.match(l) or RE_ART2.match(l)
        if m:
            sauver(); art_ref = m.group(1).strip()
            contenu = (m.group(2) or '').strip()
            art_lignes = [contenu] if contenu else []
            art_ctx = {'titre': titre, 'chapitre': chapitre,
                       'section': section, 'ctx_court': ctx_court()}
            continue

        if art_ref and l and len(l) > 2:
            art_lignes.append(l)

    sauver()
    return articles


# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return a['titre'] == b['titre'] and a['chapitre'] == b['chapitre']

def ref_to_id(ref): return re.sub(r'[^a-zA-Z0-9]', '_', str(ref))

def emettre_chunk(groupe, source, loi, prefix_id):
    premier, dernier = groupe[0], groupe[-1]
    lignes = []
    for art in groupe:
        lignes += [f"Article {art['ref']}", art['texte'], '']
    texte_groupe = '\n'.join(lignes).strip()
    titre = construire_titre(premier['ref'], dernier['ref'],
                             premier['chapitre'], premier['titre'], texte_groupe)
    cid = (f"{prefix_id}_{ref_to_id(premier['ref'])}" if premier['ref'] == dernier['ref']
           else f"{prefix_id}_{ref_to_id(premier['ref'])}_{ref_to_id(dernier['ref'])}")
    return {
        'id': cid, 'titre': titre,
        'document': f"{titre}\n\n{texte_groupe}",
        'metadata': {'article_ref': str(premier['ref']), 'article_ref_fin': str(dernier['ref']),
                     'titre': premier['titre'], 'chapitre': premier['chapitre'],
                     'section': premier['section'], 'ctx_court': premier['ctx_court'],
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
                tp = construire_titre(art['ref'], art['ref'], art['chapitre'], art['titre'], sous)
                if part > 0: tp += f' (suite {part+1})'
                chunks.append({'id': f"{prefix_id}_{ref_to_id(art['ref'])}_p{part}",
                               'titre': tp, 'document': f"{tp}\n\nArt. {art['ref']}\n{sous}",
                               'metadata': {'article_ref': str(art['ref']), 'article_ref_fin': str(art['ref']),
                                            'titre': art['titre'], 'chapitre': art['chapitre'],
                                            'section': art['section'], 'ctx_court': art['ctx_court'],
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


# ── SUPPRESSION + INGESTION ───────────────────────────────────────────────────

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

    pages = extraire_texte_pdf(cfg['pdf'], cfg['pages_skip'])

    if args.diag:
        print("\n=== DIAGNOSTIC : 50 premieres lignes ===")
        txt = '\n'.join(t for _, t in pages[:3])
        for j, l in enumerate(txt.split('\n')[:50]):
            print(f"  [{j:02d}] {repr(l.strip())}")
        print("=== FIN ===\n")

    articles = parser_articles(pages)
    print(f"Articles detectes: {len(articles)}")

    if not articles:
        print("0 articles. Lance avec --diag pour voir le format brut.")
        exit(1)

    for titre, n in Counter(a['titre'] for a in articles).most_common():
        print(f"  {titre[:60]:<60} {n}")

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
