"""Extracts the AI spots (where the game's own NPCs sit, lean, smoke, use things,
and homeless people sleep rough) from Night City's exterior streaming sectors:
each worldAISpotNode's position, rotation, workspot resource and markings.

Run scan3.py first (finds the sectors with AI spots: work/spots_cands.json), then
this in slices (python extract_spots.py START STOP), then merge the
work/spots_*.json files and classify them into data/spots.lua (see README).
Needs cr2w.py, rdar.py (cyberpunk-navmesh-framework/tools) and `bulk`.
"""
import json, os, struct, subprocess, sys, math
sys.path.insert(0, os.path.expanduser('~'))
import cr2w
from rdar import index, fnv
G = os.path.expanduser('~/mnt/Cyberpunk 2077')
ap_path = G + '/archive/pc/ep1/ep1_1_nightcity.archive'
f, ents, segs = index(ap_path); f.close()
cands = [c[1] for c in json.load(open('work/spots_cands.json'))['cands']]
start, stop = int(sys.argv[1]), int(sys.argv[2])
out = []
work = os.path.abspath('work/sx%d' % start); os.makedirs(work, exist_ok=True)
paths = cands[start:stop]
for b in range(0, len(paths), 200):
    batch = paths[b:b + 200]
    with open(work + '/man.txt', 'w') as m:
        for i, p in enumerate(batch):
            e = ents[fnv(p)]
            for k in range(e[1], min(e[2], e[1] + 3)):
                s = segs[k]; m.write('%d %d %d %s\n' % (s[0], s[1], s[2], work + '/%d_%d.bin' % (i, k - e[1])))
    subprocess.run(['./bulk', ap_path, work + '/man.txt'], capture_output=True)
    for i, p in enumerate(batch):
        files = [work + '/%d_%d.bin' % (i, k) for k in range(3)]
        try:
            data = open(files[0], 'rb').read()
            bufs = [open(fn, 'rb').read() if os.path.exists(fn) else b'' for fn in files[1:]]
            nbuf = struct.unpack_from('<III', data, 40 + 12 * 5)[1]
            f2 = cr2w.File.read(data, (bufs + [b''] * nbuf)[:nbuf])
            names = f2.names if hasattr(f2, 'names') else None
            ap = f2.exports[0].appendix
            ref = cr2w.u32(ap[8:12]) & 0x7FFFFFFF
            n, q = cr2w.vlq(ap, 12)
            handles = [cr2w.i32(ap[q + 4 * j:q + 4 * j + 4]) for j in range(n)]
            nd = bufs[ref - 1] if ref - 1 < 2 else b''
            for r in range(len(nd) // 144):
                rec = nd[144 * r:144 * r + 144]
                idx = struct.unpack_from('<Q', rec, 112)[0] & 0x7FFFF
                if idx >= len(handles): continue
                o = f2.exports[handles[idx] - 1]
                if o.cls != 'worldAISpotNode': continue
                sp = o.get('spot')
                if sp is None: continue
                so = f2.exports[cr2w.i32(sp.raw) - 1]
                res = so.get('resource')
                if res is None: continue
                ii = cr2w.u16(res.raw)
                if ii == 0 or ii > len(f2.imports): continue
                ws = f2.imports[ii - 1][0]
                x, y, z = struct.unpack_from('<3f', rec, 0)
                qi, qj, qk, qr = struct.unpack_from('<4f', rec, 16)
                yaw = math.degrees(math.atan2(2 * (qr * qk + qi * qj), 1 - 2 * (qj * qj + qk * qk)))
                mk = []
                m_ = o.get('markings')
                if m_ is not None and names is not None:
                    cnt = cr2w.u32(m_.raw[:4])
                    for t in range(cnt):
                        ni = cr2w.u16(m_.raw[4 + 2 * t:6 + 2 * t])
                        if 0 <= ni < len(names): mk.append(names[ni])
                out.append([round(x, 2), round(y, 2), round(z, 2), round(yaw, 1), ws, mk])
        except Exception as ex:
            pass
        finally:
            for fn in files:
                if os.path.exists(fn): os.remove(fn)
json.dump(out, open('work/spots_%d.json' % start, 'w'))
print(start, stop, len(out))
