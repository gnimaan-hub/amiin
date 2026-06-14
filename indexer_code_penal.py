# -*- coding: utf-8 -*-
"""
indexer_code_penal.py - Amiin Project
Extrait et indexe tous les articles du Code Penal djiboutien (181 pages).

Differences vs Code Civil :
- Pas de plan general : le code commence page 1
- Structure en MAJUSCULES : LIVRE I, TITRE PREMIER, CHAPITRE I, SECTION 1
- "Articles X" (pluriel) possible pour certains articles
- Articles speciaux "Art. R. X" pour les contraventions reglementaires

Usage: python indexer_code_penal.py
"""

import re
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

# ── CONFIG ────────────────────────────────────────────────────────────────────

PDF_PATH  = './Code_Pénal_de_Djibouti.pdf'
DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
SOURCE    = 'Code Penal Djiboutien'
LOI       = 'Code Penal de la Republique de Djibouti'

PAGES_PLAN_GENERAL = 0   # Le code commence directement page 1

MIN_MOTS  = 280
CIBLE     = 370
MAX_MOTS  = 480

# ── PATTERNS ──────────────────────────────────────────────────────────────────

# Code penal : structure en MAJUSCULES
RE_LIVRE    = re.compile(r'^LIVRE\s+([IVX\d]+)\s*$')
RE_TITRE    = re.compile(r'^TITRE\s+(.+)$')
RE_CHAPITRE = re.compile(r'^CHAPITRE\s+(.+)$')
RE_SECTION  = re.compile(r'^SECTION\s+(.+)$')
RE_PARAGRAPHE = re.compile(r'^Paragraphe\s+(.+)$', re.IGNORECASE)

# Articles reguliers : "Article 1" ou "Articles 5" (pluriel)
RE_ARTICLE  = re.compile(r'^Articles?\s+(\d+)\s*$')

# Articles reglementaires de contravention : "Art. R. 1" ou "Art. R. 1 - 1°"
RE_ART_R    = re.compile(r'^Art\.\s*R\.\s*(\d+)', re.IGNORECASE)

# Libelles de LIVRE connus (ligne suivante apres LIVRE I)
LIVRE_LIBELLES = {
    'I':   'DISPOSITIONS GENERALES',
    'II':  'CRIMES ET DELITS',
    'III': 'CONTRAVENTIONS',
}

# Formules generiques a eviter pour les sous-titres semantiques
RE_GENERIQUE = re.compile(
    r'^(le |la |les |un |une |des |il |elle |on |est |sont |peut |peuvent |'
    r'doit |doivent |nul |nulle |aucun |toute |tout |les dispositions |'
    r'le present |la presente |est puni|est reprime|constitue )',
    re.IGNORECASE
)

# ── TITRE SEMANTIQUE ──────────────────────────────────────────────────────────

def extraire_sujet(texte):
    """Extrait la premiere phrase substantielle pour le sous-titre."""
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


