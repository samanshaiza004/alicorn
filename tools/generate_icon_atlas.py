"""Compile pinned monochrome SVGs with resvg; normal Alicorn builds need neither tool.

python tools/generate_icon_atlas.py --resvg .deps/icon-tools/bin/resvg.exe [--verify]
Only Python's standard library is required. PNG decoding extracts coverage from alpha.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess
import xml.etree.ElementTree as ET
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
MIN_SIZE, MAX_SIZE, PAGE_SIZE, GUTTER = 8, 64, 1024, 2


def sha(data):
    return hashlib.sha256(data).hexdigest()


def validate_svg(data):
    if b"<!" in data or b"<?" in data:
        raise ValueError("SVG declarations and external entities are forbidden")
    root = ET.fromstring(data)
    if root.tag != "{http://www.w3.org/2000/svg}svg" or root.get("viewBox") != "0 0 24 24":
        raise ValueError("Expected a 24-unit SVG")
    attributes = {"viewBox", "width", "height", "color", "d", "fill", "fill-rule",
                  "clip-rule", "cx", "cy", "r", "x", "y", "rx", "ry", "points"}
    for node in root.iter():
        if node.tag.rsplit("}", 1)[-1] not in {"svg", "path", "circle", "rect", "polygon", "ellipse"}:
            raise ValueError("Unsupported SVG element")
        for key, value in node.attrib.items():
            if key not in attributes or "url(" in value:
                raise ValueError("Unsupported SVG attribute or resource reference")
            if key in {"fill", "color"} and value not in {"currentColor", "#ffffff", "none"}:
                raise ValueError("Only opaque monochrome paint is allowed")


def read_alpha(path, expected):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Rasterizer did not produce PNG")
    position, compressed = 8, bytearray()
    while position < len(data):
        count = struct.unpack_from(">I", data, position)[0]
        kind, body = data[position + 4:position + 8], data[position + 8:position + 8 + count]
        if kind == b"IHDR":
            width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (width, height, depth, color, interlace) != (expected, expected, 8, 6, 0):
                raise ValueError("Expected non-interlaced RGBA8 at the requested dimensions")
        if kind == b"IDAT":
            compressed.extend(body)
        position += count + 12
    raw = zlib.decompress(compressed)
    stride, previous, result = expected * 4, bytearray(expected * 4), bytearray()
    for y in range(expected):
        mode = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a, b, c = row[x - 4] if x >= 4 else 0, previous[x], previous[x - 4] if x >= 4 else 0
            if mode == 1: predictor = a
            elif mode == 2: predictor = b
            elif mode == 3: predictor = (a + b) // 2
            elif mode == 4:
                p = a + b - c
                distances = [abs(p - a), abs(p - b), abs(p - c)]
                predictor = [a, b, c][distances.index(min(distances))]
            elif mode == 0: predictor = 0
            else: raise ValueError("Invalid PNG filter")
            row[x] = (row[x] + predictor) & 255
        result.extend(row[3::4])
        previous = row
    if not any(0 < pixel < 255 for pixel in result):
        raise ValueError("Rasterized icon has no antialiased coverage")
    return result


def png_rgba(width, height, pixels, compression_level=9):
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(b"\0" + pixels[y * width * 4:(y + 1) * width * 4] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, compression_level)) + chunk(b"IEND", b""))


def decode_png_rgba(data):
    """Return dimensions and RGBA pixels, independent of PNG compression bytes."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Expected PNG data")
    position, compressed, dimensions = 8, bytearray(), None
    while position + 12 <= len(data):
        count = struct.unpack_from(">I", data, position)[0]
        end = position + count + 12
        if end > len(data):
            raise ValueError("Truncated PNG chunk")
        kind, body = data[position + 4:position + 8], data[position + 8:position + 8 + count]
        if kind == b"IHDR":
            width, height, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("Expected non-interlaced RGBA8 PNG")
            dimensions = width, height
        elif kind == b"IDAT":
            compressed.extend(body)
        elif kind == b"IEND":
            break
        position = end
    if dimensions is None:
        raise ValueError("PNG is missing its header")
    width, height = dimensions
    stride = width * 4
    raw = zlib.decompress(compressed)
    if len(raw) != height * (stride + 1):
        raise ValueError("Unexpected PNG pixel data length")
    pixels, previous = bytearray(), bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        mode = raw[start]
        row = bytearray(raw[start + 1:start + stride + 1])
        for x in range(stride):
            a = row[x - 4] if x >= 4 else 0
            b = previous[x]
            c = previous[x - 4] if x >= 4 else 0
            if mode == 0:
                predictor = 0
            elif mode == 1:
                predictor = a
            elif mode == 2:
                predictor = b
            elif mode == 3:
                predictor = (a + b) // 2
            elif mode == 4:
                p = a + b - c
                distances = (abs(p - a), abs(p - b), abs(p - c))
                predictor = (a, b, c)[distances.index(min(distances))]
            else:
                raise ValueError("Invalid PNG filter")
            row[x] = (row[x] + predictor) & 255
        pixels.extend(row)
        previous = row
    return width, height, bytes(pixels)


def artifact_matches(relative, existing, generated):
    # zlib can encode identical PNG pixels differently across operating systems.
    # Runtime masks, manifests, and Odin source remain byte-for-byte verified;
    # the visual-only contact sheet is checked by decoded pixels instead.
    if relative == "assets/icons/generated/contact_sheet.png":
        try:
            return decode_png_rgba(existing) == decode_png_rgba(generated)
        except (ValueError, zlib.error, struct.error):
            return False
    return existing == generated


