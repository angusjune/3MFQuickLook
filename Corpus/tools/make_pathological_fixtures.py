#!/usr/bin/env python3
"""Synthesizes the pathological corpus (issue #10): corrupt, truncated,
zip-bomb, image-bomb, and over-budget files that must never break the
preview. Every fixture is deterministic; the parse-seam expectations live in
PathologicalCorpusTests (ThreeMFKit) and the end-to-end expectations in
SmokeTests.

- garbage_bytes.3mf       64 KB of seeded pseudo-random bytes; not a zip.
- text_stub.3mf           the classic 15-byte ASCII stub; not a zip.
- empty.3mf               zero bytes.
- truncated_box.3mf       a valid tiny package cut at 60% — the central
                          directory is gone.
- no_rels.3mf             a real zip with a model part but no _rels/.rels.
- rels_no_model.3mf       relationships exist but name no 3D model.
- missing_model_part.3mf  the relationship targets a part that is absent.
- malformed_model_xml.3mf the model part stops mid-tag.
- zipbomb_model.3mf       ~600 KB archive whose model part inflates to
                          ~600 MB of spam XML — past the extensions'
                          512 MB streamed-part cap (ParseLimits).
- zipbomb_thumbnail.3mf   valid model, but the OPC thumbnail inflates to
                          128 MB — past the 64 MB materialized-part cap;
                          must degrade to "no embedded thumbnail".
- imagebomb_thumbnail.3mf valid model; the OPC thumbnail is a ~120-byte PNG
                          whose header declares 100000x100000 — rejected by
                          PackageImageDecoder's dimension cap, never decoded.
- billion_laughs.3mf      DTD entity-expansion attack in the model part;
                          libxml2's amplification guard must fail it fast.
- deep_xml.3mf            10000-deep element nesting; libxml2's depth cap
                          (256 without XML_PARSE_HUGE) must fail it fast.
- overbudget_grid.3mf     an honest ~2.73M-triangle grid mesh, ~4.10M
                          geometry elements — just past the 4M Geometry
                          Budget (docs/geometry-budget.md). Previews as the
                          open-in-app hint; parses fully unlimited. No
                          embedded thumbnail.
- overbudget_with_thumb.3mf  the same mesh plus a real 32x32 OPC Package
                          Thumbnail — the "stays on its Embedded Thumbnail
                          with the hint" acceptance path.

Regenerate with: python3 Corpus/tools/make_pathological_fixtures.py
(the two over-budget fixtures write ~180 MB of XML; allow ~a minute)
"""

import io
import math
import os
import random
import struct
import zlib
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "pathological")

RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

RELS_WITH_THUMBNAIL = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
 <Relationship Target="/Metadata/thumbnail.png" Id="rel-2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
</Relationships>
"""

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="png" ContentType="image/png"/>
</Types>
"""

