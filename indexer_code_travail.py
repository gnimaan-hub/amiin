# -*- coding: utf-8 -*-
"""
indexer_code_travail.py - Amiin Project
Extrait et indexe le Code du Travail djiboutien (66 pages, 299 articles).

Specificites :
- Pas de plan general : le code commence page 1
- TITRE I/II... seul sur sa ligne, libelle sur la ligne suivante
- CHAPITRE 1er/II... seul sur sa ligne, libelle sur la ligne suivante
- Section X : LIBELLE sur la meme ligne
- Article Xer : ou Article X : avec contenu qui commence sur la meme ligne
- Loi n133/AN/05/5eme L du 28 janvier 2006

Usage: python indexer_code_travail.py
"""

import re
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

# ── CONFIG ────────────────────────────────────────────────────────────────────

PDF_PATH  = './Code_du_travail.pdf'
DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
SOURCE    = 'Code du Travail Djiboutien'
LOI       = 'Loi n133/AN/05/5eme L du 28 janvier 2006'

PAGES_PLAN_GENERAL = 0

MIN_MOTS  = 280
CIBLE     = 370
MAX_MOTS  = 480

# ── PATTERNS ──────────────────────────────────────────────────────────────────

# TITRE I, TITRE II, TITRE III... (seul sur sa ligne)
RE_TITRE    = re.compile(r'^TITRE\s+([IVX]+|[0-9]+)\s*$')

# CHAPITRE 1er, CHAPITRE II, CHAPITRE III... (seul sur sa ligne)
RE_CHAPITRE = re.compile(r'^CHAPITRE\s+(\S+)\s*$')

# Section 1 : LIBELLE ou Section 1: LIBELLE (libelle sur la meme ligne)
RE_SECTION  = re.compile(r'^Section\s+(\d+)\s*[:\-]\s*(.*)?$', re.IGNORECASE)

# Paragraphe (ex: PARAGRAPHE 1, PARAGRAPHE 2)
RE_PARA     = re.compile(r'^PARAGRAPHE\s+(\S+)\s*$')

# Article 1er : ou Article 22 : (contenu inline)
RE_ARTICLE  = re.compile(r'^Article\s+(\d+(?:er|eme|ieme)?)\s*:\s*(.*)?$', re.IGNORECASE)

# Lignes a ignorer
RE_IGNORE   = re.compile(r'^(Fait a Djibouti|Le President|chef du|ISMAIL|L\'ASSEMBLEE|LE PRESIDENT|VU La|VU Le)', re.IGNORECASE)

# Formules generiques pour sous-titres semantiques
RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |on |est |sont |peut |peuvent |'
    r'doit |doivent |nul |nulle |toute |tout |les dispositions |'
    r'le present |la presente |en cas de |si |lorsque |sous reserve )',
    re.IGNORECASE
)

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
        sous_titre = phrase.rstrip('.,;:')
        if len(sous_titre) > 110:
            sous_titre = ' '.join(sous_titre.split()[:16]) + '...'
        return sous_titre
    mots = texte_plat.split()
    return ' '.join(mots[:12]).rstrip('.,;:')


