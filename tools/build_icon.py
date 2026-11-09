"""Builds the Shared Resupply stratagem's icon from the installed game: the Resupply icon on the yellow of the
mission ("special") stratagems, such as the Hellbomb, with soft white bullets and a pure white plus.

Usage: python tools/build_icon.py [path to Helldivers/contents]

Writes res/icons.material and res/shared_resupply_icon.texture, both for the boot bundle (see "resources"
in obsidian.json), image.png (the picture Obsidian shows for the mod) and internal/icon_preview.png to look
at. Needs Pillow.

The icon is drawn like the game's own: an 80x80 uncompressed texture with two mips, in the Resupply
icon's header, and a material record copied from the Resupply's in hud/hud, so the Loadout screen's clip
variables and the HUD's shader are the same. Only its name and texture differ.
"""
import io
import struct
import sys
import zlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RES, INTERNAL = ROOT / "res", ROOT / "internal"
CONTENTS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Program Files (x86)\Steam\steamapps\common\Helldivers\contents")
COMMON = "95b2365a6369ee36"  # resource_packages/common, which holds hud/hud

# Keep in step with src/shared_resupply.lua.
ICON = "shared_resupply_icon"
MATERIAL = "shared_resupply/icons"
TEXTURE = "shared_resupply/shared_resupply_icon"

# The yellow stratagem the preview shows beside the new icon.
REFERENCE = "stratagem_hellbomb"

# The Resupply icon's tones, by red value, and the colour each becomes: the frame, inner ring and background
# of the Hellbomb icon, the front silhouette of the Reinforce icon for the bullets, and white for the plus.
TONES = [
    (0, (138, 101, 33)),
    (44, (184, 147, 71)),
    (70, (187, 151, 75)),
    (168, (255, 235, 207)),
    (255, (255, 255, 255)),
]
IMAGE_SCALE = 8

MATERIAL_VERSION = 10
DIFFUSE_MAP = 0x3aa8b87e
RECORD_WORDS = 13


def murmur64(data, seed=0):
    m, r, mask = 0xc6a4a7935bd1e995, 47, (1 << 64) - 1
    h = (seed ^ (len(data) * m)) & mask
    tail = len(data) & ~7
    for (k,) in struct.iter_unpack("<Q", data[:tail]):
        k = (k * m) & mask
        k ^= k >> r
        k = (k * m) & mask
        h = ((h ^ k) * m) & mask
    rest = data[tail:]
    if rest:
        h = ((h ^ int.from_bytes(rest, "little")) * m) & mask
    h ^= h >> r
    h = (h * m) & mask
    return h ^ (h >> r)


def bundle_entries(path):
    """A bundle's resources: (type, name, data of the first variant)."""
    data = path.read_bytes()
    if len(data) < 12 or struct.unpack_from("<I", data, 0)[0] != 0xF0000004:
        raise SystemExit(f"not a bundle: {path}")
    total = struct.unpack_from("<I", data, 4)[0]
    raw, pos = bytearray(), 12
    while pos < len(data) and len(raw) < total:
        (size,) = struct.unpack_from("<I", data, pos)
        pos += 4
        chunk = data[pos:pos + size]
        pos += size
        raw += chunk if size == 0x10000 else zlib.decompress(chunk)
    (count,) = struct.unpack_from("<I", raw, 0)
    pos = 260 + count * 16
    for _ in range(count):
        kind, name, variants, _ = struct.unpack_from("<QQII", raw, pos)
        pos += 24
        heads = [struct.unpack_from("<III", raw, pos + 12 * i) for i in range(variants)]
        pos += 12 * variants
        first = None
        for _, size, _ in heads:
            if first is None:
                first = bytes(raw[pos:pos + size])
            pos += size
        yield kind, name, first


