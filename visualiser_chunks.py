# -*- coding: utf-8 -*-
"""
visualiser_chunks.py - Amiin Project
Genere un fichier HTML pour inspecter visuellement tous les chunks de la base.
Lance: python visualiser_chunks.py
Puis ouvre: chunks_viewer.html dans ton navigateur
"""

import sqlite3
import html
from collections import defaultdict, Counter

DB_PATH = './amiin_db/chroma.sqlite3'

conn = sqlite3.connect(DB_PATH)
cur = conn.cursor()

cur.execute("""
    SELECT 
        e.id,
        MAX(CASE WHEN em.key='url' THEN em.string_value END) as url,
        MAX(CASE WHEN em.key='category' THEN em.string_value END) as category,
        MAX(CASE WHEN em.key='title' THEN em.string_value END) as title,
        MAX(CASE WHEN em.key='chunk_index' THEN em.int_value END) as chunk_idx,
        MAX(CASE WHEN em.key='chroma:document' THEN em.string_value END) as content
    FROM embeddings e
    JOIN embedding_metadata em ON e.id = em.id
    GROUP BY e.id
    ORDER BY category, url, chunk_idx
""")
rows = cur.fetchall()
conn.close()

# Grouper par categorie
by_cat = defaultdict(list)
for r in rows:
    by_cat[r[2] or 'inconnu'].append(r)

cats = sorted(by_cat.keys())
total = len(rows)

# Couleurs par categorie
COLORS = {
    'etat_civil':       '#3B82F6',
    'transport':        '#F59E0B',
    'travail':          '#10B981',
    'economie_commerce':'#8B5CF6',
    'education':        '#EC4899',
    'energie_eau':      '#06B6D4',
    'urbanisme':        '#84CC16',
    'juridique':        '#EF4444',
    'numerique':        '#6366F1',
    'sante':            '#F97316',
    'immigration':      '#14B8A6',
    'culture':          '#A78BFA',
    'securite':         '#FB7185',
    'gouvernement':     '#64748B',
    'institution':      '#0EA5E9',
    'ministeres':       '#7C3AED',
    'geographie':       '#16A34A',
    'histoire':         '#92400E',
    'administrative':   '#475569',
    'presidence':       '#B45309',
    'general':          '#9CA3AF',
}

def get_color(cat):
    return COLORS.get(cat, '#6B7280')

def word_count(text):
    return len((text or '').split())

