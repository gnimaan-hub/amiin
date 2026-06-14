# -*- coding: utf-8 -*-
"""
indexer_code_route.py - Amiin Project
Code de la Route djiboutien (80 pages).

Format articles : Article L1  /  Article L2.1  /  Article L110-1  (seul sur sa ligne)
Structure : LIVRE PREMIER > PARAGRAPHE PREMIER > Article LX
Pas de deux-points - contenu sur les lignes suivantes.
"""

import re, chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

PDF_PATH  = './Code_de_la_route.pdf'
DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
SOURCE    = 'Code de la Route Djiboutien'
LOI       = 'Loi n120/AN/80 modifiee - Code de la Route de la Republique de Djibouti'
PREFIX_ID = 'cr'
PAGES_SKIP = 1
MIN_MOTS, CIBLE, MAX_MOTS = 250, 350, 450

# Format : Article L1  /  Article L2.1  /  Article L110-1-2-3
RE_ARTICLE = re.compile(r'^Article\s+(L\d+(?:[.\-]\d+)*)\s*$', re.IGNORECASE)
RE_LIVRE   = re.compile(r'^LIVRE\s+(.+)$', re.IGNORECASE)
RE_PARA    = re.compile(r'^PARAGRAPHE\s+(.+)$', re.IGNORECASE)
RE_SECTION = re.compile(r'^(?:SECTION|Section)\s+(.+)$')
RE_CHAPITRE= re.compile(r'^(?:CHAPITRE|Chapitre)\s+(.+)$')
RE_TITRE   = re.compile(r'^(?:TITRE|Titre)\s+(.+)$')
RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |tout |toute |nul |nulle |'
    r'tout conducteur|tout vehicule|aucun|est interdit)',
    re.IGNORECASE
)

def extraire_sujet(texte):
    for phrase in re.split(r'[.!?;]\s+', ' '.join(texte.split()))[:4]:
        mots = phrase.strip().split()
        if 5 <= len(mots) <= 22 and not RE_GENERIQUE.match(phrase.strip().lower()):
            return phrase.strip().rstrip('.,;:')[:110]
    return ' '.join(texte.split()[:12]).rstrip('.,;:')

def construire_titre(ref_debut, ref_fin, contexte_court, texte):
    plage = f"Art. {ref_debut}" if ref_debut == ref_fin else f"Art. {ref_debut} a {ref_fin}"
    ctx = re.sub(r'^(LIVRE|PARAGRAPHE|CHAPITRE|SECTION|Chapitre|Titre)\s+\S+\s*', '', contexte_court).strip()
    if len(ctx) > 60: ctx = ctx[:57] + '...'
    sujet = extraire_sujet(texte)
    if ctx and sujet and sujet.lower() not in ctx.lower():
        return f"{plage} | {ctx} | {sujet}"
    elif ctx: return f"{plage} | {ctx}"
    elif sujet: return f"{plage} | {sujet}"
    return plage

