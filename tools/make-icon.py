#!/usr/bin/env python3
"""Packs the PNGs that `love tools/icon` renders (the title screen's cylinder) into tools/icon/gunnug.ico."""
import os
import struct

SIZES = [256, 128, 64, 48, 32, 24, 16]
SRC = os.path.join(os.environ["APPDATA"], "LOVE", "gunnug-icon")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon", "gunnug.ico")

pngs = [open(os.path.join(SRC, "icon%d.png" % s), "rb").read() for s in SIZES]
head = struct.pack("<HHH", 0, 1, len(SIZES))
offset = 6 + 16 * len(SIZES)
entries = b""
for s, p in zip(SIZES, pngs):
    entries += struct.pack("<BBBBHHII", s % 256, s % 256, 0, 0, 1, 32, len(p), offset)
    offset += len(p)
with open(OUT, "wb") as f:
    f.write(head + entries + b"".join(pngs))
print(OUT, offset, "bytes")
