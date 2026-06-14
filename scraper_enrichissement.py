# -*- coding: utf-8 -*-
"""
scraper_enrichissement.py - Amiin Project (v2 corrigé)
Scrape et indexe du contenu depuis Wikipedia FR et Visit Djibouti.

Corrections v2:
  - Noms d'articles Wikipedia corrigés (Lac_Assal, Franc_djiboutien, etc.)
  - Titres descriptifs basés sur les sections Wikipedia (pas "Djibouti partie 1")
  - Catégories appropriées par article (culture, tourisme, géographie, etc.)
  - Gestion des articles à 0 mots (exsectionformat corrigé)

Usage:
  python scraper_enrichissement.py --source wikipedia --dry-run
  python scraper_enrichissement.py --source wikipedia
  python scraper_enrichissement.py --source visitdjibouti
  python scraper_enrichissement.py --source all
"""

import argparse
import re
import time
import requests
from bs4 import BeautifulSoup
from collections import Counter, defaultdict
import chromadb
from sentence_transformers import SentenceTransformer

DB_PATH    = './amiin_db'
COLLECTION = 'djibouti_knowledge'
MODEL_NAME = 'paraphrase-multilingual-MiniLM-L12-v2'

MAX_MOTS   = 480
OVERLAP    = 50

HEADERS = {
    'User-Agent': 'AmIIn-Bot/1.0 (Djibouti Knowledge Base; educational project)'
}

# ══════════════════════════════════════════════════════════════════════════════
# UTILITAIRES
# ══════════════════════════════════════════════════════════════════════════════

def decouper_texte(texte, titre_base, source, category, url, prefix_id, extra_meta=None):
    mots = texte.split()
    if not mots:
        return []
    chunks = []
    i = 0
    part = 0
    while i < len(mots):
        fin = min(i + MAX_MOTS, len(mots))
        sous_texte = ' '.join(mots[i:fin])
        part += 1
        meta = {
            'title': titre_base if part == 1 and fin >= len(mots) else f"{titre_base} (partie {part})",
            'category': category,
            'source': source,
            'url': url,
            'type': 'scrape_enrichissement',
        }
        if extra_meta:
            meta.update(extra_meta)
        chunks.append({
            'id': f"{prefix_id}_{part:03d}",
            'document': sous_texte,
            'metadata': meta
        })
        i = fin - OVERLAP if fin < len(mots) else fin
    return chunks


def nettoyer_texte(texte):
    texte = re.sub(r'\[\d+\]', '', texte)
    texte = re.sub(r'\[réf\.\s*nécessaire\]', '', texte)
    texte = re.sub(r'\n{3,}', '\n\n', texte)
    texte = re.sub(r' {2,}', ' ', texte)
    # Supprimer les lignes de navigation Wikipedia
    texte = re.sub(r'↑ .*', '', texte)
    return texte.strip()


# ══════════════════════════════════════════════════════════════════════════════
# WIKIPEDIA - Liste d'articles avec noms EXACTS et catégories
# ══════════════════════════════════════════════════════════════════════════════

WIKIPEDIA_ARTICLES = [
    # (nom_article_wikipedia, catégorie_amiin)
    # Général
    ("Djibouti", "geographie"),
    ("Djibouti_(ville)", "geographie"),
    ("Histoire_de_Djibouti", "culture"),
    ("Géographie_de_Djibouti", "geographie"),
    ("Économie_de_Djibouti", "economie"),
    ("Politique_à_Djibouti", "gouvernement"),
    ("Indépendance_de_Djibouti", "culture"),
    ("Démographie_de_Djibouti", "geographie"),
    ("Culture_de_Djibouti", "culture"),
    ("Franc Djibouti", "economie"),
    ("Subdivision_de_Djibouti", "gouvernement"),

    # Villes et régions
    ("Tadjoura (Djibouti)", "geographie"),
    ("Ali_Sabieh", "geographie"),
    ("Dikhil", "geographie"),
    ("Obock", "geographie"),
    ("Arta_(Djibouti)", "geographie"),
    ("Balbala", "geographie"),

    # Sites naturels
    ("Lac_Assal", "tourisme"),
    ("Lac_Abbe", "tourisme"),
    ("Parc_national_de_la_Forêt_de_Day", "tourisme"),
    ("Île Moucha", "tourisme"),
    ("Ghoubbet-el-Kharab", "tourisme"),
    ("Golfe de Tadjoura", "geographie"),
    ("Ardoukôba", "tourisme"),
    ("Dépression_de_l'Afar", "geographie"),

    # Infrastructure
    ("Port_de_Djibouti", "economie"),
    ("Aéroport_international_Ambouli", "transport"),
    ("Chemin_de_fer_djibouto-éthiopien", "transport"),

    # Politique et institutions
    ("Gouvernement_Abdoulkader_Kamil_Mohamed", "gouvernement"),
    ("Ismaïl_Omar_Guelleh", "gouvernement"),
    ("Hassan_Gouled_Aptidon", "culture"),
    ("Constitution_de_Djibouti", "gouvernement"),
    ("Assemblée_nationale_(Djibouti)", "gouvernement"),
    ("Gouvernement_djiboutien", "gouvernement"),

    # Divers
    ("Afars", "culture"),
    ("Issas", "culture"),
    ("Cuisine_djiboutienne", "culture"),
    ("Somali", "culture"),
    ("Gadabuursi", "culture"),
    ("Issas", "culture"),
    ("Sultanat_de_Tadjoura", "culture"),
    ("Bab-el-Mandeb", "geographie"),
    ("Côte française des Somalis", "culture"),
]


