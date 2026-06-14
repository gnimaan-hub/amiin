# titre_egouv.py - a lancer depuis ton PC
import requests
from bs4 import BeautifulSoup
import csv
import time

headers = {'User-Agent': 'AmiinBot/1.0'}
input_csv = 'amiin_links.csv'
output_csv = 'amiin_links_titres.csv'

with open(input_csv, 'r', encoding='utf-8-sig') as fin, \
     open(output_csv, 'w', newline='', encoding='utf-8-sig') as fout:
    
    reader = csv.DictReader(fin, delimiter=';')
    writer = csv.DictWriter(fout, fieldnames=reader.fieldnames, delimiter=';')
    writer.writeheader()
    
    for row in reader:
        if 'egouv.dj' not in row['url']:
            writer.writerow(row)
            continue
        try:
            r = requests.get(row['url'], timeout=8, headers=headers)
            r.encoding = 'utf-8'
            soup = BeautifulSoup(r.content, 'html.parser')
            for tag in soup(['nav','footer','script','style']):
                tag.decompose()
            title = ''
            for sel in ['h1','h2','h3','.title']:
                t = soup.find(sel)
                if t and len(t.get_text(strip=True)) > 5:
                    title = t.get_text(strip=True)[:100]
                    break
            if title:
                row['title'] = title
            writer.writerow(row)
            print(f"[OK] {title[:60]}")
            time.sleep(0.5)
        except Exception as e:
            writer.writerow(row)
            print(f"[ERR] {row['url'][-40:]}")

print("Termine -> amiin_links_titres.csv")