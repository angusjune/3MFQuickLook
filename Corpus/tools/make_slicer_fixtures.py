#!/usr/bin/env python3
"""Synthesizes the slicer-project corpus fixtures that are hard to source:

- slicer-projects/synthetic_multiplate.3mf — a Bambu-dialect project with
  THREE plates (plate 1 deliberately empty, plate 2 a cube on extruder 1,
  plate 3 a two-part object: pyramid on the object-level extruder 2 plus a
  small cube with a part-level extruder 1 override), two filaments
  (#FF0000 PLA, #00FF00 PETG), and a 180x180 printable_area.
  Plate 2 carries a real Plate Thumbnail (Metadata/plate_2.png, a 4x4
  solid-red PNG); plates 1 and 3 deliberately have none, exercising the
  Filmstrip's numbered-placeholder fallback.
  Plate 2 is also the only SLICED plate: Metadata/slice_info.config records
  its prediction (5460 s) and used filament (id 1). Plates 1 and 3 have no
  slice_info entry, exercising the unsliced fallbacks (no print time;
  filament dots derived from object assignments).
  Production-extension: each root object is a component reference into its
  own 3D/Objects/*.model part, mirroring how Bambu Studio packages geometry
  (part ids in model_settings.config equal the component target object ids,
  as in the real corpus files).
- slicer-projects/synthetic_prusa.3mf — a PrusaSlicer-style project: plain
  core-spec root model plus Metadata/Slic3r_PE*.config parts and NO Bambu
  configs. Must parse as Vanilla-plus (document.slicer == nil).
- sliced/synthetic_single.gcode.3mf — a Bambu-style Sliced File (issue #8):
  geometry-stripped root model, ONE sliced plate with its G-code part
  (Metadata/plate_1.gcode), Plate Thumbnail (6x6 solid blue), prediction
  3720 s, one filament (#00AE42 PLA), printer_model "Bambu Lab P1S".
- sliced/synthetic_multiplate.gcode.3mf — a Sliced File with TWO sliced
  plates (predictions 3600 s / 7245 s, red and green 4x4 Plate Thumbnails,
  each using one of the two filaments #FF0000 PLA / #0000FF PETG),
  printer_model "Bambu Lab X1 Carbon".

The values written here are the ground truth the parse-seam tests assert;
regenerate with: python3 Corpus/tools/make_slicer_fixtures.py
"""

import os
import struct
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "slicer-projects")
SLICED_OUT_DIR = os.path.join(HERE, "..", "sliced")

CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="png" ContentType="image/png"/>
</Types>
"""

ROOT_RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""


def solid_png(width, height, rgb):
    """A minimal valid PNG (8-bit RGB, one solid color), dependency-free."""
    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def cube_mesh_xml(size):
    """An axis-aligned cube [0, size]^3: 8 vertices, 12 triangles."""
    vs = []
    for z in (0, size):
        for y in (0, size):
            for x in (0, size):
                vs.append(f'     <vertex x="{x}" y="{y}" z="{z}"/>')
    tris = [(0, 2, 1), (1, 2, 3), (4, 5, 6), (5, 7, 6),
            (0, 1, 4), (1, 5, 4), (2, 6, 3), (3, 6, 7),
            (0, 4, 2), (2, 4, 6), (1, 3, 5), (3, 7, 5)]
    ts = [f'     <triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in tris]
    return "\n".join(vs), "\n".join(ts)


def pyramid_mesh_xml(base, height):
    """A square pyramid, base [0, base]^2 at z=0, apex above the center."""
    vs = [
        f'     <vertex x="0" y="0" z="0"/>',
        f'     <vertex x="{base}" y="0" z="0"/>',
        f'     <vertex x="{base}" y="{base}" z="0"/>',
        f'     <vertex x="0" y="{base}" z="0"/>',
        f'     <vertex x="{base / 2}" y="{base / 2}" z="{height}"/>',
    ]
    tris = [(0, 2, 1), (0, 3, 2), (0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    ts = [f'     <triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in tris]
    return "\n".join(vs), "\n".join(ts)


def object_part(*objects):
    """A production-extension object part holding (object_id, mesh_xml) meshes."""
    blocks = []
    for object_id, (vertices, triangles) in objects:
        blocks.append(f"""  <object id="{object_id}" type="model">
   <mesh>
    <vertices>
{vertices}
    </vertices>
    <triangles>
{triangles}
    </triangles>
   </mesh>
  </object>""")
    resources = "\n".join(blocks)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" requiredextensions="p">
 <resources>
{resources}
 </resources>
 <build/>
</model>
"""


