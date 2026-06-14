# -*- coding: utf-8 -*-
"""
indexer_code_civil.py - Amiin Project v2
Extrait et indexe tous les articles du Code Civil djiboutien (392 pages).

Ameliorations v2 :
- Chunks cibles 300-480 mots (vs 100-200 avant)
- Regroupement agressif des articles courts du meme contexte
- Titres semantiques : Art X-Y | Contexte | Sujet extrait du contenu
- Suppression automatique des anciens chunks avant reindexation

Usage: python indexer_code_civil.py
"""

import re
import chromadb
from sentence_transformers import SentenceTransformer
import pdfplumber
from collections import Counter

# ── CONFIG ────────────────────────────────────────────────────────────────────

PDF_PATH  = './Djibouti-Code-civil-2018.pdf'
DB_PATH   = './amiin_db'
CATEGORIE = 'lois'
SOURCE    = 'Code Civil Djiboutien 2018'
LOI       = 'Loi n003/AN/18/8eme L du 12 avril 2018'

PAGES_PLAN_GENERAL = 26

MIN_MOTS  = 280
CIBLE     = 370
MAX_MOTS  = 480

# ── PATTERNS ──────────────────────────────────────────────────────────────────

RE_LIVRE    = re.compile(r'^LIVRE\s+([IVX]+)\s*[:\.\-]\s*(.+)$', re.IGNORECASE)
RE_TITRE    = re.compile(r'^Titre\s+([IVXivx]+)\s*[:\.\-]\s*(.+)$')
RE_CHAPITRE = re.compile(r'^Chapitre\s+(I{1,4}|IV|V?I{0,3}|[IVX]+|[Ier]+)\s*[:\.\-]\s*(.+)$')
RE_SECTION  = re.compile(r'^Section\s+([IVXivx]+)\s*[:\.\-]\s*(.+)$')
RE_ARTICLE  = re.compile(r'^Article\s+(\d+)\s*$')
RE_PRELIM   = re.compile(r'^Titre\s+pr.liminaire\s*[:\.\-]?\s*(.+)?$', re.IGNORECASE)

FORMULES_GENERIQUES = [
    r'^(le |la |les |un |une |des |il |elle |on |tout |toute |tous |toutes )',
    r'^(est |sont |peut |peuvent |doit |doivent |ne peut |ne peuvent )',
    r'^(nul |nulle |aucun |aucune |chacun |chaque )',
    r'^(en cas de |a defaut de |sous reserve de |conformement a )',
    r'^(les dispositions |le present |la presente |le code |la loi )',
]
RE_GENERIQUE = re.compile('|'.join(FORMULES_GENERIQUES), re.IGNORECASE)

# ── TITRE SEMANTIQUE ──────────────────────────────────────────────────────────

def extraire_sujet(texte):
    """
    Extrait la premiere phrase substantielle du texte pour servir de sous-titre.
    Evite les formules generiques d'ouverture.
    """
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
    # Fallback
    mots = texte_plat.split()
    return ' '.join(mots[:12]).rstrip('.,;:')


def construire_titre(num_debut, num_fin, chapitre, titre_section, texte_groupe):
    """
    Titre en 3 niveaux :
      "Articles X a Y | Contexte court | Sujet extrait du contenu"
    Exemples :
      "Articles 241-243 | Divorce : cas et procedure | Divorce sur demande conjointe des epoux"
      "Article 14 | Corps humain : inviolabilite | Il ne peut etre porte atteinte a l'integrite"
    """
    # Niveau 1 : plage d'articles
    plage = f"Article {num_debut}" if num_debut == num_fin else f"Articles {num_debut} a {num_fin}"

    # Niveau 2 : contexte court (on retire le prefixe "Chapitre X : ")
    ctx_brut = chapitre or titre_section or ''
    ctx = re.sub(r'^(Chapitre|Titre|Section|Livre)\s+[IVXivx0-9]+\s*[:\.\-]\s*', '', ctx_brut).strip()
    if len(ctx) > 60:
        ctx = ctx[:57] + '...'

    # Niveau 3 : sujet semantique extrait du contenu
    sujet = extraire_sujet(texte_groupe)

    # Assembler en evitant les repetitions
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
                texte = re.sub(r'^\d+\s*$', '', texte, flags=re.MULTILINE)
                texte = re.sub(r'\n\d+\n', '\n', texte)
                pages.append((i + 1, texte.strip()))
    print(f"Pages extraites: {len(pages)}")
    return pages


# ── PARSER ────────────────────────────────────────────────────────────────────