def generate(resvg, temporary):
    sources_path = ROOT / "assets/icons/reicon/sources.json"
    sources = json.loads(sources_path.read_text())
    version = subprocess.check_output([resvg, "--version"], text=True).strip()
    if version.removeprefix("resvg ") != sources["resvg_version"]:
        raise ValueError("Unexpected rasterizer version: " + version)
    icons = sources["icons"]
    masks = {}
    for index, icon in enumerate(icons):
        source = sources_path.parent / icon["file"]
        data = source.read_bytes()
        if sha(data) != icon["sha256"]:
            raise ValueError("Source hash mismatch: " + icon["file"])
        validate_svg(data)
        for size in range(MIN_SIZE, MAX_SIZE + 1):
            raster = temporary / "icon.png"
            subprocess.run([resvg, "--skip-system-fonts", "--width", str(size), "--height", str(size), str(source), str(raster)], check=True, capture_output=True)
            masks[index, size] = read_alpha(raster, size)
    pages, entries = [bytearray(PAGE_SIZE * PAGE_SIZE)], {}
    page, x, y, row_height = 0, 0, 0, 0
    for size in range(MAX_SIZE, MIN_SIZE - 1, -1):
        extent = size + GUTTER * 2
        for index in range(len(icons)):
            if x + extent > PAGE_SIZE:
                x, y, row_height = 0, y + row_height, 0
            if y + extent > PAGE_SIZE:
                pages.append(bytearray(PAGE_SIZE * PAGE_SIZE))
                page, x, y, row_height = page + 1, 0, 0, 0
            px, py = x + GUTTER, y + GUTTER
            mask = masks[index, size]
            for line in range(size):
                offset = (py + line) * PAGE_SIZE + px
                pages[page][offset:offset + size] = mask[line * size:(line + 1) * size]
            entries[index, size] = dict(page=page, x=px, y=py, size=size)
            x, row_height = x + extent, max(row_height, extent)
    output = {}
    page_manifest = []
    for index, pixels in enumerate(pages):
        height = PAGE_SIZE if index < len(pages) - 1 else ((y + row_height + 255) // 256) * 256
        pixels = bytes(pixels[:height * PAGE_SIZE])
        name = "atlas_%d.r8" % index
        output["assets/icons/generated/" + name] = pixels
        page_manifest.append(dict(file=name, width=PAGE_SIZE, height=height, sha256=sha(pixels)))
    manifest = dict(format="alicorn-r8-icons-v1", packing="descending-size-shelf-v1", gutter=GUTTER,
                    normalization="opaque-white-currentColor-v1", coverage_channel="alpha", system_fonts=False,
                    physical_sizes=[MIN_SIZE, MAX_SIZE], sources=sources, pages=page_manifest,
                    entries=[dict(icon=icons[i]["id"], **entries[i, s]) for i in range(len(icons)) for s in range(MIN_SIZE, MAX_SIZE + 1)])
    output["assets/icons/generated/manifest.json"] = (json.dumps(manifest, indent=2) + "\n").encode()
    code = "// Generated by tools/generate_icon_atlas.py. Do not edit.\npackage alicorn\n\n"
    code += "ICON_ATLAS_MIN_SIZE :: 8\nICON_ATLAS_MAX_SIZE :: 64\nICON_ATLAS_GUTTER :: 2\n"
    code += "ICON_ATLAS_PAGES: [" + str(len(pages)) + "]Icon_Atlas_Page_Data = {\n"
    for p in page_manifest:
        code += '\t{%d, %d, #load("../assets/icons/generated/%s")},\n' % (p["width"], p["height"], p["file"])
    code += "}\n\nICON_ATLAS_ENTRIES: [" + str(len(entries)) + "]Icon_Atlas_Entry = {\n"
    for i in range(len(icons)):
        for s in range(MIN_SIZE, MAX_SIZE + 1):
            e = entries[i, s]
            code += "\t{%d, %d, %d, %d}, // %s\n" % (e["page"], e["x"], e["y"], s, icons[i]["id"])
    code += "}\n"
    output["runtime/icon_atlas_generated.odin"] = code.encode()
    # A contact sheet at actual physical pixel sizes, on light and dark surfaces.
    sizes, width, height = [12, 16, 20, 24, 32], len(icons) * 72, 5 * 80
    sheet = bytearray(width * height * 4)
    for row, s in enumerate(sizes):
        for i in range(len(icons)):
            for half, (bg, fg) in enumerate([(18, 225), (245, 35)]):
                for yy in range(40):
                    for xx in range(72):
                        local_x, local_y = xx - (72 - s) // 2, yy - (40 - s) // 2
                        cov = masks[i, s][local_y * s + local_x] / 255 if 0 <= local_x < s and 0 <= local_y < s else 0
                        value = round(bg + (fg - bg) * cov)
                        offset = ((row * 80 + half * 40 + yy) * width + i * 72 + xx) * 4
                        sheet[offset:offset + 4] = bytes([value, value, value, 255])
    output["assets/icons/generated/contact_sheet.png"] = png_rgba(width, height, sheet)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resvg", required=True)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    directory = ROOT / "out/icon-generation"
    directory.mkdir(parents=True, exist_ok=True)
    outputs = generate(args.resvg, directory)
    for relative, data in outputs.items():
        path = ROOT / relative
        if args.verify:
            if not path.exists() or not artifact_matches(relative, path.read_bytes(), data):
                raise SystemExit("Generated artifact differs: " + relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print("%s %d generated artifacts" % ("Verified" if args.verify else "Generated", len(outputs)))


if __name__ == "__main__":
    main()