def extraire_sections_wikipedia(texte, titre_article):
    """Extrait les sections d'un article Wikipedia et retourne des paires (titre_section, contenu)."""
    # Séparer par sections de niveau 2
    parts = re.split(r'\n== (.+?) ==\n', texte)

    sections = []
    if parts[0].strip():
        sections.append((f"{titre_article} - Présentation générale", parts[0].strip()))

    for j in range(1, len(parts), 2):
        section_titre = parts[j].strip() if j < len(parts) else ''
        section_contenu = parts[j+1].strip() if j+1 < len(parts) else ''

        # Nettoyer les sous-sections (=== ... ===)
        # Garder le contenu mais intégrer le titre de sous-section dans le texte
        section_contenu = re.sub(r'=== (.+?) ===', r'\1 :', section_contenu)
        section_contenu = re.sub(r'==== (.+?) ====', r'\1 :', section_contenu)

        # Ignorer les sections vides ou trop courtes
        if len(section_contenu.split()) < 30:
            continue

        # Ignorer les sections non pertinentes
        skip = ['Notes et références', 'Voir aussi', 'Bibliographie', 'Liens externes',
                'Articles connexes', 'Sources', 'Notes', 'Références']
        if section_titre in skip:
            continue

        sections.append((f"{titre_article} - {section_titre}", section_contenu))

    return sections


def scraper_wikipedia():
    print(f"\n  📚 Scraping Wikipedia ({len(WIKIPEDIA_ARTICLES)} articles)...")
    tous_chunks = []

    for i, (article, category) in enumerate(WIKIPEDIA_ARTICLES):
        url_api = "https://fr.wikipedia.org/w/api.php"
        params = {
            'action': 'query',
            'titles': article.replace('_', ' '),
            'prop': 'extracts',
            'explaintext': True,
            'format': 'json',
        }

        try:
            resp = requests.get(url_api, params=params, headers=HEADERS, timeout=15)
            data = resp.json()
            pages = data.get('query', {}).get('pages', {})

            for page_id, page in pages.items():
                if page_id == '-1':
                    print(f"    ❌ Non trouvé: {article}")
                    continue

                titre = page.get('title', article.replace('_', ' '))
                texte = page.get('extract', '')
                texte = nettoyer_texte(texte)

                if len(texte.split()) < 50:
                    print(f"    ⚠️ Trop court: {titre} ({len(texte.split())} mots)")
                    continue

                # Extraire les sections
                sections = extraire_sections_wikipedia(texte, titre)

                if not sections:
                    # Pas de sections, découper le texte entier
                    slug = re.sub(r'[^a-z0-9]+', '_', article.lower())[:30]
                    chunks = decouper_texte(
                        texte, titre,
                        'Wikipedia FR', category,
                        f"https://fr.wikipedia.org/wiki/{article}",
                        f"wiki_{slug}"
                    )
                    tous_chunks.extend(chunks)
                else:
                    # Découper chaque section
                    for section_titre, section_contenu in sections:
                        slug_art = re.sub(r'[^a-z0-9]+', '_', article.lower())[:20]
                        slug_sec = re.sub(r'[^a-z0-9]+', '_', section_titre.lower())[:25]

                        chunks = decouper_texte(
                            section_contenu, section_titre,
                            'Wikipedia FR', category,
                            f"https://fr.wikipedia.org/wiki/{article}",
                            f"wiki_{slug_art}_{slug_sec}"
                        )
                        tous_chunks.extend(chunks)

                print(f"    [{i+1}/{len(WIKIPEDIA_ARTICLES)}] {titre}: "
                      f"{len(texte.split())} mots → {len(sections)} sections")

        except Exception as e:
            print(f"    ❌ Erreur {article}: {e}")

        time.sleep(0.5)

    print(f"  → {len(tous_chunks)} chunks Wikipedia générés")
    return tous_chunks


# ══════════════════════════════════════════════════════════════════════════════
# VISIT DJIBOUTI
# ══════════════════════════════════════════════════════════════════════════════

