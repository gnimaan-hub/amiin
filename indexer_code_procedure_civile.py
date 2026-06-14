# -*- coding: utf-8 -*-
"""
indexer_code_procedure_civile.py - Amiin Project
Extrait et indexe le Code de Procedure Civile djiboutien (387 pages).

Specificites :
- Articles au format "Article L.XXX-X :" (lettre + numeros + tiret + deux-points)
- Plan general de 27 pages a ignorer
- Hierarchie mixte : LIVRE/TITRE en majuscules, Chapitre/Section avec casse normale
- Le contenu de l'article commence sur la meme ligne que son numero

Usage: python indexer_code_procedure_civile.py
"""

import re
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

# ── CONFIG ────────────────────────────────────────────────────────────────────

PDF_PATH  = './Code de procedure civile 2018 DJIBOUTI.pdf'
DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
SOURCE    = 'Code de Procedure Civile Djiboutien'
LOI       = 'Code de Procedure Civile de la Republique de Djibouti 2019'

PAGES_PLAN_GENERAL = 27   # Pages 1-27 = titre + plan general

MIN_MOTS  = 280
CIBLE     = 370
MAX_MOTS  = 480

# ── PATTERNS ──────────────────────────────────────────────────────────────────

# Article L.110-1 : ou Article L.110-1: (avec ou sans espace avant les deux-points)
# Le contenu peut commencer sur la meme ligne
RE_ARTICLE = re.compile(
    r'^Article\s+(L\.\d+(?:-\d+)?(?:\s+bis|ter|quater)?)\s*:\s*(.*)?$',
    re.IGNORECASE
)

# Hierarchie : LIVRE PREMIER / DEUXIEME, TITRE I/II, Chapitre 1, Section 1
RE_LIVRE    = re.compile(r'^LIVRE\s+(.+)$')
RE_TITRE    = re.compile(r'^TITRE\s+(.+)$', re.IGNORECASE)
RE_CHAPITRE = re.compile(r'^(?:CHAPITRE|Chapitre)\s+(.+)$')
RE_SECTION  = re.compile(r'^(?:SECTION|Section)\s+(.+)$')
RE_PARA     = re.compile(r'^(?:§\s*\d+|Paragraphe\s+.+)$', re.IGNORECASE)

# Lignes a ignorer systematiquement
RE_ENTETE   = re.compile(r'^Code de Proc.dure Civile\s*$', re.IGNORECASE)

# Formules generiques pour sous-titres
RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |on |est |sont |peut |peuvent |'
    r'doit |doivent |nul |nulle |toute |tout |les dispositions |'
    r'le present |la presente |lorsque |dans le cas |en cas de )',
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


