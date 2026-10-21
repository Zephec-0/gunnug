#!/usr/bin/env python3
"""Builds a Windows release of the game without any extra tools.

  python tools/build-windows.py [path to the LÖVE install]

Makes, in ./builds:
  Gunnug.love                  the game package (a zip of ./game)
  windows/Gunnug/              Gunnug.exe (love.exe with the game attached) and
                               the LÖVE DLLs and licence it needs
  Gunnug-windows.zip           that folder, zipped: the file to share

The product name comes from game/product.env. The LÖVE install defaults to
C:\\Program Files\\LOVE and must be version 11.5 (see LOVE_VERSION in product.env).
"""
import os
import shutil
import struct
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILDS = os.path.join(ROOT, "builds")
LOVE = sys.argv[1] if len(sys.argv) > 1 else r"C:\Program Files\LOVE"
DLLS = ["love.dll", "SDL2.dll", "OpenAL32.dll", "lua51.dll", "mpg123.dll", "msvcp120.dll", "msvcr120.dll"]
SKIP_NAMES = {".gitkeep", "log.txt"}


def product_name():
    with open(os.path.join(GAME, "product.env"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("PRODUCT_NAME="):
                return line.split("=", 1)[1].strip().strip('"').replace(" ", "-")
    raise SystemExit("PRODUCT_NAME not found in game/product.env")


def build_love(path):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for folder, _, files in os.walk(GAME):
            for name in sorted(files):
                if name in SKIP_NAMES:
                    continue
                full = os.path.join(folder, name)
                z.write(full, os.path.relpath(full, GAME).replace(os.sep, "/"))


def set_icon(exe, ico_path):
    """Puts the .ico in the exe's resources (Windows only; this rewrites the file, so it is done before the game is attached)."""
    import ctypes
    from ctypes import wintypes

    k32 = ctypes.windll.kernel32
    k32.BeginUpdateResourceW.restype = wintypes.HANDLE
    k32.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    k32.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    k32.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    data = open(ico_path, "rb").read()
    count = struct.unpack_from("<H", data, 4)[0]
    h = k32.BeginUpdateResourceW(exe, False)
    if not h:
        raise SystemExit("Could not open %s to set its icon" % exe)
    group = struct.pack("<HHH", 0, 1, count)
    for i in range(count):
        w, ht, cc, res, planes, bits, size, off = struct.unpack_from("<BBBBHHII", data, 6 + 16 * i)
        image = data[off:off + size]
        buf = ctypes.create_string_buffer(image, len(image))
        k32.UpdateResourceW(h, 3, i + 1, 0, buf, len(image))  # RT_ICON
        group += struct.pack("<BBBBHHIH", w, ht, cc, res, planes, bits, size, i + 1)
    buf = ctypes.create_string_buffer(group, len(group))
    k32.UpdateResourceW(h, 14, 1, 0, buf, len(group))  # RT_GROUP_ICON
    if not k32.EndUpdateResourceW(h, False):
        raise SystemExit("Could not write the icon into %s" % exe)


def main():
    name = product_name()
    for needed in ["love.exe"] + DLLS + ["license.txt"]:
        if not os.path.exists(os.path.join(LOVE, needed)):
            raise SystemExit("Not found in the LÖVE install (%s): %s" % (LOVE, needed))
    os.makedirs(BUILDS, exist_ok=True)
    love_file = os.path.join(BUILDS, name + ".love")
    build_love(love_file)

    out = os.path.join(BUILDS, "windows", name)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    # A fused executable: love.exe (with the game's icon) and the game package attached to its end
    exe_path = os.path.join(out, name + ".exe")
    shutil.copy(os.path.join(LOVE, "love.exe"), exe_path)
    ico = os.path.join(ROOT, "tools", "icon", "gunnug.ico")
    if os.path.exists(ico) and os.name == "nt":
        set_icon(exe_path, ico)
    with open(exe_path, "ab") as exe:
        with open(love_file, "rb") as f:
            shutil.copyfileobj(f, exe)
    for dll in DLLS:
        shutil.copy(os.path.join(LOVE, dll), out)
    shutil.copy(os.path.join(LOVE, "license.txt"), os.path.join(out, "love-license.txt"))

    zip_path = os.path.join(BUILDS, name + "-windows.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for fname in sorted(os.listdir(out)):
            z.write(os.path.join(out, fname), name + "/" + fname)
    for p in (os.path.join(out, name + ".exe"), zip_path):
        print("%-60s %6.1f MB" % (os.path.relpath(p, ROOT), os.path.getsize(p) / 1048576))


if __name__ == "__main__":
    main()