def construire_titre(num_debut, num_fin, section, chapitre, titre, texte_groupe):
    """
    Titre : "Article X | Contexte | Sujet"
    Priorite contexte : Section > Chapitre > Titre
    """
    plage = f"Article {num_debut}" if num_debut == num_fin else f"Articles {num_debut} a {num_fin}"

    # Choisir le contexte le plus precis
    ctx_brut = section or chapitre or titre or ''
    # Nettoyer le prefixe hierarchique
    ctx = re.sub(
        r'^(TITRE|CHAPITRE|Section|PARAGRAPHE)\s+\S+\s*[:\-]?\s*',
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
    else:
        return plage


# ── EXTRACTION PDF ─────────────────────────────────────────────────────────────

def extraire_texte_pdf(pdf_path):
    pages = []
    with pdfplumber.open(pdf_path) as pdf:
        total = len(pdf.pages)
        print(f"PDF: {total} pages | Extraction depuis page 1")
        for i, page in enumerate(pdf.pages):
            texte = page.extract_text()
            if texte:
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                texte = re.sub(r'\n\d+\n', '\n', texte)
                pages.append((i + 1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


# ── PARSER ────────────────────────────────────────────────────────────────────

def parser_articles(pages_texte):
    titre = titre_lib = ''
    chapitre = chapitre_lib = ''
    section = ''
    paragraphe = ''
    articles = []
    art_num = None
    art_lignes = []
    art_ctx = {}

    def contexte():
        parts = []
        if titre:
            lib = titre_lib or titre
            parts.append(f"{titre} : {lib}" if titre_lib else titre)
        if chapitre:
            lib = chapitre_lib or chapitre
            parts.append(f"{chapitre} : {lib}" if chapitre_lib else chapitre)
        if section:
            parts.append(section)
        if paragraphe:
            parts.append(paragraphe)
        return ' > '.join(parts)

    def contexte_court():
        # Pour le titre du chunk: priorite section > chapitre > titre
        if section:
            return re.sub(r'^Section\s+\d+\s*[:\-]\s*', '', section).strip()
        if chapitre_lib:
            return chapitre_lib
        if titre_lib:
            return titre_lib
        return chapitre or titre

    def sauver():
        nonlocal art_num, art_lignes
        if art_num is not None and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 3:
                articles.append({
                    'num':      art_num,
                    'texte':    texte,
                    'titre':    titre,
                    'chapitre': chapitre,
                    'section':  section,
                    'contexte': contexte(),
                    'ctx_court': contexte_court(),
                })

    texte_complet = '\n'.join(t for _, t in pages_texte)
    lignes = texte_complet.split('\n')
    i = 0

    while i < len(lignes):
        ligne = lignes[i].strip()

        if not ligne or RE_IGNORE.match(ligne):
            i += 1; continue

        # TITRE X (seul sur sa ligne)
        m = RE_TITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            titre = f"TITRE {m.group(1)}"
            titre_lib = chapitre = chapitre_lib = section = paragraphe = ''
            # Libelle sur la ligne suivante
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if (prochaine
                        and not RE_CHAPITRE.match(prochaine)
                        and not RE_ARTICLE.match(prochaine)
                        and not RE_TITRE.match(prochaine)
                        and len(prochaine.split()) < 12):
                    titre_lib = prochaine
                    i += 1
            i += 1; continue

        # CHAPITRE X (seul sur sa ligne)
        m = RE_CHAPITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            chapitre = f"CHAPITRE {m.group(1)}"
            chapitre_lib = section = paragraphe = ''
            # Libelle sur la ligne suivante
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if (prochaine
                        and not RE_SECTION.match(prochaine)
                        and not RE_ARTICLE.match(prochaine)
                        and not RE_TITRE.match(prochaine)
                        and not RE_CHAPITRE.match(prochaine)
                        and len(prochaine.split()) < 12):
                    chapitre_lib = prochaine
                    i += 1
            i += 1; continue

        # Section X : LIBELLE
        m = RE_SECTION.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            libelle_sec = (m.group(2) or '').strip()
            # Si libelle vide ou trop court, chercher ligne suivante
            if len(libelle_sec.split()) < 2 and i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 12:
                    libelle_sec = prochaine
                    i += 1
            section = f"Section {m.group(1)} : {libelle_sec}" if libelle_sec else f"Section {m.group(1)}"
            paragraphe = ''
            i += 1; continue

        # PARAGRAPHE X
        m = RE_PARA.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            para_lib = ''
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 12:
                    para_lib = prochaine
                    i += 1
            paragraphe = f"Paragraphe {m.group(1)}" + (f" : {para_lib}" if para_lib else '')
            i += 1; continue

        # Article X :
        m = RE_ARTICLE.match(ligne)
        if m:
            sauver()
            ref = m.group(1).strip()
            num_str = re.sub(r'[^0-9]', '', ref)
            art_num = int(num_str) if num_str else None
            if art_num is None:
                i += 1; continue
            contenu_inline = (m.group(2) or '').strip()
            art_lignes = [contenu_inline] if contenu_inline else []
            i += 1; continue

        # Corps de l'article
        if art_num is not None and ligne and not re.match(r'^\d+$', ligne) and len(ligne) > 2:
            art_lignes.append(ligne)

        i += 1

    sauver()
    return articles


# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return (a['titre'] == b['titre'] and
            a['chapitre'] == b['chapitre'] and
            a['section'] == b['section'])


def emettre_chunk(groupe):
    if not groupe:
        return None
    premier = groupe[0]
    dernier = groupe[-1]
    num_debut = premier['num']
    num_fin   = dernier['num']

    lignes_corps = []
    for art in groupe:
        lignes_corps.append(f"Article {art['num']}")
        lignes_corps.append(art['texte'])
        lignes_corps.append('')
    texte_groupe = '\n'.join(lignes_corps).strip()

    titre_chunk = construire_titre(
        num_debut, num_fin,
        premier['section'],
        premier['chapitre'],
        premier['titre'],
        texte_groupe
    )

    chunk_id = f"ct_{num_debut}" if num_debut == num_fin else f"ct_{num_debut}_{num_fin}"

    return {
        'id':       chunk_id,
        'titre':    titre_chunk,
        'document': f"{titre_chunk}\n\n{texte_groupe}",
        'metadata': {
            'article_num': num_debut,
            'article_fin': num_fin,
            'titre':       premier['titre'],
            'chapitre':    premier['chapitre'],
            'section':     premier['section'],
            'contexte':    premier['contexte'],
            'source':      SOURCE,
            'loi':         LOI,
            'category':    CATEGORIE,
            'title':       titre_chunk,
            'url':         'Code du Travail Djiboutien',
        }
    }


def regrouper_articles(articles):
    chunks = []
    i = 0

    while i < len(articles):
        art = articles[i]
        mots = len(art['texte'].split())

        # Article tres long : decouper
        if mots > MAX_MOTS:
            tous_mots = art['texte'].split()
            step = MAX_MOTS - 50
            for k in range(0, len(tous_mots), step):
                sous = ' '.join(tous_mots[k:k + MAX_MOTS])
                if len(sous.split()) < 30:
                    continue
                part = k // step
                titre_part = construire_titre(
                    art['num'], art['num'],
                    art['section'], art['chapitre'], art['titre'], sous
                )
                if part > 0:
                    titre_part += f' (suite {part + 1})'
                chunks.append({
                    'id':       f"ct_{art['num']}_p{part}",
                    'titre':    titre_part,
                    'document': f"{titre_part}\n\nArticle {art['num']}\n{sous}",
                    'metadata': {
                        'article_num': art['num'],
                        'article_fin': art['num'],
                        'titre':       art['titre'],
                        'chapitre':    art['chapitre'],
                        'section':     art['section'],
                        'contexte':    art['contexte'],
                        'source':      SOURCE,
                        'loi':         LOI,
                        'category':    CATEGORIE,
                        'title':       titre_part,
                        'url':         'Code du Travail Djiboutien',
                    }
                })
            i += 1
            continue

        # Agglomeration
        groupe = [art]
        mots_groupe = mots
        j = i + 1

        while j < len(articles):
            suivant = articles[j]
            mots_suivant = len(suivant['texte'].split())

            if not meme_ctx(art, suivant):
                break

            if mots_groupe + mots_suivant > MAX_MOTS:
                if mots_groupe < MIN_MOTS:
                    groupe.append(suivant)
                    mots_groupe += mots_suivant
                    j += 1
                break

            groupe.append(suivant)
            mots_groupe += mots_suivant
            j += 1

            if mots_groupe >= CIBLE:
                break

        c = emettre_chunk(groupe)
        if c:
            chunks.append(c)
        i = j

    return chunks


# ── SUPPRESSION + INGESTION ───────────────────────────────────────────────────

def supprimer_anciens(collection):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == SOURCE]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"[OK] {len(ids)} anciens chunks supprimes")
    else:
        print("[INFO] Aucun ancien chunk a supprimer")