MULTIPLATE_ROOT_MODEL = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06" requiredextensions="p">
 <metadata name="Application">synthetic-multiplate-fixture</metadata>
 <resources>
  <object id="2" type="model">
   <components>
    <component p:path="/3D/Objects/object_1.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
   </components>
  </object>
  <object id="4" type="model">
   <components>
    <component p:path="/3D/Objects/object_2.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
    <component p:path="/3D/Objects/object_2.model" objectid="2" transform="1 0 0 0 1 0 0 0 1 0 0 15"/>
   </components>
  </object>
 </resources>
 <build>
  <item objectid="2" transform="1 0 0 0 1 0 0 0 1 80 80 0" printable="1"/>
  <item objectid="4" transform="1 0 0 0 1 0 0 0 1 75 75 0" printable="1"/>
 </build>
</model>
"""

MULTIPLATE_MODEL_RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/Objects/object_1.model" Id="rel-1" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
 <Relationship Target="/3D/Objects/object_2.model" Id="rel-2" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

# Plate 1 is deliberately empty: the default-plate rule must skip it.
MULTIPLATE_MODEL_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="2">
    <metadata key="name" value="Cube"/>
    <metadata key="extruder" value="1"/>
  </object>
  <object id="4">
    <metadata key="name" value="Pyramid"/>
    <metadata key="extruder" value="2"/>
    <part id="1" subtype="normal_part">
      <metadata key="name" value="Pyramid"/>
    </part>
    <part id="2" subtype="normal_part">
      <metadata key="name" value="Topper"/>
      <metadata key="extruder" value="1"/>
    </part>
  </object>
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value=""/>
  </plate>
  <plate>
    <metadata key="plater_id" value="2"/>
    <metadata key="plater_name" value="Cube Plate"/>
    <metadata key="thumbnail_file" value="Metadata/plate_2.png"/>
    <model_instance>
      <metadata key="object_id" value="2"/>
      <metadata key="instance_id" value="0"/>
    </model_instance>
  </plate>
  <plate>
    <metadata key="plater_id" value="3"/>
    <metadata key="plater_name" value=""/>
    <model_instance>
      <metadata key="object_id" value="4"/>
      <metadata key="instance_id" value="0"/>
    </model_instance>
  </plate>
</config>
"""

MULTIPLATE_PROJECT_SETTINGS = """{
  "filament_colour": ["#FF0000", "#00FF00"],
  "filament_type": ["PLA", "PETG"],
  "printable_area": ["0x0", "180x0", "180x180", "0x180"],
  "printable_height": "180"
}
"""

# Only plate 2 has been sliced; the shape mirrors Bambu Studio's output
# (plate <metadata key="index"> matches the plate's plater_id, prediction in
# seconds, one <filament> per filament the sliced G-code uses, 1-based ids).
MULTIPLATE_SLICE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <header>
    <header_item key="X-BBL-Client-Type" value="slicer"/>
    <header_item key="X-BBL-Client-Version" value="02.03.01.51"/>
  </header>
  <plate>
    <metadata key="index" value="2"/>
    <metadata key="printer_model_id" value="C11"/>
    <metadata key="nozzle_diameters" value="0.4"/>
    <metadata key="prediction" value="5460"/>
    <metadata key="weight" value="4.88"/>
    <metadata key="outside" value="false"/>
    <metadata key="support_used" value="false"/>
    <object identify_id="86" name="Cube" skipped="false"/>
    <filament id="1" tray_info_idx="GFA00" type="PLA" color="#FF0000" used_m="1.63" used_g="4.88"/>
  </plate>
</config>
"""

PRUSA_ROOT_MODEL = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:slic3rpe="http://schemas.slic3r.org/3mf/2017/06">
 <metadata name="slic3rpe:Version3mf">1</metadata>
 <metadata name="Application">PrusaSlicer-2.9.0</metadata>
 <resources>
  <object id="1" type="model">
   <mesh>
    <vertices>
{vertices}
    </vertices>
    <triangles>
{triangles}
    </triangles>
   </mesh>
  </object>
 </resources>
 <build>
  <item objectid="1" transform="1 0 0 0 1 0 0 0 1 115 95 0" printable="1"/>
 </build>
</model>
"""

PRUSA_CONFIG = """; generated by PrusaSlicer 2.9.0 (synthetic fixture)
filament_colour = #FF8000
filament_type = PLA
bed_shape = 0x0,250x0,250x210,0x210
"""

PRUSA_MODEL_CONFIG = """<?xml version="1.0" encoding="UTF-8"?>
<config>
 <object id="1" instances_count="1">
  <metadata type="object" key="name" value="synthetic_cube"/>
  <volume firstid="0" lastid="11">
   <metadata type="volume" key="name" value="synthetic_cube"/>
  </volume>
 </object>
</config>
"""


