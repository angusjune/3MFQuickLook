#!/usr/bin/env python3
"""Synthesizes the slicer-project corpus fixtures that are hard to source:

- slicer-projects/synthetic_multiplate.3mf — a Bambu-dialect project with
  THREE plates (plate 1 deliberately empty, plate 2 a cube on extruder 1,
  plate 3 a two-part object: pyramid on the object-level extruder 2 plus a
  small cube with a part-level extruder 1 override), two filaments
  (#FF0000 PLA, #00FF00 PETG), and a 180x180 printable_area.
  Production-extension: each root object is a component reference into its
  own 3D/Objects/*.model part, mirroring how Bambu Studio packages geometry
  (part ids in model_settings.config equal the component target object ids,
  as in the real corpus files).
- slicer-projects/synthetic_prusa.3mf — a PrusaSlicer-style project: plain
  core-spec root model plus Metadata/Slic3r_PE*.config parts and NO Bambu
  configs. Must parse as Vanilla-plus (document.slicer == nil).

The values written here are the ground truth the parse-seam tests assert;
regenerate with: python3 Corpus/tools/make_slicer_fixtures.py
"""

import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "slicer-projects")

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
    ])

    vertices, triangles = cube_mesh_xml(10)
    write_fixture(os.path.join(OUT_DIR, "synthetic_prusa.3mf"), [
        ("[Content_Types].xml", CONTENT_TYPES),
        ("_rels/.rels", ROOT_RELS),
        ("3D/3dmodel.model", PRUSA_ROOT_MODEL.format(vertices=vertices, triangles=triangles)),
        ("Metadata/Slic3r_PE.config", PRUSA_CONFIG),
        ("Metadata/Slic3r_PE_model.config", PRUSA_MODEL_CONFIG),
    ])


if __name__ == "__main__":
    main()