def ingerer(chunks, collection, model):
    print(f"Ingestion de {len(chunks)} chunks...")
    ingeres = doublons = 0
    for k, chunk in enumerate(chunks):
        emb = model.encode(chunk['document']).tolist()
        try:
            collection.add(
                ids=[chunk['id']],
                embeddings=[emb],
                documents=[chunk['document']],
                metadatas=[chunk['metadata']]
            )
            ingeres += 1
        except Exception:
            doublons += 1
        if (k + 1) % 100 == 0:
            print(f"  {k+1}/{len(chunks)}...")
    print(f"[OK] Ingeres: {ingeres} | Doublons: {doublons}")
    return ingeres


# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("=" * 65)
    print("INDEXATION CODE DU TRAVAIL DJIBOUTIEN")
    print("=" * 65)

    print("\n[1/5] Extraction PDF...")
    pages = extraire_texte_pdf(PDF_PATH)

    print("\n[2/5] Parsing articles...")
    articles = parser_articles(pages)
    print(f"Articles detectes: {len(articles)}")
    for titre, n in Counter(a['titre'] for a in articles).most_common():
        print(f"  {titre:<20} {n} articles")

    print("\n[3/5] Regroupement (cible 300-480 mots)...")
    chunks = regrouper_articles(articles)
    mots_list = [len(c['document'].split()) for c in chunks]
    print(f"Chunks: {len(chunks)} | Moy: {sum(mots_list)//len(mots_list)}m | Min: {min(mots_list)}m | Max: {max(mots_list)}m")

    dist = Counter()
    for w in mots_list:
        if w < 100: dist['<100'] += 1
        elif w < 200: dist['100-200'] += 1
        elif w < 300: dist['200-300'] += 1
        elif w < 400: dist['300-400'] += 1
        elif w < 500: dist['400-500'] += 1
        else: dist['500+'] += 1
    for k in ['<100','100-200','200-300','300-400','400-500','500+']:
        bar = '#' * (dist[k] // 2)
        print(f"  {k:<10} {dist[k]:>4}  {bar}")

    print("\nExemples de titres:")
    step = max(1, len(chunks) // 10)
    for c in chunks[::step][:10]:
        print(f"  [{len(c['document'].split()):>3}m] {c['titre']}")

    print("\n[4/5] Connexion ChromaDB...")
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"Base avant: {collection.count()} chunks")
    supprimer_anciens(collection)

    print("\n[5/5] Ingestion...")
    nb = ingerer(chunks, collection, model)

    print(f"\n{'='*65}")
    print(f"TERMINE | Code travail: {nb} chunks | Base: {collection.count()} total")

    print("\nTest - 'licenciement abusif indemnites droits travailleur':")
    emb = model.encode("licenciement abusif droits indemnites travailleur cause reelle").tolist()
    res = collection.query(query_embeddings=[emb], n_results=3, where={"category": "lois"})
    for doc, meta in zip(res['documents'][0], res['metadatas'][0]):
        print(f"  -> {meta['title']}")
        print(f"     {doc[doc.find(chr(10))+1:doc.find(chr(10))+121].replace(chr(10),' ')}")
        print()

    print("Test - 'greve droits travailleurs procedure legale':")
    emb2 = model.encode("greve procedure legale conditions declenchement droits travailleurs").tolist()
    res2 = collection.query(query_embeddings=[emb2], n_results=3, where={"category": "lois"})
    for doc, meta in zip(res2['documents'][0], res2['metadatas'][0]):
        print(f"  -> {meta['title']}")
        print(f"     {doc[doc.find(chr(10))+1:doc.find(chr(10))+121].replace(chr(10),' ')}")
        print()
