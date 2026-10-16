"""Measure source sprite anchors and record provenance; never changes PNG pixels.
Requires Pillow, NumPy and SciPy for read-only image inspection. Bundled metadata needs no Python at runtime.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image
import numpy as np
from scipy import ndimage
from scipy.spatial import ConvexHull

ROOT = Path(__file__).resolve().parents[1]
COUNTS = {'walk': 9, 'run': 8, 'attack': 6}


def register(sources):
    result = {'license': 'OGA-BY 3.0', 'credits': '../lpc/CREDITS.txt',
              'notes': 'Generated cyberpunk redraws using original class designs and credited LPC pose references. PNG outputs are unmodified.',
              'classes': {}}
    for role in ['vanguard', 'cipher', 'ronin', 'ghost', 'machinist']:
        clips = {}
        for clip, columns in COUNTS.items():
            path = ROOT / 'assets/rpg' / role / (clip + '.png')
            with Image.open(path) as image:
                width, height = image.size
                alpha = image.getchannel('A').point(lambda value: 255 if value >= 230 else 0)
                blank = []
                start = None
                for y in range(height):
                    count = alpha.crop((0, y, width, y + 1)).histogram()[255]
                    if count <= 2 and start is None:
                        start = y
                    elif count > 2 and start is not None:
                        if y - start >= 2:
                            blank.append((start, y))
                        start = None
                cuts = [0]
                for boundary in range(1, 4):
                    expected = height * boundary / 4
                    candidates = [gap for gap in blank if abs(sum(gap) / 2 - expected) < height * .12]
                    if not candidates:
                        raise ValueError(f'No safe row separator: {role}/{clip}/{boundary}')
                    gap = min(candidates, key=lambda item: abs(sum(item) / 2 - expected))
                    cuts.append(round(sum(gap) / 2))
                cuts.append(height)
                rows = []
                frames = []
                for view in range(4):
                    # Only the ready/contact frame defines a stable anchor for a whole row.
                    # Ignore soft glow. All subsequent poses keep this anchor, preserving bob.
                    cell = image.getchannel('A').crop((0, cuts[view], round(width / columns), cuts[view + 1]))
                    solid = cell.point(lambda alpha: 255 if alpha >= 230 else 0)
                    box = solid.getbbox()
                    if box is None:
                        raise ValueError(f'Empty registration frame: {role}/{clip}/{view}')
                    top, bottom = box[1], box[3]
                    feet_top = max(top, bottom - max(2, round((bottom - top) * .12)))
                    feet_box = solid.crop((0, feet_top, solid.width, bottom)).getbbox()
                    foot_x = (feet_box[0] + feet_box[2]) / 2
                    rows.append({'height': bottom - top, 'foot': [foot_x, bottom]})
                    pixels = np.asarray(alpha)[cuts[view]:cuts[view + 1]] > 0
                    labels, count = ndimage.label(pixels)
                    sizes = np.bincount(labels.ravel())
                    main_ids = (np.argsort(sizes[1:])[-columns:] + 1).tolist()
                    centers = {label: np.argwhere(labels == label).mean(axis=0)[::-1] for label in main_ids}
                    main_ids.sort(key=lambda label: centers[label][0])
                    parts = {label: [] for label in main_ids}
                    for label in range(1, count + 1):
                        if sizes[label] < 32:
                            continue
                        points = np.argwhere(labels == label)[:, ::-1]
                        center = points.mean(axis=0)
                        owner = label if label in main_ids else min(main_ids, key=lambda candidate: np.linalg.norm(center - centers[candidate]))
                        hull = points[ConvexHull(points).vertices]
                        # Keep antialiased outline pixels around the opaque body without
                        # including disconnected pieces of a neighboring sprite.
                        expanded = np.concatenate([hull + offset for offset in [(-2,-2),(-2,2),(2,-2),(2,2)]])
                        expanded[:, 0] = np.clip(expanded[:, 0], 0, width - 1)
                        expanded[:, 1] = np.clip(expanded[:, 1], 0, cuts[view + 1] - cuts[view] - 1)
                        hull = expanded[ConvexHull(expanded).vertices]
                        hull[:, 1] += cuts[view]
                        parts[owner].append(hull.tolist())
                    poses = []
                    for frame, label in enumerate(main_ids):
                        expected = width * (frame + .5) / columns
                        if abs(centers[label][0] - expected) > width / columns * .4:
                            raise ValueError(f"Body assignment does not match frame grid: {role}/{clip}/{view}/{frame}")
                        points = np.concatenate([np.array(poly) for poly in parts[label]])
                        left, upper = points.min(axis=0).tolist()
                        right, lower = points.max(axis=0).tolist()
                        poses.append({'rect': [left, upper, right - left + 1, lower - upper + 1],
                                      'foot': [foot_x + width * frame / columns, cuts[view] + bottom],
                                      'polygons': parts[label]})
                    frames.append(poses)
            clips[clip] = {'columns': columns, 'rows': 4, 'size': [width, height],
                           'row_regions': [[cuts[i], cuts[i + 1] - cuts[i]] for i in range(4)],
                           'registration': rows, 'frames': frames, 'source_output': sources[role + '/' + clip],
                           'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
        walk_cell_width = clips['walk']['size'][0] / COUNTS['walk']
        for clip, data in clips.items():
            cell_width = data['size'][0] / COUNTS[clip]
            for view, anchor in enumerate(data['registration']):
                # A crouched run must not be magnified back to standing height.
                anchor['scale_height'] = (clips['walk']['registration'][view]['height'] * cell_width / walk_cell_width
                                          if clip == 'run' else anchor['height'])
        result['classes'][role] = clips
    (ROOT / 'assets/rpg/manifest.json').write_text(json.dumps(result, indent=2) + '\n')
    print('RPG_REGISTRATION_OK 15 unchanged sheets, 60 stable row anchors, 460 isolated poses, checksums')


if __name__ == '__main__':
    import sys
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'assets/rpg/sources.json'
    register(json.loads(source_path.read_text()))
