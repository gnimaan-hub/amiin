import chromadb
from sentence_transformers import SentenceTransformer
from scraper_enrichissement import scraper_wikipedia
model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
client = chromadb.PersistentClient(path='./amiin_db')
col = client.get_or_create_collection('djibouti_knowledge')
print(f"Base avant: {col.count()}")
# 1. Supprimer tout ce qui commence par wiki_
data = col.get()
wiki_ids = [id_ for id_ in data['ids'] if id_.startswith('wiki_')]
print(f"Anciens wiki_ trouves: {len(wiki_ids)}")
if wiki_ids:
    for k in range(0, len(wiki_ids), 500):
        col.delete(ids=wiki_ids[k:k+500])
    print(f"Supprimes: {len(wiki_ids)}")
print(f"Base apres suppression: {col.count()}")
# 2. Scraper et ingerer
chunks = scraper_wikipedia()
print(f"Chunks a ingerer: {len(chunks)}")
for k, chunk in enumerate(chunks):
    emb = model.encode(chunk['document']).tolist()
    col.add(ids=[chunk['id']], embeddings=[emb], documents=[chunk['document']], metadatas=[chunk['metadata']])
    if (k+1) % 50 == 0:
        print(f"  {k+1}/{len(chunks)}...")
print(f"Base finale: {col.count()}")
# 3. Verification
data2 = col.get(where={'source': 'Wikipedia FR'})
print(f"Chunks Wikipedia FR: {len(data2['ids'])}")