def construire_titre(num_debut, num_fin, chapitre, titre_section, texte_groupe, est_art_r=False):
    """
    Titre semantique en 3 niveaux :
    "Article X | Contexte | Sujet extrait du contenu"
    """
    # Niveau 1 : plage
    if est_art_r:
        plage = f"Art. R. {num_debut}" if num_debut == num_fin else f"Art. R. {num_debut} a {num_fin}"
    else:
        plage = f"Article {num_debut}" if num_debut == num_fin else f"Articles {num_debut} a {num_fin}"

    # Niveau 2 : contexte court
    ctx_brut = chapitre or titre_section or ''
    ctx = re.sub(r'^(CHAPITRE|TITRE|SECTION|LIVRE|Paragraphe)\s+\S+\s*', '', ctx_brut).strip()
    if len(ctx) > 60:
        ctx = ctx[:57] + '...'

    # Niveau 3 : sujet semantique
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
                # Supprimer les numeros de page seuls
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                texte = re.sub(r'\n\d+\n', '\n', texte)
                pages.append((i + 1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


# ── PARSER ────────────────────────────────────────────────────────────────────

def parser_articles(pages_texte):
    livre = titre = chapitre = section = paragraphe = ''
    articles = []
    art_num = None
    art_r_num = None   # Pour les Art. R.
    art_lignes = []
    art_ctx = {}
    est_art_r = False

    def contexte():
        parts = [p for p in [livre, titre, chapitre, section, paragraphe] if p]
        return ' > '.join(parts)

    def sauver():
        nonlocal art_num, art_r_num, art_lignes, est_art_r
        num = art_r_num if est_art_r else art_num
        if num is not None and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 4:
                articles.append({
                    'num':      num,
                    'texte':    texte,
                    'livre':    art_ctx.get('livre', ''),
                    'titre':    art_ctx.get('titre', ''),
                    'chapitre': art_ctx.get('chapitre', ''),
                    'section':  art_ctx.get('section', ''),
                    'contexte': art_ctx.get('contexte', ''),
                    'est_art_r': est_art_r,
                })

    texte_complet = '\n'.join(t for _, t in pages_texte)
    lignes = texte_complet.split('\n')
    i = 0
    prochaine_ligne_libelle_livre = False

    while i < len(lignes):
        ligne = lignes[i].strip()

        # Detecter LIVRE (la ligne suivante contient le libelle)
        m = RE_LIVRE.match(ligne)
        if m:
            sauver(); art_num = None; art_r_num = None; art_lignes = []; est_art_r = False
            # Chercher le libelle sur la ligne suivante
            libelle = ''
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_TITRE.match(prochaine) and not RE_ARTICLE.match(prochaine):
                    libelle = prochaine
                    i += 1  # Consommer la ligne suivante
            num_livre = m.group(1)
            libelle = libelle or LIVRE_LIBELLES.get(num_livre, '')
            livre = f"Livre {num_livre} : {libelle}" if libelle else f"Livre {num_livre}"
            titre = chapitre = section = paragraphe = ''
            i += 1; continue

        # Detecter TITRE (en MAJUSCULES, ligne suivante = libelle)
        m = RE_TITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_r_num = None; art_lignes = []; est_art_r = False
            # Le libelle peut etre sur la meme ligne ou la suivante
            libelle_titre = m.group(1).strip()
            # Si le libelle est court/vide, chercher la ligne suivante
            if len(libelle_titre.split()) <= 2 and i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_CHAPITRE.match(prochaine) and not RE_ARTICLE.match(prochaine):
                    libelle_titre = libelle_titre + ' ' + prochaine if libelle_titre else prochaine
                    i += 1
            titre = f"Titre {libelle_titre}"
            chapitre = section = paragraphe = ''
            i += 1; continue

        # Detecter CHAPITRE
        m = RE_CHAPITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_r_num = None; art_lignes = []; est_art_r = False
            libelle_chap = m.group(1).strip()
            # Libelle sur ligne suivante ?
            if len(libelle_chap.split()) <= 2 and i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_SECTION.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine) > 3:
                    libelle_chap = libelle_chap + ' ' + prochaine
                    i += 1
            chapitre = f"Chapitre {libelle_chap}"
            section = paragraphe = ''
            i += 1; continue

        # Detecter SECTION
        m = RE_SECTION.match(ligne)
        if m:
            sauver(); art_num = None; art_r_num = None; art_lignes = []; est_art_r = False
            libelle_sec = m.group(1).strip()
            if len(libelle_sec.split()) <= 2 and i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_PARAGRAPHE.match(prochaine) and not RE_ARTICLE.match(prochaine) and len(prochaine) > 3:
                    libelle_sec = libelle_sec + ' ' + prochaine
                    i += 1
            section = f"Section {libelle_sec}"
            paragraphe = ''
            i += 1; continue

        # Detecter Paragraphe
        m = RE_PARAGRAPHE.match(ligne)
        if m:
            sauver(); art_num = None; art_r_num = None; art_lignes = []; est_art_r = False
            libelle_para = m.group(1).strip()
            if i + 1 < len(lignes):
                prochaine = lignes[i+1].strip()
                if prochaine and not RE_ARTICLE.match(prochaine) and len(prochaine) > 3 and not prochaine[0].isupper():
                    libelle_para = libelle_para + ' ' + prochaine
                    i += 1
            paragraphe = f"Paragraphe {libelle_para}"
            i += 1; continue

        # Detecter Article reglementaire Art. R. X
        m = RE_ART_R.match(ligne)
        if m:
            sauver()
            art_num = None
            art_r_num = int(m.group(1))
            art_lignes = [ligne[ligne.index(':')+1:].strip()] if ':' in ligne else []
            est_art_r = True
            art_ctx = {
                'livre': livre, 'titre': titre,
                'chapitre': chapitre, 'section': section,
                'contexte': contexte(),
            }
            i += 1; continue

        # Detecter Article regulier
        m = RE_ARTICLE.match(ligne)
        if m:
            sauver()
            art_num = int(m.group(1))
            art_r_num = None
            art_lignes = []
            est_art_r = False
            art_ctx = {
                'livre': livre, 'titre': titre,
                'chapitre': chapitre, 'section': section,
                'contexte': contexte(),
            }
            i += 1; continue

        # Corps de l'article courant
        num_courant = art_r_num if est_art_r else art_num
        if num_courant is not None and ligne and not re.match(r'^\d+$', ligne) and len(ligne) > 2:
            art_lignes.append(ligne)

        i += 1

    sauver()
    return articles


# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return (a['livre'] == b['livre'] and
            a['titre'] == b['titre'] and
            a['chapitre'] == b['chapitre'] and
            a['est_art_r'] == b['est_art_r'])


