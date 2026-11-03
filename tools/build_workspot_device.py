"""Builds People of Night City's workspot device: an entity with nothing in it
but a workspot component named "workspot". The mod spawns one where one of our
people is to sit, lean, smoke..., sets the component's workspot resource to the
one the game uses at that spot (from data/spots.lua), and plays it on them.

Writes archive/pc/mod/PeopleOfNightCity.archive with
  people_of_night_city\\workspot_device.ent

Needs cr2w.py and rdar.py from cyberpunk-navmesh-framework/tools on the path.
  python build_workspot_device.py OUT_ARCHIVE
"""
import random
import struct
import sys

import cr2w
import rdar

PATH = "people_of_night_city\\workspot_device.ent"

# The compiled entity (an entity of class Device with one
# workWorkspotResourceComponent, name "workspot", empty transform and resource),
# as the game stores an entity template's compiledData. @CRUID@ is the
# component's id (twice: in the component list and in the component).
PACKAGE = (
    "040206000200000000000000680000004c0100005c01000000000200000000000000"
    "0000@CRUID@680000076f00001e8d0000059200000698000009a1000003a4000006aa"
    "00000fb900000fc8000009d100000edf000002e100000bec000005f1000006f700000"
    "2f9000002fb00000c0701000b12010002140100061a0100021c0100021e0100022001"
    "00113101001b44657669636500776f726b576f726b73706f745265736f7572636543"
    "6f6d706f6e656e74006e616d6500434e616d6500776f726b73706f74006964004352"
    "554944006c6f63616c5472616e73666f726d00576f726c645472616e73666f726d00"
    "506f736974696f6e00576f726c64506f736974696f6e0078004669786564506f696e"
    "74004269747300496e7433320079007a004f7269656e746174696f6e005175617465"
    "726e696f6e006900466c6f6174006a006b007200776f726b73706f745265736f7572"
    "63650072615265663a776f726b576f726b73706f745265736f757263650000000000"
    "5c010000010000005e0100000000040002000300220000000500060024000000070008"
    "002c00000018001900b40000000400@CRUID@020009000a00120000001100120056"
    "00000003000b000c001a0000000f000c002800000010000c003600000001000d000e00"
    "0a0000000000000001000d000e000a0000000000000001000d000e000a000000000000"
    "00040013001400220000001500140026000000160014002a000000170014002e000000"
    "0000000000000080000080bf00000080ffff"
)


def build():
    cruid = struct.pack("<Q", random.Random("people_of_night_city workspot").getrandbits(64)).hex()
    package = bytes.fromhex(PACKAGE.replace("@CRUID@", cruid))
    assert len(package) == 576, len(package)
    f = cr2w.File()
    for s in ("entEntityTemplate", "cookingPlatform", "ECookingPlatform", "PLATFORM_PC", "compiledData", "DataBuffer"):
        f.nid(s)
    t = cr2w.Obj("entEntityTemplate")
    t.props = [
        cr2w.Prop("cookingPlatform", "ECookingPlatform", cr2w.p_u16(f.nid("PLATFORM_PC"))),
        cr2w.Prop("compiledData", "DataBuffer", cr2w.p_u32(0x80000001)),
    ]
    f.exports.append(t)
    f.add_buffer(package, flags=0x3E0000)
    return f


def main(out):
    f = build()
    data, buffers = f.segments()
    rdar.write(out, [(PATH, data, buffers)])
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1])