# --- Sliced Files (.gcode.3mf, issue #8) ---------------------------------
# Mirrors Bambu Studio's sliced export: the root model keeps its metadata but
# its resources and build are EMPTY (geometry stripped), while Metadata/
# gains one plate_N.gcode per sliced plate. model_settings.config keeps the
# plate blocks (with gcode_file alongside thumbnail_file) and the
# model_instance/identify_id entries the printer's skip-object feature needs.

SLICED_CONTENT_TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
 <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
 <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
 <Default Extension="png" ContentType="image/png"/>
 <Default Extension="gcode" ContentType="text/x.gcode"/>
</Types>
"""

SLICED_ROOT_MODEL = """<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
 <metadata name="Application">BambuStudio-02.03.01.51</metadata>
 <metadata name="Title">synthetic sliced fixture</metadata>
 <resources/>
 <build/>
</model>
"""


def fake_gcode(minutes):
    return (
        "; BambuStudio 02.03.01.51\n"
        f"; model printing time: {minutes}m\n"
        "; total layer number: 2\n"
        "G28\nG1 X10 Y10 Z0.2 F3000\nG1 X20 E1.5\nM400\n"
    )


SLICED_SINGLE_MODEL_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="2">
    <metadata key="name" value="Benchy"/>
    <metadata key="extruder" value="1"/>
  </object>
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value=""/>
    <metadata key="gcode_file" value="Metadata/plate_1.gcode"/>
    <metadata key="thumbnail_file" value="Metadata/plate_1.png"/>
    <model_instance>
      <metadata key="object_id" value="2"/>
      <metadata key="instance_id" value="0"/>
      <metadata key="identify_id" value="463"/>
    </model_instance>
  </plate>
</config>
"""

SLICED_SINGLE_PROJECT_SETTINGS = """{
  "filament_colour": ["#00AE42"],
  "filament_type": ["PLA"],
  "printer_model": "Bambu Lab P1S",
  "printable_area": ["0x0", "256x0", "256x256", "0x256"],
  "printable_height": "256"
}
"""

SLICED_SINGLE_SLICE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <header>
    <header_item key="X-BBL-Client-Type" value="slicer"/>
    <header_item key="X-BBL-Client-Version" value="02.03.01.51"/>
  </header>
  <plate>
    <metadata key="index" value="1"/>
    <metadata key="printer_model_id" value="C12"/>
    <metadata key="nozzle_diameters" value="0.4"/>
    <metadata key="prediction" value="3720"/>
    <metadata key="weight" value="15.37"/>
    <metadata key="outside" value="false"/>
    <metadata key="support_used" value="false"/>
    <object identify_id="463" name="Benchy" skipped="false"/>
    <filament id="1" tray_info_idx="GFA00" type="PLA" color="#00AE42" used_m="5.12" used_g="15.37"/>
  </plate>
</config>
"""

SLICED_MULTI_MODEL_SETTINGS = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="2">
    <metadata key="name" value="Cube"/>
    <metadata key="extruder" value="1"/>
  </object>
  <object id="4">
    <metadata key="name" value="Pyramid"/>
    <metadata key="extruder" value="2"/>
  </object>
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value="Cube Plate"/>
    <metadata key="gcode_file" value="Metadata/plate_1.gcode"/>
    <metadata key="thumbnail_file" value="Metadata/plate_1.png"/>
    <model_instance>
      <metadata key="object_id" value="2"/>
      <metadata key="instance_id" value="0"/>
      <metadata key="identify_id" value="86"/>
    </model_instance>
  </plate>
  <plate>
    <metadata key="plater_id" value="2"/>
    <metadata key="plater_name" value=""/>
    <metadata key="gcode_file" value="Metadata/plate_2.gcode"/>
    <metadata key="thumbnail_file" value="Metadata/plate_2.png"/>
    <model_instance>
      <metadata key="object_id" value="4"/>
      <metadata key="instance_id" value="0"/>
      <metadata key="identify_id" value="87"/>
    </model_instance>
  </plate>
</config>
"""

SLICED_MULTI_PROJECT_SETTINGS = """{
  "filament_colour": ["#FF0000", "#0000FF"],
  "filament_type": ["PLA", "PETG"],
  "printer_model": "Bambu Lab X1 Carbon",
  "printable_area": ["0x0", "256x0", "256x256", "0x256"],
  "printable_height": "256"
}
"""