def emettre_chunk(groupe):
    if not groupe:
        return None
    premier = groupe[0]
    dernier = groupe[-1]
    num_debut = premier['num']
    num_fin   = dernier['num']
    est_art_r = premier['est_art_r']

    lignes_corps = []
    for art in groupe:
        prefix = f"Art. R. {art['num']}" if est_art_r else f"Article {art['num']}"
        lignes_corps.append(prefix)
        lignes_corps.append(art['texte'])
        lignes_corps.append('')
    texte_groupe = '\n'.join(lignes_corps).strip()

    titre = construire_titre(
        num_debut, num_fin,
        premier['chapitre'],
        premier['titre'],
        texte_groupe,
        est_art_r=est_art_r
    )

    prefix_id = 'art_r' if est_art_r else 'art'
    chunk_id = f"{prefix_id}_{num_debut}" if num_debut == num_fin else f"{prefix_id}_{num_debut}_{num_fin}"
    document = f"{titre}\n\n{texte_groupe}"

    return {
        'id':       chunk_id,
        'titre':    titre,
        'document': document,
        'metadata': {
            'article_num': num_debut,
            'article_fin': num_fin,
            'livre':       premier['livre'],
            'titre':       premier['titre'],
            'chapitre':    premier['chapitre'],
            'section':     premier['section'],
            'contexte':    premier['contexte'],
            'source':      SOURCE,
            'loi':         LOI,
            'category':    CATEGORIE,
            'title':       titre,
            'url':         'Code Penal Djiboutien',
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
                prefix = "Art. R." if art['est_art_r'] else "Article"
                titre_part = construire_titre(
                    art['num'], art['num'],
                    art['chapitre'], art['titre'], sous,
                    est_art_r=art['est_art_r']
                )
                if part > 0:
                    titre_part += f' (suite {part + 1})'
                prefix_id = 'art_r' if art['est_art_r'] else 'art'
                chunks.append({
                    'id':       f"{prefix_id}_{art['num']}_p{part}",
                    'titre':    titre_part,
                    'document': f"{titre_part}\n\n{prefix} {art['num']}\n{sous}",
                    'metadata': {
                        'article_num': art['num'],
                        'article_fin': art['num'],
                        'livre':       art['livre'],
                        'titre':       art['titre'],
                        'chapitre':    art['chapitre'],
                        'section':     art['section'],
                        'contexte':    art['contexte'],
                        'source':      SOURCE,
                        'loi':         LOI,
                        'category':    CATEGORIE,
                        'title':       titre_part,
                        'url':         'Code Penal Djiboutien',
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

def supprimer_chunks_code_penal(collection):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == SOURCE]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"[OK] {len(ids)} anciens chunks '{SOURCE}' supprimes")
    else:
        print(f"[INFO] Aucun ancien chunk '{SOURCE}'")


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
    print("INDEXATION CODE PENAL DJIBOUTIEN")
    print("=" * 65)

    print("\n[1/5] Extraction PDF...")
    pages = extraire_texte_pdf(PDF_PATH)

    print("\n[2/5] Parsing articles...")
    articles = parser_articles(pages)
    art_reguliers = [a for a in articles if not a['est_art_r']]
    art_reglementaires = [a for a in articles if a['est_art_r']]
    print(f"Articles reguliers:       {len(art_reguliers)}")
    print(f"Articles reglementaires:  {len(art_reglementaires)}")
    print(f"Total:                    {len(articles)}")
    for livre, n in Counter(a['livre'] for a in articles).most_common():
        print(f"  {livre[:55]:<55} {n} articles")

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
    supprimer_chunks_code_penal(collection)

    print("\n[5/5] Ingestion...")
    nb = ingerer(chunks, collection, model)

    print(f"\n{'='*65}")
    print(f"TERMINE | Code penal: {nb} chunks | Base: {collection.count()} total")

    print("\nTest - 'vol avec violence et circonstances aggravantes':")
    emb = model.encode("vol avec violence circonstances aggravantes peine").tolist()
    res = collection.query(query_embeddings=[emb], n_results=3,
                           where={"category": "lois"})
    for doc, meta in zip(res['documents'][0], res['metadatas'][0]):
        print(f"  -> {meta['title']}")
        print(f"     {doc[doc.find(chr(10))+1:doc.find(chr(10))+121].replace(chr(10),' ')}")
        print()