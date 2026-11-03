import struct, os, sys, subprocess, json, collections
sys.path.insert(0, os.path.expanduser('~'))
from rdar import index, fnv
G = os.path.expanduser('~/mnt/Cyberpunk 2077')
paths = open(G + '/_navmesh_work/ponc/exterior.txt').read().split('\n')
arcs = []
for a in ['/archive/pc/ep1/ep1_1_nightcity.archive', '/archive/pc/content/basegame_3_nightcity.archive']:
    f, ents, segs = index(G + a); f.close(); arcs.append((G + a, ents, segs))
todo = collections.defaultdict(list)  # archive -> [(path, seg0, seg1)]
missing = 0
for p in paths:
    h = fnv(p)
    for ap, ents, segs in arcs:
        e = ents.get(h)
        if e:
            todo[ap].append((p, segs[e[1]], segs[e[1] + 1] if e[2] - e[1] > 1 else None)); break
    else: missing += 1
print('missing', missing, {k.split('/')[-1]: len(v) for k, v in todo.items()})
cands = []   # (archive, path, seg1)
words = collections.Counter()
os.makedirs(os.path.expanduser('~/work/s0'), exist_ok=True)
for ap, items in todo.items():
    for b in range(0, len(items), 400):
        batch = items[b:b + 400]
        man = os.path.expanduser('~/work/man.txt')
        with open(man, 'w') as m:
            for i, (p, s0, s1) in enumerate(batch):
                m.write('%d %d %d %s\n' % (s0[0], s0[1], s0[2], os.path.expanduser('~/work/s0/%d.bin' % i)))
        subprocess.run([os.path.expanduser('~/bulk'), ap, man], capture_output=True)
        for i, (p, s0, s1) in enumerate(batch):
            fn = os.path.expanduser('~/work/s0/%d.bin' % i)
            try: d = open(fn, 'rb').read()
            except: continue
            os.remove(fn)
            tabs = [struct.unpack_from('<III', d, 40 + 12 * k) for k in range(10)]
            so, sl, _ = tabs[0]
            strs = d[so:so + sl].split(b'\0')
            hit = [s for s in strs if s.endswith(b'.workspot')] if b'worldAISpotNode' in strs else []
            if hit:
                cands.append((ap, p, s1))
                for s in hit: words[s.decode('latin1')] += 1
    print(ap.split('/')[-1], 'done', len(cands), flush=True)
json.dump({'cands': cands, 'templates': words.most_common()}, open(os.path.expanduser('~/work/spots_cands.json'), 'w'))
print(len(cands), 'sectors with workspots;', len(words), 'workspots')