BOX_MODEL = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
<resources><object id="1" type="model"><mesh>
<vertices>
<vertex x="0" y="0" z="0"/><vertex x="10" y="0" z="0"/><vertex x="10" y="10" z="0"/><vertex x="0" y="10" z="0"/>
<vertex x="0" y="0" z="10"/><vertex x="10" y="0" z="10"/><vertex x="10" y="10" z="10"/><vertex x="0" y="10" z="10"/>
</vertices>
<triangles>
<triangle v1="0" v2="2" v3="1"/><triangle v1="0" v2="3" v3="2"/>
<triangle v1="4" v2="5" v3="6"/><triangle v1="4" v2="6" v3="7"/>
<triangle v1="0" v2="1" v3="5"/><triangle v1="0" v2="5" v3="4"/>
<triangle v1="1" v2="2" v3="6"/><triangle v1="1" v2="6" v3="5"/>
<triangle v1="2" v2="3" v3="7"/><triangle v1="2" v2="7" v3="6"/>
<triangle v1="3" v2="0" v3="4"/><triangle v1="3" v2="4" v3="7"/>
</triangles>
</mesh></object></resources>
<build><item objectid="1"/></build>
</model>
"""


def write_zip(name, parts, compresslevel=6):
    path = os.path.join(OUT_DIR, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=compresslevel) as z:
        for part_path, data in parts:
            z.writestr(part_path, data)
    print(f"{name}: {os.path.getsize(path):,} bytes")


def write_raw(name, data):
    path = os.path.join(OUT_DIR, name)
    with open(path, "wb") as f:
        f.write(data)
    print(f"{name}: {len(data):,} bytes")


def png(width, height, declared=None):
    """A real grayscale PNG of width x height; `declared` overrides the IHDR
    dimensions to build an image bomb (tiny data, giant claim)."""
    def chunk(kind, payload):
        data = kind + payload
        return struct.pack(">I", len(payload)) + data + struct.pack(">I", zlib.crc32(data))

    dw, dh = declared or (width, height)
    ihdr = struct.pack(">IIBBBBB", dw, dh, 8, 0, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes([200] * width) for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))


def grid_model_xml(target_elements):
    """An honest grid-mesh model part with ~target_elements vertices+triangles
    (3MF-valid, watertight-ish heightfield; ratio ~1 vertex : 2 triangles)."""
    n = math.ceil(math.sqrt(target_elements / 3))
    out = io.StringIO()
    out.write(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
        '<resources><object id="1" type="model"><mesh><vertices>\n')
    for j in range(n + 1):
        for i in range(n + 1):
            z = (i * 7 + j * 13) % 29 * 0.37
            out.write(f'<vertex x="{i * 0.5:.1f}" y="{j * 0.5:.1f}" z="{z:.2f}"/>\n')
    out.write("</vertices><triangles>\n")
    for j in range(n):
        for i in range(n):
            a = j * (n + 1) + i
            b = a + 1
            c = a + n + 1
            d = c + 1
            out.write(f'<triangle v1="{a}" v2="{b}" v3="{d}"/>\n')
            out.write(f'<triangle v1="{a}" v2="{d}" v3="{c}"/>\n')
    out.write('</triangles></mesh></object></resources>\n'
              '<build><item objectid="1"/></build>\n</model>\n')
    elements = (n + 1) ** 2 + 2 * n * n
    return out.getvalue(), elements


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    # --- not zips at all ---
    write_raw("garbage_bytes.3mf", bytes(random.Random(31415).randbytes(65536)))
    write_raw("text_stub.3mf", b"not a 3mf file\n")
    write_raw("empty.3mf", b"")

    # --- broken packages ---
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CONTENT_TYPES)
        z.writestr("_rels/.rels", RELS)
        z.writestr("3D/3dmodel.model", BOX_MODEL)
    intact = buffer.getvalue()
    write_raw("truncated_box.3mf", intact[: int(len(intact) * 0.6)])

    write_zip("no_rels.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("3D/3dmodel.model", BOX_MODEL),
    ])
    write_zip("rels_no_model.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS_WITH_THUMBNAIL.replace(
            '<Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>\n ', "")),
        ("Metadata/thumbnail.png", png(4, 4)),
    ])
    write_zip("missing_model_part.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
    ])
    write_zip("malformed_model_xml.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("3D/3dmodel.model", '<?xml version="1.0"?><model><resources><object'),
    ])

    # --- hostile: decompression bombs ---
    spam_unit = "<metadatagroup>" + " " * 8192 + "</metadatagroup>\n"
    bomb_body = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                 '<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
                 "<resources>\n"
                 + spam_unit * 73_000  # ~600 MB decompressed
                 + "</resources><build/></model>\n")
    write_zip("zipbomb_model.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("3D/3dmodel.model", bomb_body),
    ], compresslevel=9)

    write_zip("zipbomb_thumbnail.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS_WITH_THUMBNAIL),
        ("3D/3dmodel.model", BOX_MODEL),
        ("Metadata/thumbnail.png", b"\x00" * (128 * 1024 * 1024)),  # 128 MB of nothing
    ], compresslevel=9)

    # --- hostile: image bomb (tiny bytes, gigapixel claim) ---
    write_zip("imagebomb_thumbnail.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS_WITH_THUMBNAIL),
        ("3D/3dmodel.model", BOX_MODEL),
        ("Metadata/thumbnail.png", png(2, 2, declared=(100_000, 100_000))),
    ])

    # --- hostile: XML expansion attacks ---
    laughs = ['<!ENTITY lol0 "lolololololololololol">']
    for i in range(1, 10):
        laughs.append(f'<!ENTITY lol{i} "' + f"&lol{i - 1};" * 10 + '">')
    billion = ('<?xml version="1.0"?>\n<!DOCTYPE model [' + "".join(laughs) + "]>\n"
               '<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
               "<resources><object id=\"1\" name=\"&lol9;\" type=\"model\"><mesh><vertices/>"
               "<triangles/></mesh></object></resources><build/></model>")
    write_zip("billion_laughs.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("3D/3dmodel.model", billion),
    ])

    deep = ('<?xml version="1.0"?>\n'
            '<model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">\n'
            "<resources>" + "<a>" * 10_000 + "</a>" * 10_000 + "</resources><build/></model>")
    write_zip("deep_xml.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("3D/3dmodel.model", deep),
    ])

    # --- over the Geometry Budget (honest, valid files) ---
    grid, elements = grid_model_xml(4_100_000)
    print(f"grid mesh: {elements:,} geometry elements, XML {len(grid) / 1e6:.0f} MB")
    write_zip("overbudget_grid.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS),
        ("3D/3dmodel.model", grid),
    ])
    write_zip("overbudget_with_thumb.3mf", [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", RELS_WITH_THUMBNAIL),
        ("3D/3dmodel.model", grid),
        ("Metadata/thumbnail.png", png(32, 32)),
    ])


if __name__ == "__main__":
    main()
