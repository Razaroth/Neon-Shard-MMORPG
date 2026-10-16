"""Fetch unmodified, OGA-BY-licensed LPC sprite layers at a pinned revision."""
import concurrent.futures
import csv
import hashlib
import io
import json
from pathlib import Path
import urllib.request

REVISION = '9bf06be193b053db256b2536824af426de046aa2'
BASE = f'https://raw.githubusercontent.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator/{REVISION}/'
ROOT = Path(__file__).resolve().parents[1] / 'assets/lpc'
PREFIXES = [
    'body/bodies/male', 'body/bodies/female',
    'head/heads/human/male', 'head/heads/human/female',
    'torso/clothes/longsleeve/longsleeves/male', 'torso/clothes/longsleeve/longsleeves/female',
    'torso/clothes/longsleeve/longsleeve/male', 'torso/clothes/longsleeve/longsleeve/female',
    'legs/pants/male', 'legs/pants/thin', 'feet/boots/basic/male', 'feet/boots/basic/thin',
    'hair/half_up/adult', 'hair/ponytail2/adult/fg', 'hair/ponytail2/adult/bg',
    'hair/halfmessy/adult', 'hat/cloth/hood/adult',
    'hair/high_ponytail/adult/fg', 'hair/high_ponytail/adult/bg',
]
CLIPS = ['walk', 'run', 'shoot', 'slash', 'spellcast']


def read(url):
    with urllib.request.urlopen(url, timeout=45) as response:
        return response.read()


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    rows = {row['filename']: row for row in csv.DictReader(io.StringIO(read(BASE + 'CREDITS.csv').decode()))}
    names = [f'{prefix}/{clip}.png' for prefix in PREFIXES for clip in CLIPS]
    for name in names:
        assert name in rows and 'OGA-BY' in rows[name]['licenses'], name

    known = {}
    if (ROOT / 'manifest.json').exists():
        previous = json.loads((ROOT / 'manifest.json').read_text())
        if previous.get('revision') == REVISION:
            known = {item['filename']: item['sha256'] for item in previous['assets']}

    def fetch(name):
        target = ROOT / name
        payload = target.read_bytes() if name in known and target.exists() else b''
        if not payload or hashlib.sha256(payload).hexdigest() != known.get(name):
            payload = read(BASE + 'spritesheets/' + name)
        assert payload.startswith(b'\x89PNG\r\n\x1a\n'), name
        target = ROOT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        return {**rows[name], 'selected_license': 'OGA-BY 3.0', 'sha256': hashlib.sha256(payload).hexdigest()}

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        assets = sorted(pool.map(fetch, names), key=lambda item: item['filename'])
    (ROOT / 'manifest.json').write_text(json.dumps({'revision': REVISION, 'source': BASE, 'assets': assets}, indent=2) + '\n')
    authors = sorted({name.strip() for item in assets for name in item['authors'].split(',') if name.strip()})
    credits = ['LIBERATED PIXEL CUP / CLASSIC MOVEMENT STUDY', '',
               'Artist-authored body, head, clothing, hair and boot animation layers.',
               'Source: https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator',
               f'Revision: {REVISION}', '',
               'Selected license for every bundled LPC layer: OGA-BY 3.0.',
               'License: https://static.opengameart.org/OGA-BY-3.0.txt',
               'Authors: ' + ', '.join(authors), '',
               'The upstream PNGs are unmodified. The game applies runtime color tints.',
               'These reference outfits are not finished Neon Shard cyberpunk character art.',
               'Other upstream license choices remain recorded in manifest.json.', '',
               'PER-ASSET ATTRIBUTION AND ORIGINAL SOURCES', '']
    for item in assets:
        credits += [item['filename'], 'Authors: ' + item['authors'].strip(),
                    'Sources: ' + item['urls'].strip(), 'Notes: ' + item['notes'].strip(), '']
    (ROOT / 'CREDITS.txt').write_text('\n'.join(credits) + '\n')
    print(f'LPC_ASSETS_OK {len(assets)} unmodified PNG layers, pinned source, SHA-256 manifest, attribution')


if __name__ == '__main__':
    main()