def construire_titre(ref_debut, ref_fin, chapitre, titre_section, texte_groupe):
    """
    Titre : "Article L.110-1 | Contexte | Sujet"
    ou     "Articles L.110-1 a L.110-5 | Contexte | Sujet"
    """
    if ref_debut == ref_fin:
        plage = f"Article {ref_debut}"
    else:
        plage = f"Articles {ref_debut} a {ref_fin}"

    ctx_brut = chapitre or titre_section or ''
    # Nettoyer le prefixe "Chapitre X." ou "TITRE I." 
    ctx = re.sub(
        r'^(CHAPITRE|Chapitre|TITRE|SECTION|Section|LIVRE)\s+\S+\s*[\.\-\–]?\s*',
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
        print(f"PDF: {total} pages | Corps: page {PAGES_PLAN_GENERAL + 1} a {total}")
        for i, page in enumerate(pdf.pages):
            if i < PAGES_PLAN_GENERAL:
                continue
            texte = page.extract_text()
            if texte:
                # Supprimer numeros de page seuls et entetes repetes
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                texte = re.sub(r'\n\d+\n', '\n', texte)
                # Supprimer l'entete "Code de Procédure Civile" repete sur chaque page
                texte = re.sub(r'^Code de Proc.dure Civile\s*$', '', texte, flags=re.MULTILINE | re.IGNORECASE)
                pages.append((i + 1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


# ── PARSER ────────────────────────────────────────────────────────────────────

def parser_articles(pages_texte):
    livre = titre = chapitre = section = ''
    articles = []
    art_ref = None      # ex: "L.110-1"
    art_lignes = []
    art_ctx = {}

    def contexte():
        return ' > '.join(p for p in [livre, titre, chapitre, section] if p)

    def sauver():
        nonlocal art_ref, art_lignes
        if art_ref and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 4:
                articles.append({
                    'ref':      art_ref,
                    'texte':    texte,
                    'livre':    art_ctx.get('livre', ''),
                    'titre':    art_ctx.get('titre', ''),
                    'chapitre': art_ctx.get('chapitre', ''),
                    'section':  art_ctx.get('section', ''),
                    'contexte': art_ctx.get('contexte', ''),
                })

    texte_complet = '\n'.join(t for _, t in pages_texte)
    lignes = texte_complet.split('\n')
    i = 0

    while i < len(lignes):
        ligne = lignes[i].strip()

        # Ignorer entetes vides
        if not ligne or RE_ENTETE.match(ligne):
            i += 1; continue

        # Detecter LIVRE
        m = RE_LIVRE.match(ligne)
        if m and not RE_ARTICLE.match(ligne):
            sauver(); art_ref = None; art_lignes = []
            libelle = m.group(1).strip()
            # Libelle peut continuer sur la ligne suivante
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_TITRE.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 8:
                    libelle += ' ' + prochaine
                    i += 1
            livre = f"Livre {libelle}"
            titre = chapitre = section = ''
            i += 1; continue

        # Detecter TITRE
        m = RE_TITRE.match(ligne)
        if m and not RE_ARTICLE.match(ligne):
            sauver(); art_ref = None; art_lignes = []
            libelle = m.group(1).strip()
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_CHAPITRE.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 10:
                    libelle += ' ' + prochaine
                    i += 1
            titre = f"Titre {libelle}"
            chapitre = section = ''
            i += 1; continue

        # Detecter Chapitre
        m = RE_CHAPITRE.match(ligne)
        if m and not RE_ARTICLE.match(ligne):
            sauver(); art_ref = None; art_lignes = []
            libelle = m.group(1).strip()
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_SECTION.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 10:
                    libelle += ' ' + prochaine
                    i += 1
            chapitre = f"Chapitre {libelle}"
            section = ''
            i += 1; continue

        # Detecter Section
        m = RE_SECTION.match(ligne)
        if m and not RE_ARTICLE.match(ligne):
            sauver(); art_ref = None; art_lignes = []
            libelle = m.group(1).strip()
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_PARA.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine.split()) < 12:
                    libelle += ' ' + prochaine
                    i += 1
            section = f"Section {libelle}"
            i += 1; continue

        # Detecter Article L.XXX-X :
        m = RE_ARTICLE.match(ligne)
        if m:
            sauver()
            art_ref = m.group(1).strip()
            # Le contenu peut commencer sur la meme ligne apres les deux-points
            contenu_inline = (m.group(2) or '').strip()
            art_lignes = [contenu_inline] if contenu_inline else []
            art_ctx = {
                'livre': livre, 'titre': titre,
                'chapitre': chapitre, 'section': section,
                'contexte': contexte(),
            }
            i += 1; continue

        # Corps de l'article courant
        if art_ref and ligne and not re.match(r'^\d+$', ligne) and len(ligne) > 2:
            art_lignes.append(ligne)

        i += 1

    sauver()
    return articles


# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return (a['livre'] == b['livre'] and
            a['titre'] == b['titre'] and
            a['chapitre'] == b['chapitre'])


def ref_sort_key(ref):
    """Cle de tri pour refs comme L.110-1, L.110-12, L.122-3."""
    m = re.match(r'L\.(\d+)-(\d+)', ref)
    if m:
        return (int(m.group(1)), int(m.group(2)))
    return (0, 0)


def emettre_chunk(groupe):
    if not groupe:
        return None
    premier = groupe[0]
    dernier = groupe[-1]
    ref_debut = premier['ref']
    ref_fin   = dernier['ref']

    lignes_corps = []
    for art in groupe:
        lignes_corps.append(f"Article {art['ref']}")
        lignes_corps.append(art['texte'])
        lignes_corps.append('')
    texte_groupe = '\n'.join(lignes_corps).strip()

    titre = construire_titre(
        ref_debut, ref_fin,
        premier['chapitre'],
        premier['titre'],
        texte_groupe
    )

    # ID base sur la ref : L110-1 -> cpc_L110_1
    def ref_to_id(ref):
        return re.sub(r'[^a-zA-Z0-9]', '_', ref)

    chunk_id = (f"cpc_{ref_to_id(ref_debut)}"
                if ref_debut == ref_fin
                else f"cpc_{ref_to_id(ref_debut)}_{ref_to_id(ref_fin)}")

    return {
        'id':       chunk_id,
        'titre':    titre,
        'document': f"{titre}\n\n{texte_groupe}",
        'metadata': {
            'article_ref':   ref_debut,
            'article_ref_fin': ref_fin,
            'livre':         premier['livre'],
            'titre':         premier['titre'],
            'chapitre':      premier['chapitre'],
            'section':       premier['section'],
            'contexte':      premier['contexte'],
            'source':        SOURCE,
            'loi':           LOI,
            'category':      CATEGORIE,
            'title':         titre,
            'url':           'Code de Procedure Civile Djiboutien',
        }
    }


def regrouper_articles(articles):
    chunks = []
    i = 0

    while i < len(articles):
        art = articles[i]
        mots = len(art['texte'].split())

        # Article tres long : decouper avec overlap
        if mots > MAX_MOTS:
            tous_mots = art['texte'].split()
            step = MAX_MOTS - 50
            for k in range(0, len(tous_mots), step):
                sous = ' '.join(tous_mots[k:k + MAX_MOTS])
                if len(sous.split()) < 30:
                    continue
                part = k // step
                titre_part = construire_titre(
                    art['ref'], art['ref'],
                    art['chapitre'], art['titre'], sous
                )
                if part > 0:
                    titre_part += f' (suite {part + 1})'
                def ref_to_id(ref):
                    return re.sub(r'[^a-zA-Z0-9]', '_', ref)
                chunks.append({
                    'id':       f"cpc_{ref_to_id(art['ref'])}_p{part}",
                    'titre':    titre_part,
                    'document': f"{titre_part}\n\nArticle {art['ref']}\n{sous}",
                    'metadata': {
                        'article_ref':     art['ref'],
                        'article_ref_fin': art['ref'],
                        'livre':           art['livre'],
                        'titre':           art['titre'],
                        'chapitre':        art['chapitre'],
                        'section':         art['section'],
                        'contexte':        art['contexte'],
                        'source':          SOURCE,
                        'loi':             LOI,
                        'category':        CATEGORIE,
                        'title':           titre_part,
                        'url':             'Code de Procedure Civile Djiboutien',
                    }
                })
            i += 1
            continue

        # Agglomeration jusqu'a CIBLE mots
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
    print("INDEXATION CODE DE PROCEDURE CIVILE DJIBOUTIEN")
    print("=" * 65)

    print("\n[1/5] Extraction PDF...")
    pages = extraire_texte_pdf(PDF_PATH)

    print("\n[2/5] Parsing articles...")
    articles = parser_articles(pages)
    print(f"Articles detectes: {len(articles)}")
    for livre, n in Counter(a['livre'] for a in articles).most_common():
        print(f"  {livre[:60]:<60} {n} articles")

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
        bar = '#' * (dist[k] // 3)
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
    print(f"TERMINE | Code proc. civile: {nb} chunks | Base: {collection.count()} total")

    print("\nTest - 'competence tribunal premiere instance appel':")
    emb = model.encode("competence tribunal premiere instance appel juridiction").tolist()
    res = collection.query(query_embeddings=[emb], n_results=3,
                           where={"category": "lois"})
    for doc, meta in zip(res['documents'][0], res['metadatas'][0]):
        print(f"  -> {meta['title']}")
        print(f"     {doc[doc.find(chr(10))+1:doc.find(chr(10))+121].replace(chr(10),' ')}")
        print()
