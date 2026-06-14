# -*- coding: utf-8 -*-
"""
amiin_rag.py - Pipeline RAG du chatbot Amiin (v2)
Query → Expansion Claude → Multi-recherche ChromaDB → Fusion → Claude API → Réponse

Améliorations v2 :
  - Expansion de query : Claude reformule la question en 3 variantes (juridique, pratique, mots-clés)
  - Multi-recherche : chaque variante cherche séparément dans ChromaDB
  - Déduplication et fusion des résultats par pertinence
  - Filtrage par seuil de distance (élimine le bruit)
  - Support distance cosine (après migration)

Usage:
  python amiin_rag.py                          # Mode interactif
  python amiin_rag.py --query "Ma question"    # Question unique
  python amiin_rag.py --debug                  # Affiche les chunks et l'expansion
  python amiin_rag.py --no-expand              # Désactive l'expansion (mode basique)
"""

import os
import json
import argparse
import chromadb
from sentence_transformers import SentenceTransformer

# ── CONFIGURATION ─────────────────────────────────────────────────────────────

DB_PATH        = './amiin_db'
COLLECTION     = 'djibouti_knowledge'
MODEL_EMBED    = 'paraphrase-multilingual-MiniLM-L12-v2'
MODEL_CLAUDE   = 'claude-haiku-4-5-20251001'
TOP_K          = 10         # Chunks par recherche
TOP_K_FINAL    = 12          # Chunks envoyés à Claude après fusion
MAX_TOKENS     = 2048
TEMPERATURE    = 0.3
EXPAND_MODEL   = 'claude-haiku-4-5-20251001'  # Modèle pour l'expansion (le moins cher)

# ── PROMPT SYSTÈME ────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """Tu es Amiin, un assistant IA expert sur Djibouti. Ton nom signifie "digne de confiance" en somali.