VISITDJIBOUTI_PAGES = [
    ("https://guide.visitdjibouti.dj/a-savoir-informations-sur-le-pays/", "Djibouti - Informations générales", "tourisme"),
    ("https://guide.visitdjibouti.dj/a-savoir-informations-sur-le-pays/notre-histoire/", "Histoire de Djibouti - Guide touristique", "culture"),
    ("https://guide.visitdjibouti.dj/a-savoir-informations-sur-le-pays/geographie/", "Géographie de Djibouti - Guide touristique", "tourisme"),
    ("https://guide.visitdjibouti.dj/a-savoir-informations-sur-le-pays/notre-peuple/", "Peuple djiboutien", "culture"),
    ("https://guide.visitdjibouti.dj/en-avion/", "Vols et compagnies aériennes vers Djibouti", "transport"),
    ("https://guide.visitdjibouti.dj/front-page/", "Visa et formalités d'entrée à Djibouti", "administrative"),
    ("https://guide.visitdjibouti.dj/vie-pratique/", "Conseils pratiques de voyage à Djibouti", "tourisme"),
    # Sous-pages Culture
    ("https://guide.visitdjibouti.dj/culture/un-pays-ou-le-brassage-est-le-barycentre/", "Culture djiboutienne - Brassage culturel", "culture"),
    ("https://guide.visitdjibouti.dj/culture/splendeur-des-joutes-oratoires-et-des-danses-rythmees/", "Danses et joutes oratoires djiboutiennes", "culture"),
    ("https://guide.visitdjibouti.dj/savoir-faire-et-dexterite-nomade/", "Artisanat nomade djiboutien", "culture"),
    # Sous-pages Hébergement
    ("https://guide.visitdjibouti.dj/liste-des-hotels/", "Liste des hôtels touristiques à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/campement-touristique-2/", "Campements touristiques à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/hotel-dans-les-regions/", "Hôtels dans les régions de Djibouti", "tourisme"),
    # Sous-pages Activités Nature
    ("https://guide.visitdjibouti.dj/activites-nature/randonnee-riche-en-contrastes-et-rencontres-idylliques/", "Randonnées et trekking à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/activites-nature/dans-le-sillage-de-la-caravane-de-sel/", "Caravane de sel - Lac Assal", "tourisme"),
    ("https://guide.visitdjibouti.dj/activites-nature/un-club-de-golf-hors-du-commun/", "Golf de Douda à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/activites-nature/observation-ornithologique-pointue/", "Observation ornithologique à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/activites-nature/le-char-a-voile-une-invitation-a-laventure/", "Char à voile au Grand Bara", "tourisme"),
    ("https://guide.visitdjibouti.dj/activites-nature/le-cross-du-15-km-du-grand-bara/", "Cross du Grand Bara - 15 km", "tourisme"),
    # Sous-pages Plages
    ("https://guide.visitdjibouti.dj/la-plage-de-khor-ambado/", "Plage de Khor Ambado", "tourisme"),
    ("https://guide.visitdjibouti.dj/la-plage-de-douda/", "Plage de Douda", "tourisme"),
    ("https://guide.visitdjibouti.dj/la-plage-des-sables-blancs/", "Plage des Sables Blancs", "tourisme"),
    ("https://guide.visitdjibouti.dj/la-plage-de-raysali/", "Plage de Raysali", "tourisme"),
    ("https://guide.visitdjibouti.dj/la-somptueuse-plage-darta/", "Plage d'Arta", "tourisme"),
    # Sous-pages Activités Balnéaires
    ("https://guide.visitdjibouti.dj/les-requins-baleines/", "Requins baleines à Djibouti - Nage et observation", "tourisme"),
    ("https://guide.visitdjibouti.dj/decouverte-du-fond-marin/", "Plongée sous-marine à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/croisiere-de-plongee/", "Croisière de plongée à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/la-peche-sportive/", "Pêche sportive à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/canoe-kayak-2/", "Canoë kayak à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/le-kit-surf/", "Kitesurf à Djibouti", "tourisme"),
    ("https://guide.visitdjibouti.dj/jet-ski-a-djibouti/", "Jet ski à Djibouti", "tourisme"),
    # Sous-pages Transport
    ("https://guide.visitdjibouti.dj/en-ville/", "Se déplacer en ville à Djibouti", "transport"),
    ("https://guide.visitdjibouti.dj/en-regions/", "Se déplacer en régions à Djibouti", "transport"),
]


