"""Extracts where cars can drive: the polygons of the vehicle navmesh in the
navigation streaming sectors (navlist.txt), as their centres. Run in slices
(python extract_roads.py START STOP), then merge the work/roads_*.json files,
thin them to one point per 20 m (and 12 m of height) and write data/roads.lua.
Game x, y, z = navmesh x, z, y. Needs cr2w.py, rdar.py and `bulk`.
"""
import os, sys, struct, subprocess, json
sys.path.insert(0, os.path.expanduser('~'))
import cr2w
from rdar import index, fnv
G = os.path.expanduser('~/mnt/Cyberpunk 2077')
A = G + '/archive/pc/ep1/ep1_1_nightcity.archive'
f, ents, segs = index(A); f.close()
paths = [p for p in open(G + '/_navmesh_work/navlist.txt').read().split('\n') if p]
start, stop = int(sys.argv[1]), int(sys.argv[2])
work = os.path.abspath('work/rd%d' % start); os.makedirs(work, exist_ok=True)

def tile_points(b):
    h = struct.unpack_from('<4s14I', b, 0)
    if h[0] != b'VAND': return []
    npoly, nvert = h[6], h[7]
    p = 100
    verts = [struct.unpack_from('<3f', b, p + 12 * i) for i in range(nvert)]
    p += 12 * nvert
    out = []
    for i in range(npoly):
        v = struct.unpack_from('<3H', b, p + 4)
        flags, vc, at = struct.unpack_from('<HBB', b, p + 16)
        p += 20
        if at >> 6 != 0 or vc < 3: continue   # ground polys only
        a, bb, c = verts[v[0]], verts[v[1]], verts[v[2]]
        out.append(((a[0] + bb[0] + c[0]) / 3, (a[1] + bb[1] + c[1]) / 3, (a[2] + bb[2] + c[2]) / 3, at & 0x3F))
    return out

pts = {'Vehicle': [], 'Human': []}
items = [p for p in paths[start:stop] if fnv(p) in ents]
for b0 in range(0, len(items), 50):
    batch = items[b0:b0 + 50]
    with open(work + '/man.txt', 'w') as m:
        for i, p in enumerate(batch):
            e = ents[fnv(p)]
            for k in range(e[1], e[2]):
                s = segs[k]; m.write('%d %d %d %s\n' % (s[0], s[1], s[2], work + '/%d_%d.bin' % (i, k - e[1])))
    subprocess.run(['./bulk', A, work + '/man.txt'], capture_output=True)
    for i, p in enumerate(batch):
        e = ents[fnv(p)]
        files = [work + '/%d_%d.bin' % (i, k) for k in range(e[2] - e[1])]
        try:
            data = open(files[0], 'rb').read()
            bufs = [open(fn, 'rb').read() for fn in files[1:]]
            nbuf = struct.unpack_from('<III', data, 40 + 12 * 5)[1]
            f2 = cr2w.File.read(data, (bufs + [b''] * nbuf)[:nbuf])
            for o in f2.exports:
                if o.cls != 'worldNavigationTileResource': continue
                ag = o.get('agentSize')
                agent = f2.names[cr2w.u16(ag.raw)] if ag is not None else 'Human'
                tb = o.get('tileBuffers')
                if tb is None or agent not in pts: continue
                n = cr2w.u32(tb.raw[:4])
                for j in range(n):
                    ref = cr2w.u32(tb.raw[4 + 4 * j:8 + 4 * j]) & 0x7FFFFFFF
                    if 0 < ref <= len(bufs):
                        pts[agent] += tile_points(bufs[ref - 1])
        except Exception as ex:
            print('err', p, ex)
        finally:
            for fn in files:
                if os.path.exists(fn): os.remove(fn)
json.dump({k: [[round(a, 1), round(b, 1), round(c, 1), d] for a, b, c, d in v] for k, v in pts.items()}, open('work/roads_%d.json' % start, 'w'))
print(start, stop, len(pts['Vehicle']), len(pts['Human']))
