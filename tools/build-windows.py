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
    # A fused executable: love.exe with the game package attached to its end
    with open(os.path.join(out, name + ".exe"), "wb") as exe:
        with open(os.path.join(LOVE, "love.exe"), "rb") as f:
            shutil.copyfileobj(f, exe)
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