# Generer HTML
html_parts = []
html_parts.append("""<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<title>Amiin - Visualiseur de chunks</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0f172a; color: #e2e8f0; min-height: 100vh; }
  .header { background: #1e293b; padding: 20px 30px; border-bottom: 1px solid #334155;
            display: flex; align-items: center; gap: 20px; flex-wrap: wrap; }
  .header h1 { font-size: 22px; color: #f1f5f9; }
  .stat { background: #334155; padding: 6px 14px; border-radius: 20px;
          font-size: 13px; color: #94a3b8; }
  .stat span { color: #f1f5f9; font-weight: 600; }
  .controls { background: #1e293b; padding: 14px 30px; border-bottom: 1px solid #334155;
              display: flex; gap: 14px; flex-wrap: wrap; align-items: center; }
  .controls label { font-size: 13px; color: #94a3b8; }
  input[type=text] { background: #334155; border: 1px solid #475569; color: #f1f5f9;
                     padding: 7px 12px; border-radius: 8px; font-size: 14px; width: 260px; }
  input[type=text]:focus { outline: none; border-color: #60a5fa; }
  .sort-group { display: flex; align-items: center; gap: 6px; border-left: 1px solid #334155; padding-left: 14px; }
  .sort-btn { background: #334155; border: 1px solid #475569; color: #94a3b8;
              padding: 6px 12px; border-radius: 8px; font-size: 12px; cursor: pointer; transition: all .15s; }
  .sort-btn:hover { border-color: #60a5fa; color: #f1f5f9; }
  .sort-btn.active { background: #1d4ed8; border-color: #3b82f6; color: #fff; }
  .cat-nav { background: #1e293b; padding: 12px 30px; border-bottom: 1px solid #334155;
             display: flex; gap: 8px; flex-wrap: wrap; }
  .cat-btn { padding: 5px 14px; border-radius: 20px; font-size: 12px; font-weight: 600;
             cursor: pointer; border: none; color: white; opacity: 0.7; transition: opacity .2s; }
  .cat-btn:hover, .cat-btn.active { opacity: 1; }
  .main { padding: 20px 30px; }
  .cat-section { margin-bottom: 30px; }
  .cat-header { display: flex; align-items: center; gap: 10px; margin-bottom: 12px;
                padding: 10px 16px; border-radius: 10px; cursor: pointer; }
  .cat-header h2 { font-size: 15px; font-weight: 700; color: white; flex: 1; }
  .cat-count { font-size: 12px; background: rgba(255,255,255,0.2);
               padding: 2px 10px; border-radius: 10px; color: white; }
  .chunks-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));
                 gap: 12px; }
  .chunk-card { background: #1e293b; border: 1px solid #334155; border-radius: 10px;
                padding: 14px; border-left: 4px solid var(--cat-color); }
  .chunk-meta { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 8px; align-items: center; }
  .chunk-id { font-size: 11px; color: #64748b; }
  .chunk-wc { font-size: 11px; background: #334155; padding: 2px 8px;
              border-radius: 10px; color: #94a3b8; }
  .chunk-warn { font-size: 11px; background: #7c2d12; color: #fca5a5;
                padding: 2px 8px; border-radius: 10px; }
  .chunk-title { font-size: 13px; font-weight: 600; color: #f1f5f9;
                 margin-bottom: 6px; white-space: nowrap; overflow: hidden;
                 text-overflow: ellipsis; }
  .chunk-url { font-size: 11px; color: #64748b; margin-bottom: 8px;
               white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .chunk-url a { color: #60a5fa; text-decoration: none; }
  .chunk-content { font-size: 12px; color: #94a3b8; line-height: 1.6;
                   max-height: 120px; overflow: hidden; position: relative; }
  .chunk-content::after { content: ''; position: absolute; bottom: 0; left: 0; right: 0;
                          height: 30px; background: linear-gradient(transparent, #1e293b); }
  .chunk-card.expanded .chunk-content { max-height: none; }
  .chunk-card.expanded .chunk-content::after { display: none; }
  .expand-btn { margin-top: 6px; font-size: 11px; color: #60a5fa; cursor: pointer;
                background: none; border: none; padding: 0; }
  .hidden { display: none !important; }
  .noise-flag { background: #450a0a; border-color: #dc2626 !important; }
</style>
</head>
<body>
<div class="header">
  <h1>Amiin - Visualiseur de chunks</h1>
""")

html_parts.append(f'  <div class="stat">Total: <span>{total}</span> chunks</div>')
html_parts.append(f'  <div class="stat">Categories: <span>{len(cats)}</span></div>')

# Detecter le bruit (chunks avec "Alabama" ou menu repetitif)
noise_count = sum(1 for r in rows if 'A l a b a m a' in (r[5] or '') or
                  'TOUS LES SERVICES' in (r[5] or ''))
html_parts.append(f'  <div class="stat">Bruit detecte: <span style="color:#fca5a5">{noise_count}</span> chunks</div>')

html_parts.append("""</div>
<div class="controls">
  <label>Recherche:</label>
  <input type="text" id="search" placeholder="Chercher dans les titres et contenus..." oninput="filterChunks()">
  <div class="sort-group">
    <label>Trier par mots:</label>
    <button class="sort-btn" id="btn-default" onclick="sortChunks('default')">Par defaut</button>
    <button class="sort-btn" id="btn-asc" onclick="sortChunks('asc')">Croissant</button>
    <button class="sort-btn active" id="btn-none" onclick="sortChunks('none')">Non trie</button>
    <button class="sort-btn" id="btn-desc" onclick="sortChunks('desc')">Decroissant</button>
  </div>
</div>
<div class="cat-nav">
  <button class="cat-btn active" style="background:#475569" onclick="showAll()">Tout afficher</button>
""")

for cat in cats:
    color = get_color(cat)
    n = len(by_cat[cat])
    html_parts.append(f'  <button class="cat-btn" style="background:{color}" onclick="filterCat(\'{cat}\')">{cat} ({n})</button>')

html_parts.append("</div>\n<div class='main' id='main'>")

