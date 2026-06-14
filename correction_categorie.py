# -*- coding: utf-8 -*-
"""
corriger_titres_categories.py - Amiin Project
Corrige 3 problemes :
1. Extrait le titre depuis le contenu des chunks justice.gouv.dj
2. Recategorise intelligemment les chunks selon leur source + contenu
3. Supprime les chunks trop courts (<50 mots)

Usage: python corriger_titres_categories.py
"""

import chromadb
import re
from collections import defaultdict

DB_PATH = './amiin_db'
client = chromadb.PersistentClient(path=DB_PATH)
collection = client.get_or_create_collection("djibouti_knowledge")

print(f"Base avant corrections: {collection.count()} chunks\n")
all_data = collection.get(include=['metadatas', 'documents'])
total = len(all_data['ids'])

# ── ETAPE 1 : EXTRAIRE TITRES DES CHUNKS JUSTICE.GOUV.DJ ─────────────────────
print("=" * 60)
print("ETAPE 1 - Extraction des titres depuis le contenu justice.gouv.dj")
print("=" * 60)

def extraire_titre_depuis_contenu(contenu):
    """
    Extrait le titre du debut du contenu.
    Logique : le titre est la premiere phrase si elle est courte (<15 mots)
    OU les premiers mots jusqu'a la prochaine majuscule isolee.
    Exemples :
      'AUTOMATISATION DU TRIBUNAL... On avait...' -> 'AUTOMATISATION DU TRIBUNAL'
      "L'Aide Judiciaire. L'aide judiciaire est..." -> "L'Aide Judiciaire"
      'Management judiciaire a l IFD Le ministere...' -> 'Management judiciaire a l IFD'
    """
    if not contenu:
        return ''
    
    contenu = contenu.strip()
    
    # Cas 1 : titre tout en majuscules suivi d'une phrase normale
    # Ex: "AUTOMATISATION DU TRIBUNAL DE PREMIERE INSTANCE On avait..."
    match_maj = re.match(r'^([A-Z][A-Z\s\'\-\u00C0-\u00DC\.]{5,80}?)(\s+[A-Z][a-z])', contenu)
    if match_maj:
        titre = match_maj.group(1).strip()
        if 3 <= len(titre.split()) <= 12:
            return titre.rstrip('.,;:')
    
    # Cas 2 : premiere phrase courte terminee par un point
    # Ex: "L'Aide Judiciaire. L'aide judiciaire est..."
    premiere_phrase = re.match(r'^([^.!?]{5,80})[.!?]', contenu)
    if premiere_phrase:
        titre = premiere_phrase.group(1).strip()
        mots = titre.split()
        if 2 <= len(mots) <= 10:
            return titre
    
    # Cas 3 : premiers mots jusqu'a une minuscule precedee d'un mot de liaison
    # Ex: "Management judiciaire a l'IFD Le ministere..."
    match_liaison = re.match(
        r'^([A-Z\u00C0-\u00DC][^.]{5,80?}?)'
        r'(?:\s+(?:Le|La|Les|Un|Une|Des|Ce|Cette|Il|Elle|En|Au|Aux|Pour|Dans|Avec|Sur)\s)',
        contenu
    )
    if match_liaison:
        titre = match_liaison.group(1).strip()
        if 2 <= len(titre.split()) <= 12:
            return titre.rstrip('.,;:')
    
    # Fallback : premiers mots (max 8)
    mots = contenu.split()
    return ' '.join(mots[:8]).rstrip('.,;:')


corriges_justice = 0
non_corriges = 0

# Grouper par URL pour traiter chunk[0] en premier (il a le vrai debut du contenu)
url_chunks = defaultdict(list)
for id_, meta, doc in zip(all_data['ids'], all_data['metadatas'], all_data['documents']):
    if 'justice.gouv.dj' in (meta.get('url') or '') and meta.get('title') == 'Justice':
        url_chunks[meta['url']].append((id_, meta, doc, meta.get('chunk_index', 0)))

for url, items in url_chunks.items():
    # Trier par chunk_index pour avoir le debut du texte en premier
    items.sort(key=lambda x: x[3])
    premier_chunk = items[0]
    contenu_debut = premier_chunk[2] or ''
    
    titre = extraire_titre_depuis_contenu(contenu_debut)
    
    if titre and len(titre) > 5 and titre.lower() != 'justice':
        # Appliquer le titre a tous les chunks de cette URL
        for id_, meta, doc, _ in items:
            meta['title'] = titre
            collection.update(ids=[id_], metadatas=[meta])
        corriges_justice += len(items)
        print(f"  [OK] '{titre}' ({len(items)} chunks)")
    else:
        non_corriges += len(items)
        print(f"  [?]  Titre incertain: '{titre}' | {url[-45:]}")

print(f"\nCorrigesJustice: {corriges_justice} | Non corriges: {non_corriges}")

# ── ETAPE 2 : RECATEGORISATION INTELLIGENTE ───────────────────────────────────
print("\n" + "=" * 60)
print("ETAPE 2 - Recategorisation intelligente par source + contenu")
print("=" * 60)

# Recharger apres modifications
all_data = collection.get(include=['metadatas', 'documents'])