def extraire_texte_pdf(pdf_path):
    pages = []
    with pdfplumber.open(pdf_path) as pdf:
        print(f"PDF: {len(pdf.pages)} pages")
        for i, page in enumerate(pdf.pages):
            if i < PAGES_SKIP: continue
            texte = page.extract_text() or ''
            texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
            pages.append((i+1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages

def parser_articles(pages_texte):
    livre = paragraphe = chapitre = section = titre = ''
    articles = []
    art_ref = None; art_lignes = []; art_ctx = {}

    def ctx_full():
        return ' > '.join(p for p in [livre, titre, chapitre, paragraphe, section] if p)
    def ctx_court():
        return paragraphe or chapitre or titre or livre or ''
    def sauver():
        nonlocal art_ref, art_lignes
        if art_ref and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 3:
                articles.append({'ref': art_ref, 'texte': texte,
                                 'contexte': art_ctx.get('contexte',''),
                                 'ctx_court': art_ctx.get('ctx_court','')})

    texte_complet = '\n'.join(t for _, t in pages_texte)
    for ligne in texte_complet.split('\n'):
        l = ligne.strip()
        if not l or re.match(r'^\d+$', l): continue

        m = RE_LIVRE.match(l)
        if m and not RE_ARTICLE.match(l):
            sauver(); art_ref = None; art_lignes = []
            livre = f"Livre {m.group(1).strip()}"; paragraphe = chapitre = section = titre = ''
            continue
        m = RE_TITRE.match(l)
        if m and not RE_ARTICLE.match(l):
            sauver(); art_ref = None; art_lignes = []
            titre = f"Titre {m.group(1).strip()}"; chapitre = paragraphe = section = ''
            continue
        m = RE_CHAPITRE.match(l)
        if m and not RE_ARTICLE.match(l):
            sauver(); art_ref = None; art_lignes = []
            chapitre = f"Chapitre {m.group(1).strip()}"; section = ''
            continue
        m = RE_PARA.match(l)
        if m and not RE_ARTICLE.match(l):
            sauver(); art_ref = None; art_lignes = []
            paragraphe = f"Paragraphe {m.group(1).strip()}"
            continue
        m = RE_SECTION.match(l)
        if m and not RE_ARTICLE.match(l):
            sauver(); art_ref = None; art_lignes = []
            section = f"Section {m.group(1).strip()}"
            continue

        m = RE_ARTICLE.match(l)
        if m:
            sauver(); art_ref = m.group(1).strip(); art_lignes = []
            art_ctx = {'contexte': ctx_full(), 'ctx_court': ctx_court()}
            continue

        if art_ref and l and len(l) > 2:
            art_lignes.append(l)

    sauver()
    return articles

def meme_ctx(a, b):
    # Regrouper par contexte complet pour la route (articles souvent tres courts)
    ca = re.sub(r'Art\.\s*L\d+.*', '', a['ctx_court'])
    cb = re.sub(r'Art\.\s*L\d+.*', '', b['ctx_court'])
    return ca == cb

def ref_to_id(ref): return re.sub(r'[^a-zA-Z0-9]', '_', ref)

def emettre_chunk(groupe):
    premier, dernier = groupe[0], groupe[-1]
    lignes = []
    for art in groupe:
        lignes += [f"Article {art['ref']}", art['texte'], '']
    texte_groupe = '\n'.join(lignes).strip()
    titre = construire_titre(premier['ref'], dernier['ref'], premier['ctx_court'], texte_groupe)
    cid = (f"{PREFIX_ID}_{ref_to_id(premier['ref'])}" if premier['ref'] == dernier['ref']
           else f"{PREFIX_ID}_{ref_to_id(premier['ref'])}_{ref_to_id(dernier['ref'])}")
    return {
        'id': cid, 'titre': titre,
        'document': f"{titre}\n\n{texte_groupe}",
        'metadata': {'article_ref': premier['ref'], 'article_ref_fin': dernier['ref'],
                     'contexte': premier['contexte'], 'ctx_court': premier['ctx_court'],
                     'source': SOURCE, 'loi': LOI, 'category': CATEGORIE,
                     'title': titre, 'url': SOURCE}
    }

def regrouper(articles):
    chunks = []; i = 0
    while i < len(articles):
        art = articles[i]; mots = len(art['texte'].split())
        if mots > MAX_MOTS:
            tous = art['texte'].split(); step = MAX_MOTS - 40
            for k in range(0, len(tous), step):
                sous = ' '.join(tous[k:k+MAX_MOTS])
                if len(sous.split()) < 20: continue
                part = k // step
                tp = construire_titre(art['ref'], art['ref'], art['ctx_court'], sous)
                if part > 0: tp += f' (suite {part+1})'
                chunks.append({'id': f"{PREFIX_ID}_{ref_to_id(art['ref'])}_p{part}",
                               'titre': tp, 'document': f"{tp}\n\nArticle {art['ref']}\n{sous}",
                               'metadata': {'article_ref': art['ref'], 'article_ref_fin': art['ref'],
                                            'contexte': art['contexte'], 'ctx_court': art['ctx_court'],
                                            'source': SOURCE, 'loi': LOI, 'category': CATEGORIE,
                                            'title': tp, 'url': SOURCE}})
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
        c = emettre_chunk(groupe)
        if c: chunks.append(c)
        i = j
    return chunks

def supprimer_anciens(collection):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, m in zip(data['ids'], data['metadatas']) if m.get('source') == SOURCE]
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
        if (k+1) % 100 == 0: print(f"  {k+1}/{len(chunks)}...")
    print(f"[OK] Ingeres: {ok} | Doublons: {dup}")
    return ok

if __name__ == '__main__':
    print("=" * 65)
    print(f"INDEXATION : {SOURCE}")
    print("=" * 65)
    pages = extraire_texte_pdf(PDF_PATH)
    articles = parser_articles(pages)
    print(f"Articles detectes: {len(articles)}")
    if not articles: print("0 articles - verifier le PDF"); exit(1)
    chunks = regrouper(articles)
    ml = [len(c['document'].split()) for c in chunks]
    print(f"Chunks: {len(chunks)} | Moy: {sum(ml)//len(ml)}m | Min: {min(ml)}m | Max: {max(ml)}m")
    for c in chunks[::max(1,len(chunks)//6)][:6]:
        print(f"  [{len(c['document'].split()):>3}m] {c['titre']}")
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"Base avant: {collection.count()}")
    supprimer_anciens(collection)
    nb = ingerer(chunks, collection, model)
    print(f"\nTERMINE | {SOURCE}: {nb} chunks | Base: {collection.count()} total")