Tu aides les citoyens djiboutiens, les expatriés et les visiteurs avec :
- Les lois et réglementations djiboutiennes (codes civil, pénal, famille, travail, commerce, etc.)
- Les démarches administratives (visas, titres de séjour, création d'entreprise, CNSS, etc.)
- La vie pratique (hôtels, restaurants, banques, hôpitaux, pharmacies, transport, etc.)
- Le tourisme (Lac Assal, Lac Abbé, îles Moucha, plongée, etc.)
- Les services et commerces de Djibouti-ville

RÈGLES IMPORTANTES :
1. Réponds UNIQUEMENT à partir des informations fournies dans le contexte ci-dessous.
2. Si le contexte ne contient pas l'information demandée, dis-le honnêtement.
3. Ne fabrique JAMAIS d'information. Pas d'hallucination.
4. Cite les sources et articles de loi quand c'est pertinent.
5. Réponds en français par défaut. Si l'utilisateur écrit en somali ou en arabe, réponds dans sa langue.
6. Sois concis mais complet. Donne les numéros de téléphone, adresses et prix quand disponibles.
7. Adopte un ton chaleureux et professionnel.
8. Pour les articles de lois, soit le plus explicatif possible et vulgarise pour faciliter la compréhension.
9. Si le contexte RAG contient des articles de loi ou des données locales spécifiques, utilise-les en priorité. Si le contexte ne contient pas l'information demandée et que la question porte sur des connaissances générales sur Djibouti, tu peux répondre avec tes connaissances propres en le précisant.

CONTEXTE (informations de la base de connaissances) :
{context}
"""

# ── PROMPT D'EXPANSION DE QUERY ──────────────────────────────────────────────

EXPAND_PROMPT = """Tu es un expert en recherche d'information sur Djibouti. 
L'utilisateur pose une question. Tu dois la reformuler en EXACTEMENT 3 variantes pour maximiser les chances de trouver l'information dans une base de données juridique et pratique.

Règles :
- Variante 1 : rien
- Variante 2 : reformulation en termes PRATIQUES/QUOTIDIENS (comment un djiboutien poserait la question)
- Variante 3 : MOTS-CLÉS essentiels séparés par des espaces (5-8 mots maximum, les plus discriminants)

Réponds UNIQUEMENT en JSON, sans backticks, sans explication :
{"v1": "...", "v2": "...", "v3": "..."}

Question : {query}"""

# ── CHARGEMENT ────────────────────────────────────────────────────────────────

def charger_composants():
    print("Chargement du modèle d'embedding...")
    model = SentenceTransformer(MODEL_EMBED)
    print(f"Connexion à ChromaDB ({DB_PATH})...")
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(COLLECTION)
    print(f"Base chargée : {collection.count()} chunks")
    return model, collection


def charger_claude():
    try:
        from anthropic import Anthropic
    except ImportError:
        print("ERREUR: pip install anthropic")
        exit(1)

    api_key = os.environ.get('ANTHROPIC_API_KEY')
    if not api_key:
        env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
        if os.path.exists(env_path):
            with open(env_path, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('ANTHROPIC_API_KEY='):
                        api_key = line.split('=', 1)[1].strip().strip('"').strip("'")
                        break
    if not api_key:
        print("ERREUR: Clé API manquante. Créer .env avec ANTHROPIC_API_KEY=sk-ant-...")
        exit(1)

    return Anthropic(api_key=api_key)


# ── EXPANSION DE QUERY ────────────────────────────────────────────────────────

def expandre_query(client, query, debug=False):
    """Demande à Claude de reformuler la question en 3 variantes."""
    try:
        response = client.messages.create(
            model=EXPAND_MODEL,
            max_tokens=300,
            temperature=0.0,
            messages=[{
                "role": "user",
                "content": EXPAND_PROMPT.replace("{query}", query)
            }]
        )
        texte = response.content[0].text.strip()
        texte = texte.replace('```json', '').replace('```', '').strip()
        variantes = json.loads(texte)

        if debug:
            print(f"\n  📝 Expansion de query :")
            print(f"     Original: {query}")
            print(f"     V1 (juridique):  {variantes.get('v1', '?')}")
            print(f"     V2 (pratique):   {variantes.get('v2', '?')}")
            print(f"     V3 (mots-clés):  {variantes.get('v3', '?')}")

        return [query, variantes.get('v1', ''), variantes.get('v2', ''), variantes.get('v3', '')]

    except Exception as e:
        if debug:
            print(f"\n  ⚠️ Expansion échouée: {e}")
        return [query]


# ── RECHERCHE SÉMANTIQUE ─────────────────────────────────────────────────────

def rechercher(query, model, collection, top_k=TOP_K):
    embedding = model.encode(query).tolist()
    resultats = collection.query(
        query_embeddings=[embedding],
        n_results=top_k,
        include=['documents', 'metadatas', 'distances']
    )
    chunks = []
    for i in range(len(resultats['ids'][0])):
        chunks.append({
            'id':       resultats['ids'][0][i],
            'document': resultats['documents'][0][i],
            'metadata': resultats['metadatas'][0][i],
            'distance': resultats['distances'][0][i],
            'query':    query[:50],
        })
    return chunks


def multi_recherche(queries, model, collection, top_k=TOP_K, top_k_final=TOP_K_FINAL, debug=False):
    """Lance plusieurs recherches et fusionne les résultats dédupliqués."""
    tous_chunks = {}

    for q in queries:
        if not q.strip():
            continue
        chunks = rechercher(q, model, collection, top_k)
        for chunk in chunks:
            cid = chunk['id']
            if cid not in tous_chunks or chunk['distance'] < tous_chunks[cid]['distance']:
                tous_chunks[cid] = chunk

    resultats = sorted(tous_chunks.values(), key=lambda c: c['distance'])

    if debug:
        print(f"\n  🔍 Multi-recherche : {len(queries)} queries → "
              f"{len(tous_chunks)} chunks uniques → top {top_k_final}")

    return resultats[:top_k_final]


# ── CONSTRUCTION DU CONTEXTE ─────────────────────────────────────────────────

def construire_contexte(chunks):
    parties = []
    for i, chunk in enumerate(chunks, 1):
        meta = chunk['metadata']
        source = meta.get('source', '')
        titre  = meta.get('title', '')
        cat    = meta.get('category', '')
        header = f"[Source {i}: {source} | {titre} | {cat}]"
        parties.append(f"{header}\n{chunk['document']}")
    return '\n\n---\n\n'.join(parties)


# ── APPEL À CLAUDE ────────────────────────────────────────────────────────────

def interroger_claude(client, query, contexte):
    system = SYSTEM_PROMPT.replace('{context}', contexte)
    response = client.messages.create(
        model=MODEL_CLAUDE,
        max_tokens=MAX_TOKENS,
        temperature=TEMPERATURE,
        system=system,
        messages=[{"role": "user", "content": query}]
    )
    return response.content[0].text


# ── DEBUG ─────────────────────────────────────────────────────────────────────

def afficher_debug(query, chunks):
    print(f"\n{'─'*65}")
    print(f"QUERY: {query}")
    print(f"CHUNKS RETENUS: {len(chunks)}")
    print(f"{'─'*65}")
    for i, chunk in enumerate(chunks, 1):
        meta = chunk['metadata']
        dist = chunk['distance']
        mots = len(chunk['document'].split())
        via  = chunk.get('query', '')
        print(f"\n  [{i}] Dist: {dist:.4f} | {mots}m | via: «{via}»")
        print(f"      Source: {meta.get('source', '?')}")
        print(f"      Titre:  {meta.get('title', '?')[:80]}")
        print(f"      Cat:    {meta.get('category', '?')}")
        print(f"      Extrait: {chunk['document'][:120]}...")
    print(f"\n{'─'*65}")


# ── PIPELINE COMPLET ─────────────────────────────────────────────────────────

def pipeline(query, model, collection, client, debug=False, expand=True):
    if expand:
        queries = expandre_query(client, query, debug=debug)
    else:
        queries = [query]

    chunks = multi_recherche(queries, model, collection,
                             top_k=TOP_K, top_k_final=TOP_K_FINAL, debug=debug)

    if debug:
        afficher_debug(query, chunks)

    contexte = construire_contexte(chunks)

    try:
        return interroger_claude(client, query, contexte)
    except Exception as e:
        return f"❌ Erreur API Claude: {e}"


# ── BOUCLE INTERACTIVE ────────────────────────────────────────────────────────

def boucle_interactive(model, collection, client, debug=False, expand=True):
    print(f"\n{'='*65}")
    print("  AMIIN — Assistant IA de Djibouti (v2)")
    print(f"  Base: {collection.count()} chunks | Modèle: {MODEL_CLAUDE}")
    print(f"  Expansion: {'ON' if expand else 'OFF'}")
    print(f"  Commandes: 'quit' | 'debug' | 'expand' | 'stats'")
    print(f"{'='*65}\n")

    while True:
        try:
            query = input("\n🇩🇯 Vous : ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n\nAu revoir ! 👋")
            break

        if not query:
            continue
        if query.lower() in ('quit', 'exit', 'q'):
            print("\nAu revoir ! 👋")
            break
        if query.lower() == 'debug':
            debug = not debug
            print(f"  [Debug {'ON' if debug else 'OFF'}]")
            continue
        if query.lower() == 'expand':
            expand = not expand
            print(f"  [Expansion {'ON' if expand else 'OFF'}]")
            continue
        if query.lower() == 'stats':
            data = collection.get(include=['metadatas'])
            from collections import Counter
            cats = Counter(m.get('category', '?') for m in data['metadatas'])
            print(f"\n  Total: {len(data['ids'])} chunks")
            for c, n in cats.most_common():
                print(f"    {c:<25} {n}")
            continue

        reponse = pipeline(query, model, collection, client,
                          debug=debug, expand=expand)
        print(f"\n🤖 Amiin : {reponse}")


# ── MAIN ──────────────────────────────────────────────────────────────────────

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Amiin — Assistant IA de Djibouti (v2)')
    parser.add_argument('--query', '-q', type=str, default=None)
    parser.add_argument('--debug', '-d', action='store_true')
    parser.add_argument('--no-expand', action='store_true',
                        help='Désactiver l\'expansion de query')
    parser.add_argument('--top-k', '-k', type=int, default=TOP_K)
    args = parser.parse_args()

    TOP_K = args.top_k
    expand = not args.no_expand

    model, collection = charger_composants()
    client = charger_claude()

    if args.query:
        reponse = pipeline(args.query, model, collection, client,
                          debug=args.debug, expand=expand)
        print(f"\n{reponse}")
    else:
        boucle_interactive(model, collection, client,
                          debug=args.debug, expand=expand)