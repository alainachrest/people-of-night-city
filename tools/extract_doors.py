"""Extracts the outside doors of Night City's buildings from the game's archive.

Reads every exterior streaming sector listed in exterior.txt (from
base\\worlds\\03_night_city\\_compiled\\default\\blocks\\all.streamingblock), keeps
the ones that use a door template, and writes each door node's position and
rotation (from the sector's node data) to doors.json:
  [x, y, z, qi, qj, qk, qr, template, kind, nodeClass]

Needs: rdar.py-style archive index reading (fnv path hashes), cr2w.py from
cyberpunk-navmesh-framework/tools, and `bulk` (Kraken segment decompressor,
cyberpunk-navmesh-framework/tools/kark) on the PATH or next to this script.

  python extract_doors.py GAME_DIR exterior.txt doors.json
"""
import json
import os
import struct
import subprocess
import sys

import cr2w

KEEP = {
    "single_door_decorative": "decorative", "double_door_decorative": "decorative",
    "single_door": "door", "double_door": "door", "single_door_techie": "door", "single_door_hinged": "door",
    "double_door_hinged": "door", "single_door_static": "decorative", "double_door_static": "decorative",
    "single_door_techie_static": "decorative", "glass_door_k": "door", "glass_single_door": "door",
    "double_door_sliding_a": "door", "double_door_sliding_g": "door", "double_door_glass_k_v3": "door",
    "tech_hinged_door": "door", "single_sliding_door_1_eng": "door", "single_door_1_baremetal_eng": "door",
    "double_door_freight_e": "freight",
}
for w in ["w150", "w250", "w600_h400", "w300_h250", "w900_h600", "w550", "w300", "w150_h250", "w200", "w650_h250"]:
    KEEP["shutter_window_" + w] = "shutter"
    KEEP["mall_shutter_" + w] = "shutter"


def fnv(s):
    h = 0xCBF29CE484222325
    for b in s.lower().replace("/", "\\").encode():
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def index(path):
    f = open(path, "rb")
    _magic, _ver, ipos, _isize = struct.unpack("<IIQI", f.read(20))
    f.seek(ipos)
    _fto, _fts, _crc, nf, ns, _nd = struct.unpack("<IIQIII", f.read(28))
    ents = {}
    for _ in range(nf):
        h, _ts, ninl, ss, se, _ds, _de = struct.unpack("<QqIIIII", f.read(36))
        f.read(20)
        ents[h] = (ninl, ss, se)
    segs = [struct.unpack("<QII", f.read(16)) for _ in range(ns)]
    return ents, segs


def main(game, listfile, out):
    archive = os.path.join(game, "archive", "pc", "ep1", "ep1_1_nightcity.archive")
    ents, segs = index(archive)
    paths = [p for p in open(listfile).read().split("\n") if p]
    work = os.path.abspath("extract_work")
    os.makedirs(work, exist_ok=True)
    bulk = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bulk")
    doors = []
    for b in range(0, len(paths), 200):
        batch = [p for p in paths[b:b + 200] if fnv(p) in ents]
        with open(os.path.join(work, "man.txt"), "w") as m:
            for i, p in enumerate(batch):
                e = ents[fnv(p)]
                for k in range(e[1], min(e[2], e[1] + 3)):  # the CR2W part and the first buffers
                    s = segs[k]
                    m.write("%d %d %d %s\n" % (s[0], s[1], s[2], os.path.join(work, "%d_%d.bin" % (i, k - e[1]))))
        subprocess.run([bulk, archive, os.path.join(work, "man.txt")], capture_output=True)
        for i, p in enumerate(batch):
            files = [os.path.join(work, "%d_%d.bin" % (i, k)) for k in range(3)]
            try:
                data = open(files[0], "rb").read()
                strs = data[struct.unpack_from("<I", data, 40)[0]:]
                if b"door" not in strs and b"shutter" not in strs:
                    continue
                bufs = [open(fn, "rb").read() if os.path.exists(fn) else b"" for fn in files[1:]]
                nbuf = struct.unpack_from("<III", data, 40 + 12 * 5)[1]
                f2 = cr2w.File.read(data, (bufs + [b""] * nbuf)[:nbuf])
                ap = f2.exports[0].appendix
                ref = cr2w.u32(ap[8:12]) & 0x7FFFFFFF
                n, q = cr2w.vlq(ap, 12)
                handles = [cr2w.i32(ap[q + 4 * j:q + 4 * j + 4]) for j in range(n)]
                nd = bufs[ref - 1] if ref - 1 < 2 else b""
                for r in range(len(nd) // 144):
                    rec = nd[144 * r:144 * r + 144]
                    idx = struct.unpack_from("<Q", rec, 112)[0] & 0x7FFFF
                    if idx >= len(handles):
                        continue
                    o = f2.exports[handles[idx] - 1]
                    et = o.get("entityTemplate")
                    if et is None:
                        continue
                    ii = cr2w.u16(et.raw)
                    if ii == 0 or ii > len(f2.imports):
                        continue
                    name = f2.imports[ii - 1][0].split("\\")[-1][:-4]
                    kind = KEEP.get(name)
                    if not kind:
                        continue
                    x, y, z = struct.unpack_from("<3f", rec, 0)
                    qi, qj, qk, qr = struct.unpack_from("<4f", rec, 16)
                    doors.append([round(x, 2), round(y, 2), round(z, 2), round(qi, 4), round(qj, 4),
                                  round(qk, 4), round(qr, 4), name, kind, o.cls])
            except (OSError, ValueError, IndexError, struct.error):
                pass
            finally:
                for fn in files:
                    if os.path.exists(fn):
                        os.remove(fn)
    json.dump(doors, open(out, "w"))
    print(len(doors), "doors")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