SLICED_MULTI_SLICE_INFO = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <header>
    <header_item key="X-BBL-Client-Type" value="slicer"/>
    <header_item key="X-BBL-Client-Version" value="02.03.01.51"/>
  </header>
  <plate>
    <metadata key="index" value="1"/>
    <metadata key="printer_model_id" value="BL-P001"/>
    <metadata key="nozzle_diameters" value="0.4"/>
    <metadata key="prediction" value="3600"/>
    <metadata key="weight" value="4.88"/>
    <metadata key="outside" value="false"/>
    <metadata key="support_used" value="false"/>
    <object identify_id="86" name="Cube" skipped="false"/>
    <filament id="1" tray_info_idx="GFA00" type="PLA" color="#FF0000" used_m="1.63" used_g="4.88"/>
  </plate>
  <plate>
    <metadata key="index" value="2"/>
    <metadata key="printer_model_id" value="BL-P001"/>
    <metadata key="nozzle_diameters" value="0.4"/>
    <metadata key="prediction" value="7245"/>
    <metadata key="weight" value="9.20"/>
    <metadata key="outside" value="false"/>
    <metadata key="support_used" value="false"/>
    <object identify_id="87" name="Pyramid" skipped="false"/>
    <filament id="2" tray_info_idx="GFG00" type="PETG" color="#0000FF" used_m="3.07" used_g="9.20"/>
  </plate>
</config>
"""


def write_fixture(path, parts):
    """Writes a deterministic zip: fixed timestamps, insertion order."""
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, payload in parts:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, payload)
    print(f"wrote {os.path.relpath(path)}")


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    write_fixture(os.path.join(OUT_DIR, "synthetic_multiplate.3mf"), [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", ROOT_RELS),
        ("3D/3dmodel.model", MULTIPLATE_ROOT_MODEL),
        ("3D/_rels/3dmodel.model.rels", MULTIPLATE_MODEL_RELS),
        ("3D/Objects/object_1.model", object_part((1, cube_mesh_xml(20)))),
        ("3D/Objects/object_2.model", object_part(
            (1, pyramid_mesh_xml(30, 15)), (2, cube_mesh_xml(10)))),
        ("Metadata/model_settings.config", MULTIPLATE_MODEL_SETTINGS),
        ("Metadata/project_settings.config", MULTIPLATE_PROJECT_SETTINGS),
        ("Metadata/slice_info.config", MULTIPLATE_SLICE_INFO),
        ("Metadata/plate_2.png", solid_png(4, 4, (255, 0, 0))),
    ])

    vertices, triangles = cube_mesh_xml(10)
    write_fixture(os.path.join(OUT_DIR, "synthetic_prusa.3mf"), [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", ROOT_RELS),
        ("3D/3dmodel.model", PRUSA_ROOT_MODEL.format(vertices=vertices, triangles=triangles)),
        ("Metadata/Slic3r_PE.config", PRUSA_CONFIG),
        ("Metadata/Slic3r_PE_model.config", PRUSA_MODEL_CONFIG),
    ])

    os.makedirs(SLICED_OUT_DIR, exist_ok=True)

    write_fixture(os.path.join(SLICED_OUT_DIR, "synthetic_single.gcode.3mf"), [
        ("[Content_Types].xml", SLICED_CONTENT_TYPES),
        ("_rels/.rels", ROOT_RELS),
        ("3D/3dmodel.model", SLICED_ROOT_MODEL),
        ("Metadata/model_settings.config", SLICED_SINGLE_MODEL_SETTINGS),
        ("Metadata/project_settings.config", SLICED_SINGLE_PROJECT_SETTINGS),
        ("Metadata/slice_info.config", SLICED_SINGLE_SLICE_INFO),
        ("Metadata/plate_1.gcode", fake_gcode(62)),
        ("Metadata/plate_1.png", solid_png(6, 6, (0, 0, 255))),
    ])

    write_fixture(os.path.join(SLICED_OUT_DIR, "synthetic_multiplate.gcode.3mf"), [
        ("[Content_Types].xml", SLICED_CONTENT_TYPES),
        ("_rels/.rels", ROOT_RELS),
        ("3D/3dmodel.model", SLICED_ROOT_MODEL),
        ("Metadata/model_settings.config", SLICED_MULTI_MODEL_SETTINGS),
        ("Metadata/project_settings.config", SLICED_MULTI_PROJECT_SETTINGS),
        ("Metadata/slice_info.config", SLICED_MULTI_SLICE_INFO),
        ("Metadata/plate_1.gcode", fake_gcode(60)),
        ("Metadata/plate_1.png", solid_png(4, 4, (255, 0, 0))),
        ("Metadata/plate_2.gcode", fake_gcode(121)),
        ("Metadata/plate_2.png", solid_png(4, 4, (0, 255, 0))),
    ])


if __name__ == "__main__":
    main()