def game_icons():
    """hud/hud's records for the Resupply and the reference stratagem, and their textures' raw bytes."""
    material, texture = murmur64(b"material"), murmur64(b"texture")
    hud = murmur64(b"hud/hud")
    entries = list(bundle_entries(CONTENTS / COMMON))
    data = next(d for k, n, d in entries if k == material and n == hud)
    words = struct.unpack_from("<%dI" % (len(data) // 4), data, 0)
    records = {}
    for name in ("stratagem_resupply", REFERENCE):
        at = words.index(murmur64(name.encode()) >> 32)
        record = words[at:at + RECORD_WORDS]
        if record[5] != DIFFUSE_MAP:
            raise SystemExit(f"{name}: not the record layout this tool knows")
        records[name] = record
    textures = {n: d for k, n, d in entries if k == texture}
    tex = {name: textures[r[6] | (r[7] << 32)] for name, r in records.items()}
    return records, tex


def tone(red, channel):
    """One channel of the colour for a pixel of the given red value, blended between the nearest TONES."""
    for (low, a), (high, b) in zip(TONES, TONES[1:]):
        if red <= high:
            return round(a[channel] + (b[channel] - a[channel]) * (red - low) / (high - low))
    return TONES[-1][1][channel]


def recolour(icon):
    """Maps the icon's tones to TONES by each pixel's red value, keeping alpha. Soft edges blend on their own."""
    red = icon.getchannel("R")
    bands = [red.point([tone(v, c) for v in range(256)]) for c in range(3)]
    return Image.merge("RGBA", (*bands, icon.getchannel("A")))



def texture(header_from, image):
    """The game's layout: the Resupply texture's DDS header, BGRA mips, and its four byte tail."""
    height, width = struct.unpack_from("<II", header_from, 12)
    mips = struct.unpack_from("<I", header_from, 28)[0]
    fourcc, bits = header_from[84:88], struct.unpack_from("<I", header_from, 88)[0]
    if (width, height) != image.size or fourcc != bytes(4) or bits != 32:
        raise SystemExit("the Resupply's texture isn't the uncompressed 32 bit image this tool knows")
    levels, size = [], image.size
    level = image
    for _ in range(mips):
        levels.append(level.tobytes("raw", "BGRA"))
        size = (max(1, size[0] // 2), max(1, size[1] // 2))
        level = level.resize(size, Image.Resampling.BOX)
    body = b"".join(levels)
    if 128 + len(body) + 4 != len(header_from):
        raise SystemExit("the Resupply's texture has a layout this tool doesn't know")
    return header_from[:128] + body + header_from[-4:]


def material(resupply_record):
    tex = murmur64(TEXTURE.encode())
    record = list(resupply_record)
    record[0] = murmur64(ICON.encode()) >> 32
    record[6], record[7] = tex & 0xffffffff, tex >> 32
    return struct.pack("<II", MATERIAL_VERSION, 1) + struct.pack("<%dI" % RECORD_WORDS, *record)


def main():
    records, tex = game_icons()
    resupply = Image.open(io.BytesIO(tex["stratagem_resupply"])).convert("RGBA")
    reference = Image.open(io.BytesIO(tex[REFERENCE])).convert("RGBA")
    icon = recolour(resupply)
    RES.mkdir(exist_ok=True)
    INTERNAL.mkdir(exist_ok=True)
    (RES / "shared_resupply_icon.texture").write_bytes(texture(tex["stratagem_resupply"], icon))
    (RES / "icons.material").write_bytes(material(records["stratagem_resupply"]))
    w, h = icon.size
    icon.resize((w * IMAGE_SCALE, h * IMAGE_SCALE), Image.Resampling.NEAREST).save(ROOT / "image.png")
    preview = Image.new("RGBA", (w * 12 + 32, h * 4), (30, 30, 30, 255))
    preview.paste(resupply.resize((w * 4, h * 4), Image.Resampling.NEAREST), (0, 0))
    preview.paste(icon.resize((w * 4, h * 4), Image.Resampling.NEAREST), (w * 4 + 16, 0))
    preview.paste(reference.resize((w * 4, h * 4), Image.Resampling.NEAREST), (w * 8 + 32, 0))
    preview.save(INTERNAL / "icon_preview.png")
    reference.resize((w * 4, h * 4), Image.Resampling.NEAREST).save(INTERNAL / "hellbomb_preview.png")
    print("wrote", RES / "shared_resupply_icon.texture", RES / "icons.material")


if __name__ == "__main__":
    main()
