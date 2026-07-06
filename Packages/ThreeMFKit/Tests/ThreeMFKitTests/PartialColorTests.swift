import Foundation
import Testing
import ThreeMFKit
import ZIPFoundation

/// A mesh where only some triangles carry color properties (the painted-model
/// shape): colored triangles keep their file colors, uncolored ones stay
/// colorless — the parser must not throw the partial colors away.
@Suite struct PartialColorTests {

    @Test func partiallyColoredMeshKeepsItsResolvedTriangleColors() throws {
        let model = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" \
        xmlns:m="http://schemas.microsoft.com/3dmanufacturing/material/2015/02">
         <resources>
          <m:colorgroup id="7">
           <m:color color="#FF0000FF"/>
           <m:color color="#00FF00FF"/>
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
             <triangle v1="0" v2="1" v3="3"/>
             <triangle v1="0" v2="3" v3="2" pid="7" p1="1"/>
             <triangle v1="1" v2="2" v3="3"/>
            </triangles>
           </mesh>
          </object>
         </resources>
         <build>
          <item objectid="1"/>
         </build>
        </model>
        """
        let url = try writePackage(modelXML: model)
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = try ThreeMFParser().parse(fileAt: url)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.triangleCount == 4)
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let green = ColorRGBA(red: 0, green: 255, blue: 0)
        #expect(mesh.triangleColors == [red, nil, green, nil])
    }

    /// Writes a minimal one-part 3MF package around the given model XML.
    private func writePackage(modelXML: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial-color-\(UUID().uuidString)")
            .appendingPathExtension("3mf")
        let archive = try Archive(url: url, accessMode: .create)
        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
         <Relationship Target="/3D/3dmodel.model" Id="rel-1" \
        Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
        """
        for (path, text) in [("_rels/.rels", rels), ("3D/3dmodel.model", modelXML)] {
            let data = Data(text.utf8)
            try archive.addEntry(
                with: path, type: .file, uncompressedSize: Int64(data.count),
                provider: { position, size in
                    data.subdata(in: Int(position)..<Int(position) + size)
                })
        }
        return url
    }
}