def parser_articles(pages_texte):
    livre = titre = chapitre = section = ''
    articles = []
    art_num = None
    art_lignes = []
    art_ctx = {}

    def contexte():
        return ' > '.join(p for p in [livre, titre, chapitre, section] if p)

    def sauver():
        if art_num and art_lignes:
            texte = '\n'.join(art_lignes).strip()
            if len(texte.split()) >= 4:
                articles.append({
                    'num':      art_num,
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

        m = RE_LIVRE.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            livre = f"Livre {m.group(1)} : {m.group(2).strip()}"
            titre = chapitre = section = ''
            i += 1; continue

        m = RE_PRELIM.match(ligne)
        if m and not RE_TITRE.match(ligne):
            sauver(); art_num = None; art_lignes = []
            titre = 'Titre preliminaire : De la publication et application des lois'
            chapitre = section = ''
            i += 1; continue

        m = RE_TITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            titre = f"Titre {m.group(1)} : {m.group(2).strip()}"
            chapitre = section = ''
            i += 1; continue

        m = RE_CHAPITRE.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            chapitre = f"Chapitre {m.group(1)} : {m.group(2).strip()}"
            section = ''
            i += 1; continue

        m = RE_SECTION.match(ligne)
        if m:
            sauver(); art_num = None; art_lignes = []
            section = f"Section {m.group(1)} : {m.group(2).strip()}"
            i += 1; continue

        m = RE_ARTICLE.match(ligne)
        if m:
            sauver()
            art_num = int(m.group(1))
            art_lignes = []
            art_ctx = {
                'livre': livre, 'titre': titre,
                'chapitre': chapitre, 'section': section,
                'contexte': contexte(),
            }
            i += 1; continue

        if art_num and ligne and not re.match(r'^\d+$', ligne) and len(ligne) > 2:
            art_lignes.append(ligne)

        i += 1

    sauver()
    return articles


# ── REGROUPEMENT ──────────────────────────────────────────────────────────────

def meme_ctx(a, b):
    return (a['livre'] == b['livre'] and
            a['titre'] == b['titre'] and
            a['chapitre'] == b['chapitre'])


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

    titre = construire_titre(
        num_debut, num_fin,
        premier['chapitre'],
        premier['titre'],
        texte_groupe
    )

    chunk_id = f"art_{num_debut}" if num_debut == num_fin else f"art_{num_debut}_{num_fin}"
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
            'url':         'Code Civil Djiboutien 2018',
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
                    art['num'], art['num'],
                    art['chapitre'], art['titre'], sous
                )
                if part > 0:
                    titre_part += f' (suite {part + 1})'
                chunks.append({
                    'id':       f"art_{art['num']}_p{part}",
                    'titre':    titre_part,
                    'document': f"{titre_part}\n\nArticle {art['num']}\n{sous}",
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
                        'url':         'Code Civil Djiboutien 2018',
                    }
                })
            i += 1
            continue

        # Agglomeration : accumuler jusqu'a CIBLE mots
        groupe = [art]
        mots_groupe = mots
        j = i + 1

        while j < len(articles):
            suivant = articles[j]
            mots_suivant = len(suivant['texte'].split())

            if not meme_ctx(art, suivant):
                break

            if mots_groupe + mots_suivant > MAX_MOTS:
                # Si on est encore sous MIN_MOTS, on accepte de depasser legerement
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


# ── SUPPRESSION ───────────────────────────────────────────────────────────────

def supprimer_chunks_lois(collection):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('category') == 'lois']
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"[OK] {len(ids)} anciens chunks 'lois' supprimes")
    else:
        print("[INFO] Aucun ancien chunk 'lois'")


# ── INGESTION ─────────────────────────────────────────────────────────────────

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
    print(f"[OK] Ingeres: {ingeres} | Doublons ignores: {doublons}")
    return ingeres


# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    print("=" * 65)
    print("INDEXATION CODE CIVIL DJIBOUTIEN v2")
    print("=" * 65)

    print("\n[1/5] Extraction PDF...")
    pages = extraire_texte_pdf(PDF_PATH)

    print("\n[2/5] Parsing articles...")
    articles = parser_articles(pages)
    print(f"Articles detectes: {len(articles)}")
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
        bar = '#' * (dist[k] // 3)
        print(f"  {k:<10} {dist[k]:>4}  {bar}")

    print("\nExemples de titres:")
    step = max(1, len(chunks) // 10)
    for c in chunks[::step][:10]:
        print(f"  [{len(c['document'].split()):>3}m] {c['titre']}")

    print("\n[4/5] Connexion ChromaDB + suppression anciens chunks...")
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection("djibouti_knowledge")
    print(f"Base avant: {collection.count()} chunks")
    supprimer_chunks_lois(collection)

    print("\n[5/5] Ingestion...")
    nb = ingerer(chunks, collection, model)

    print(f"\n{'='*65}")
    print(f"TERMINE | Code civil: {nb} chunks | Base: {collection.count()} total")

    print("\nTest - 'divorce consentement mutuel':")
    emb = model.encode("procedure divorce consentement mutuel epoux").tolist()
    res = collection.query(query_embeddings=[emb], n_results=3,
                           where={"category": "lois"})
    for doc, meta in zip(res['documents'][0], res['metadatas'][0]):
        print(f"  -> {meta['title']}")
        print(f"     {doc[doc.find(chr(10))+1:doc.find(chr(10))+1+120].replace(chr(10),' ')}")
        print()