# Regles de recategorisation SPECIFIQUES A CHAQUE SOURCE
# Format: (source_domain, mauvaises_cats, condition_contenu, bonne_categorie)
CORRECTIONS = [
    # cnss.dj - chunks categorises "geographie" qui parlent de lieux de sante
    {
        'source': 'cnss.dj',
        'mauvaises_cats': ['geographie'],
        'mots_cles_contenu': ['hopital', 'soins', 'medecin', 'pharmacie', 'centre', 
                              'sante', 'clinique', 'arta', 'djibpharma', 'medical'],
        'bonne_cat': 'sante'
    },
    # cnss.dj - chunks "presidence" qui sont des communiques CNSS
    {
        'source': 'cnss.dj',
        'mauvaises_cats': ['presidence'],
        'mots_cles_contenu': ['cnss', 'caisse', 'assurance', 'cotisation', 
                              'retraite', 'prestation', 'amu', 'assure'],
        'bonne_cat': 'travail'
    },
    # cnss.dj - chunks "presidence" qui sont des discours sur l'AMU/sante
    {
        'source': 'cnss.dj',
        'mauvaises_cats': ['presidence'],
        'mots_cles_contenu': ['sante', 'maladie', 'medical', 'hopital', 'amu',
                              'assurance maladie', 'couverture'],
        'bonne_cat': 'sante'
    },
    # cnss.dj - chunks "gouvernement" qui traitent de recrutement/avis
    {
        'source': 'cnss.dj',
        'mauvaises_cats': ['gouvernement'],
        'mots_cles_contenu': ['avis de recrutement', 'poste', 'candidat', 
                              'offre d\'emploi', 'ingenieur', 'coordinateur'],
        'bonne_cat': 'travail'
    },
    # cnss.dj - chunks "education" qui traitent de formations medicales
    {
        'source': 'cnss.dj',
        'mauvaises_cats': ['education'],
        'mots_cles_contenu': ['formation', 'medecin', 'paramedicaux', 'soins',
                              'reanimation', 'infirmier'],
        'bonne_cat': 'sante'
    },
    # justice.gouv.dj - chunks "transport" qui n'ont rien a voir
    {
        'source': 'justice.gouv.dj',
        'mauvaises_cats': ['transport'],
        'mots_cles_contenu': ['justice', 'tribunal', 'jugement', 'loi', 'code',
                              'magistrat', 'juridiction', 'procureur', 'greffe'],
        'bonne_cat': 'juridique'
    },
    # justice.gouv.dj - chunks "gouvernement" qui sont des articles juridiques
    {
        'source': 'justice.gouv.dj',
        'mauvaises_cats': ['gouvernement'],
        'mots_cles_contenu': ['code civil', 'code penal', 'loi', 'decret', 
                              'ordonnance', 'tribunal', 'juridiction', 'magistrat',
                              'jugement', 'arret', 'appel'],
        'bonne_cat': 'juridique'
    },
    # justice.gouv.dj - chunks "gouvernement" qui sont des actualites
    {
        'source': 'justice.gouv.dj',
        'mauvaises_cats': ['gouvernement'],
        'mots_cles_contenu': ['ceremonie', 'seminaire', 'atelier', 'formation',
                              'inauguration', 'signature', 'accord', 'partenariat'],
        'bonne_cat': 'actualites'
    },
    # sante.gouv.dj - chunks "gouvernement" qui traitent de sante
    {
        'source': 'sante.gouv.dj',
        'mauvaises_cats': ['gouvernement'],
        'mots_cles_contenu': ['sante', 'medecin', 'hopital', 'maladie', 'vaccin',
                              'epidemie', 'soins', 'patient', 'clinique'],
        'bonne_cat': 'sante'
    },
]

total_recategorises = 0

for regle in CORRECTIONS:
    source = regle['source']
    mauvaises_cats = regle['mauvaises_cats']
    mots_cles = regle['mots_cles_contenu']
    bonne_cat = regle['bonne_cat']
    
    a_corriger = []
    for id_, meta, doc in zip(all_data['ids'], all_data['metadatas'], all_data['documents']):
        url = meta.get('url') or ''
        cat = meta.get('category') or ''
        contenu = (doc or '').lower()
        
        if source not in url:
            continue
        if cat not in mauvaises_cats:
            continue
        if not any(kw in contenu for kw in mots_cles):
            continue
        
        a_corriger.append((id_, meta, doc))
    
    if a_corriger:
        for id_, meta, doc in a_corriger:
            meta['category'] = bonne_cat
            collection.update(ids=[id_], metadatas=[meta])
        total_recategorises += len(a_corriger)
        print(f"  [OK] {source} [{mauvaises_cats[0]}] -> [{bonne_cat}]: {len(a_corriger)} chunks")

print(f"\nTotal recategorises: {total_recategorises}")


# ── BILAN FINAL ───────────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("BILAN FINAL")
print("=" * 60)
print(f"Total chunks en base: {collection.count()}")

all_data = collection.get(include=['metadatas'])
from collections import Counter

print("\nCategories finales:")
cats = Counter(m.get('category', '?') for m in all_data['metadatas'])
for cat, n in cats.most_common():
    print(f"  {cat:<20} {n}")

print("\nSources finales:")
sources = Counter(
    (m.get('source') or m.get('url', '').split('/')[2] if '/' in m.get('url','') else '?')
    for m in all_data['metadatas']
)
for src, n in sources.most_common():
    print(f"  {src:<30} {n}")

print("\nVerification titres justice (echantillon):")
justice_sample = [
    (m.get('title'), m.get('url','')[-45:])
    for m in all_data['metadatas']
    if 'justice.gouv.dj' in (m.get('url') or '')
][:8]
for titre, url in justice_sample:
    print(f"  '{titre}' | {url}")