def scraper_visitdjibouti():
    print(f"\n  🏖️ Scraping Visit Djibouti ({len(VISITDJIBOUTI_PAGES)} pages)...")
    tous_chunks = []

    for i, (url, titre, cat) in enumerate(VISITDJIBOUTI_PAGES):
        try:
            resp = requests.get(url, headers=HEADERS, timeout=15)
            resp.encoding = 'utf-8'
            soup = BeautifulSoup(resp.text, 'html.parser')

            content = soup.find('div', class_='entry-content') or soup.find('article') or soup.find('main')
            if not content:
                print(f"    ⚠️ Pas de contenu: {titre}")
                continue

            for tag in content.find_all(['script', 'style', 'nav', 'footer', 'header', 'iframe']):
                tag.decompose()

            texte = content.get_text(separator='\n', strip=True)
            texte = nettoyer_texte(texte)

            if len(texte.split()) < 30:
                print(f"    ⚠️ Trop court: {titre} ({len(texte.split())} mots)")
                continue

            slug = re.sub(r'[^a-z0-9]+', '_', titre.lower())[:30]
            chunks = decouper_texte(
                texte, titre,
                'guide.visitdjibouti.dj', cat, url,
                f"vdj_{slug}"
            )
            tous_chunks.extend(chunks)
            print(f"    [{i+1}/{len(VISITDJIBOUTI_PAGES)}] {titre}: "
                  f"{len(texte.split())} mots → {len(chunks)} chunks")

        except Exception as e:
            print(f"    ❌ Erreur {titre}: {e}")

        time.sleep(1)

    print(f"  → {len(tous_chunks)} chunks Visit Djibouti générés")
    return tous_chunks


# ══════════════════════════════════════════════════════════════════════════════
# INGESTION
# ══════════════════════════════════════════════════════════════════════════════

def supprimer_anciens(collection, source_tag):
    data = collection.get(include=['metadatas'])
    ids = [id_ for id_, meta in zip(data['ids'], data['metadatas'])
           if meta.get('source') == source_tag]
    if ids:
        for k in range(0, len(ids), 500):
            collection.delete(ids=ids[k:k+500])
        print(f"  {len(ids)} anciens chunks '{source_tag}' supprimés")


def ingerer(chunks, collection, model):
    print(f"\n  Ingestion de {len(chunks)} chunks...")
    ingeres = doublons = 0
    for k, chunk in enumerate(chunks):
        emb = model.encode(chunk['document']).tolist()
        try:
            collection.upsert(
                ids=[chunk['id']],
                embeddings=[emb],
                documents=[chunk['document']],
                metadatas=[chunk['metadata']]
            )
            ingeres += 1
        except Exception:
            doublons += 1
        if (k + 1) % 50 == 0:
            print(f"    {k+1}/{len(chunks)}...")
    print(f"  ✅ Ingérés: {ingeres} | Doublons: {doublons}")
    return ingeres


def afficher_stats(chunks):
    mots_list = [len(c['document'].split()) for c in chunks]
    if not mots_list:
        return
    print(f"\n  Stats: {len(chunks)} chunks | Moy: {sum(mots_list)//len(mots_list)}m | "
          f"Min: {min(mots_list)}m | Max: {max(mots_list)}m")
    cats = Counter(c['metadata']['category'] for c in chunks)
    for cat, n in cats.most_common():
        print(f"    {cat:<25} {n}")
    print(f"\n  Exemples de titres:")
    step = max(1, len(chunks) // 10)
    for c in chunks[::step][:10]:
        mots = len(c['document'].split())
        print(f"    [{mots:>3}m] {c['metadata']['title'][:75]}")


# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description='Scraper enrichissement Amiin v2')
    parser.add_argument('--source', required=True,
                        choices=['wikipedia', 'visitdjibouti', 'all'])
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    print("=" * 65)
    print("SCRAPING ENRICHISSEMENT v2 - AMIIN")
    print("=" * 65)

    tous_chunks = []

    if args.source in ('wikipedia', 'all'):
        tous_chunks.extend(scraper_wikipedia())
    if args.source in ('visitdjibouti', 'all'):
        tous_chunks.extend(scraper_visitdjibouti())

    if not tous_chunks:
        print("\n  Aucun chunk généré.")
        return

    afficher_stats(tous_chunks)

    if args.dry_run:
        print(f"\n  [DRY RUN] {len(tous_chunks)} chunks prêts. Aucune ingestion.")
        return

    print(f"\nChargement modèle et base...")
    model = SentenceTransformer(MODEL_NAME)
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(COLLECTION)
    count_before = collection.count()
    print(f"Base avant: {count_before} chunks")

    if args.source in ('wikipedia', 'all'):
        supprimer_anciens(collection, 'Wikipedia FR')
    if args.source in ('visitdjibouti', 'all'):
        supprimer_anciens(collection, 'guide.visitdjibouti.dj')

    nb = ingerer(tous_chunks, collection, model)

    count_after = collection.count()
    print(f"\n{'='*65}")
    print(f"TERMINÉ | {nb} chunks ingérés | Base: {count_before} → {count_after} ({count_after-count_before:+d})")
    print(f"{'='*65}")


if __name__ == '__main__':
    main()