for cat in cats:
    color = get_color(cat)
    chunks = by_cat[cat]
    html_parts.append(f"""
<div class="cat-section" data-cat="{cat}" id="cat-{cat}">
  <div class="cat-header" style="background:{color}22; border: 1px solid {color}44">
    <h2 style="color:{color}">{cat.upper()}</h2>
    <span class="cat-count" style="background:{color}44; color:{color}">{len(chunks)} chunks</span>
  </div>
  <div class="chunks-grid">""")

    for r in chunks:
        eid, url, category, title, chunk_idx, content = r
        wc = word_count(content)
        is_noise = 'A l a b a m a' in (content or '') or 'TOUS LES SERVICES' in (content or '')
        noise_class = 'noise-flag' if is_noise else ''
        warn_badge = '<span class="chunk-warn">BRUIT</span>' if is_noise else ''
        short_url = (url or '')[:70]
        safe_content = html.escape(content or '')
        safe_title = html.escape(title or 'Sans titre')
        safe_url = html.escape(url or '')

        html_parts.append(f"""
    <div class="chunk-card {noise_class}" style="--cat-color:{color}" data-cat="{cat}"
         data-wc="{wc}"
         data-text="{html.escape((title or '') + ' ' + (content or '')[:200]).lower()}">
      <div class="chunk-meta">
        <span class="chunk-id">#{eid} chunk[{chunk_idx}]</span>
        <span class="chunk-wc">{wc} mots</span>
        {warn_badge}
      </div>
      <div class="chunk-title">{safe_title}</div>
      <div class="chunk-url"><a href="{safe_url}" target="_blank">{html.escape(short_url)}</a></div>
      <div class="chunk-content">{safe_content}</div>
      <button class="expand-btn" onclick="this.parentElement.classList.toggle('expanded');
              this.textContent=this.parentElement.classList.contains('expanded')?'Reduire':'Voir tout'">Voir tout</button>
    </div>""")

    html_parts.append("  </div>\n</div>")

html_parts.append("""</div>
<script>
let currentSort = 'none';
let currentCat = 'all';

function filterCat(cat) {
  currentCat = cat;
  document.querySelectorAll('.cat-section').forEach(s => {
    s.classList.toggle('hidden', s.dataset.cat !== cat);
  });
  document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
  event.target.classList.add('active');
}

function showAll() {
  currentCat = 'all';
  document.querySelectorAll('.cat-section').forEach(s => s.classList.remove('hidden'));
  document.querySelectorAll('.cat-btn').forEach(b => b.classList.remove('active'));
  event.target.classList.add('active');
}

function filterChunks() {
  const q = document.getElementById('search').value.toLowerCase();
  document.querySelectorAll('.chunk-card').forEach(card => {
    card.classList.toggle('hidden', q.length > 2 && !card.dataset.text.includes(q));
  });
  document.querySelectorAll('.cat-section').forEach(section => {
    const visible = [...section.querySelectorAll('.chunk-card')].some(c => !c.classList.contains('hidden'));
    section.classList.toggle('hidden', !visible && currentCat !== 'all');
  });
}

function sortChunks(mode) {
  currentSort = mode;
  document.querySelectorAll('.sort-btn').forEach(b => b.classList.remove('active'));
  document.getElementById('btn-' + mode).classList.add('active');

  document.querySelectorAll('.chunks-grid').forEach(grid => {
    const cards = [...grid.querySelectorAll('.chunk-card')];
    if (mode === 'none' || mode === 'default') {
      // Retirer tout ordre custom, laisser le DOM tel quel
      cards.forEach(c => c.style.order = '');
      return;
    }
    // Trier par data-wc
    const sorted = [...cards].sort((a, b) => {
      const wa = parseInt(a.dataset.wc) || 0;
      const wb = parseInt(b.dataset.wc) || 0;
      return mode === 'asc' ? wa - wb : wb - wa;
    });
    sorted.forEach((card, i) => card.style.order = i);
  });

  // Feedback visuel: badge de tri sur chaque section visible
  document.querySelectorAll('.cat-section:not(.hidden) .cat-header').forEach(h => {
    let badge = h.querySelector('.sort-badge');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'sort-badge';
      badge.style.cssText = 'font-size:11px;background:rgba(255,255,255,.15);padding:2px 8px;border-radius:10px;color:white;';
      h.appendChild(badge);
    }
    if (mode === 'none' || mode === 'default') {
      badge.remove();
    } else {
      badge.textContent = mode === 'asc' ? 'mots croissant' : 'mots decroissant';
    }
  });
}
</script>
</body>
</html>""")

output = '\n'.join(html_parts)
with open('chunks_viewer.html', 'w', encoding='utf-8') as f:
    f.write(output)

print(f"[OK] Fichier genere: chunks_viewer.html")
print(f"     {total} chunks, {len(cats)} categories")
print(f"     Chunks avec bruit detecte: {noise_count}")
print(f"     Ouvre chunks_viewer.html dans ton navigateur")