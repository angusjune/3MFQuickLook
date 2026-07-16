import Foundation
import Testing
import ThreeMFKit

/// Parse-seam tests for Bambu/Orca paint strokes (issue #9): given a file
/// whose triangles carry `paint_color` attributes, the mesh exposes each
/// painted triangle's dominant filament index — the PRD's approximation, no
/// sub-triangle segmentation. Ground truth for the encoding is PrusaSlicer's
/// TriangleSelector bitstream (hex nibbles in reverse order), which Bambu
/// Studio and OrcaSlicer write verbatim.
@Suite struct PaintSeamTests {

    /// One triangle per encoding shape. Expected dominant filament indices
    /// are 0-based (`paint_color` state N = filament N, 1-based).
    @Test func paintedTrianglesExposeDominantFilamentIndices() throws {
        let cases: [(paint: String?, expected: Int?)] = [
            (nil, nil),        // no attribute at all
            ("4", 0),          // leaf state 1
            ("8", 1),          // leaf state 2
            ("0C", 2),         // extended leaf state 3
            ("1C", 3),         // extended leaf state 4
            ("2C", 4),         // extended leaf state 5 — exposed as-is
            ("8442", 0),       // 3-way split, children 1,1,2 → dominant 1
            ("81C1C2", 3),     // 3-way split, extended children 4,4,2 → 4
            ("4002", nil),     // 3-way split, children 0,0,1 → mostly bare
            ("", nil),         // degenerate value
            ("ZZ", nil),       // garbage decodes as unpainted
        ]
        let url = try writePackage(paints: cases.map(\.paint))
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.triangleCount == cases.count)
        #expect(mesh.trianglePaintFilamentIndices == cases.map(\.expected))
        // Paint is not a spec property reference; it must not fabricate one.
        #expect(mesh.triangleColors == nil)
    }

    @Test func meshWithoutPaintExposesNoPaintData() throws {
        let url = try writePackage(paints: [nil, nil])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.trianglePaintFilamentIndices == nil)
    }

    /// Strokes that only ever resolve to state 0 are indistinguishable from
    /// no paint at all — the array must not materialize.
    @Test func paintThatIsEntirelyBareExposesNoPaintData() throws {
        let url = try writePackage(paints: ["0", "4002", nil])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.trianglePaintFilamentIndices == nil)
    }

    /// Paint coexists with spec property references: each stays on its own
    /// channel of the mesh.
    @Test func paintAndPropertyColorsAreExposedIndependently() throws {
        let model = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" \
        xmlns:m="http://schemas.microsoft.com/3dmanufacturing/material/2015/02">
         <resources>
          <m:colorgroup id="7">
           <m:color color="#112233FF"/>
          </m:colorgroup>
          <object id="1" type="model">
           <mesh>
            <vertices>
             <vertex x="0" y="0" z="0"/>
             <vertex x="10" y="0" z="0"/>
             <vertex x="0" y="10" z="0"/>
             <vertex x="0" y="0" z="10"/>
            </vertices>
            <triangles>
             <triangle v1="0" v2="2" v3="1" pid="7" p1="0"/>
             <triangle v1="0" v2="1" v3="3" paint_color="8"/>
            </triangles>
           </mesh>
          </object>
         </resources>
         <build>
          <item objectid="1"/>
         </build>
        </model>
        """
        let url = try writeTemporaryPackage(named: "paint-and-props", parts: [
            ("_rels/.rels", Data(Self.rels.utf8)),
            ("3D/3dmodel.model", Data(model.utf8)),
        ])
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.triangleColors == [ColorRGBA(red: 0x11, green: 0x22, blue: 0x33), nil])
        #expect(mesh.trianglePaintFilamentIndices == [nil, 1])
    }

    // MARK: Corpus-driven (ground truth by construction:
    // Corpus/tools/make_slicer_fixtures.py, PAINTED_CUBE_PAINTS)

    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_painted.3mf")))
    func paintedProjectExposesPaintAlongsideItsFilaments() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_painted.3mf"))

        let slicer = try #require(doc.slicerProject)
        #expect(slicer.filaments.map(\.color) == [
            ColorRGBA(red: 255, green: 0, blue: 0),
            ColorRGBA(red: 0, green: 255, blue: 0),
            ColorRGBA(red: 0, green: 0, blue: 255),
            ColorRGBA(red: 255, green: 255, blue: 0),
        ])

        // The painted cube lives in the production-extension object part;
        // the root wrapper (id 2) prints on extruder 4 → filament index 3.
        let meshRef = ResourceRef(partPath: "/3D/Objects/object_1.model", id: 1)
        let wrapperRef = ResourceRef(partPath: "/3D/3dmodel.model", id: 2)
        #expect(slicer.filamentIndexByObject[wrapperRef] == 3)

        let mesh = try #require(doc.object(meshRef)?.mesh)
        #expect(mesh.triangleCount == 12)
        #expect(mesh.trianglePaintFilamentIndices == [
            nil, nil, nil, nil, 0, 1, 2, 3, 0, 3, 4, nil,
        ])
        #expect(mesh.triangleColors == nil)
    }

    /// A real painted MakerWorld export (Bambu Studio 02.01, "Hinged Locked
    /// Treasure Chest", CC BY-NC-SA). Ground truth by independent inspection
    /// (`unzip -p … | grep paint_color`): 87,756 triangles, of which 12,505
    /// carry `paint_color="8"` (state 2 → filament index 1) and 6 carry
    /// `paint_color="4"` (state 1 → filament index 0); filament_colour
    /// ["#7D6556", "#A6A9AA"].
    @Test(.enabled(if: Corpus.has("slicer-projects/Hinged-Locked-Chest_MultiColor.3mf")))
    func realMakerWorldPaintedModelExposesItsStrokes() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/Hinged-Locked-Chest_MultiColor.3mf"))

        let slicer = try #require(doc.slicerProject)
        #expect(slicer.filaments.map(\.color) == [
            ColorRGBA(red: 0x7D, green: 0x65, blue: 0x56),
            ColorRGBA(red: 0xA6, green: 0xA9, blue: 0xAA),
        ])

        let mesh = try #require(
            doc.object(ResourceRef(partPath: "/3D/Objects/object_1.model", id: 1))?.mesh)
        #expect(mesh.triangleCount == 87756)
        let paints = try #require(mesh.trianglePaintFilamentIndices)
        #expect(paints.count == mesh.triangleCount)
        var tally: [Int?: Int] = [:]
        for paint in paints { tally[paint, default: 0] += 1 }
        #expect(tally[0] == 6)
        #expect(tally[1] == 12505)
        #expect(tally[nil] == 87756 - 12511)
    }

    /// Regression (issue #9 acceptance): unpainted corpus projects keep
    /// exposing no paint data.
    @Test(.enabled(if: Corpus.has("slicer-projects/synthetic_multiplate.3mf")))
    func unpaintedProjectExposesNoPaintData() throws {
        let doc = try ThreeMFParser().parse(
            fileAt: Corpus.url("slicer-projects/synthetic_multiplate.3mf"))
        for object in doc.objects {
            #expect(object.mesh?.trianglePaintFilamentIndices == nil)
        }
    }

    // MARK: Fixture plumbing

    private static let rels = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
     <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
    Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
    </Relationships>
    """

    /// A one-object package with one triangle per entry of `paints` (nil =
    /// no `paint_color` attribute), all sharing four vertices.
    private func writePackage(paints: [String?]) throws -> URL {
        let triangles = paints.map { paint in
            let attribute = paint.map { " paint_color=\"\($0)\"" } ?? ""
            return "     <triangle v1=\"0\" v2=\"1\" v3=\"2\"\(attribute)/>"
        }.joined(separator: "\n")
        let model = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <object id="1" type="model">
           <mesh>
            <vertices>
             <vertex x="0" y="0" z="0"/>
             <vertex x="10" y="0" z="0"/>
             <vertex x="0" y="10" z="0"/>
             <vertex x="0" y="0" z="10"/>
            </vertices>
            <triangles>
        \(triangles)
            </triangles>
           </mesh>
          </object>
         </resources>
         <build>
          <item objectid="1"/>
         </build>
        </model>
        """
        return try writeTemporaryPackage(named: "paint-seam", parts: [
            ("_rels/.rels", Data(Self.rels.utf8)),
            ("3D/3dmodel.model", Data(model.utf8)),
        ])
    }
}
