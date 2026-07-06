import Foundation
import simd
import Testing
import ThreeMFKit

/// Parse-seam corpus tests: given a corpus file, the document contains these
/// objects, meshes, transforms, and colors. Ground truth for every expected
/// value comes from independent inspection of the files (Python ElementTree /
/// text dumps), not from this parser.
@Suite struct ParseSeamCorpusTests {

    @Test(.enabled(if: Corpus.has("vanilla/box.3mf")))
    func vanillaBoxParsesUnitGeometryAndBuild() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/box.3mf"))

        #expect(doc.unit == .millimeter)
        #expect(doc.objects.count == 1)

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 8)
        #expect(mesh.triangleCount == 12)
        #expect(mesh.triangleColors == nil)

        #expect(doc.buildItems.count == 1)
        let item = try #require(doc.buildItems.first)
        #expect(item.transform == matrix_identity_float4x4)
        #expect(item.objectRef == doc.objects[0].ref)
    }

    @Test(.enabled(if: Corpus.has("vanilla/cube_gears.3mf")))
    func cubeGearsParsesSeventeenObjectsAndItemTransforms() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/cube_gears.3mf"))

        #expect(doc.objects.count == 17)
        let first = try #require(doc.objects.first?.mesh)
        #expect(first.positions.count == 1744)
        #expect(first.triangleCount == 3484)

        #expect(doc.buildItems.count == 17)
        for item in doc.buildItems {
            let translation = item.transform.columns.3
            #expect(abs(translation.x - -1.23762) < 1e-4)
            #expect(abs(translation.y - 1.20238) < 1e-4)
            #expect(abs(translation.z - -20.0108) < 1e-4)
        }
    }

    @Test(.enabled(if: Corpus.has("vanilla/pyramid_vertexcolor.3mf")))
    func pyramidResolvesPerTriangleColorGroupColors() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/pyramid_vertexcolor.3mf"))

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.triangleCount == 4)
        // p1 values 0, 2, 0, 0 into colorgroup [red, blue, green, white].
        let red = ColorRGBA(red: 255, green: 0, blue: 0)
        let green = ColorRGBA(red: 0, green: 255, blue: 0)
        #expect(mesh.triangleColors == [red, green, red, red])
    }

    @Test(.enabled(if: Corpus.has("vanilla/dodeca_chain_loop_color.3mf")))
    func dodecaChainResolvesAllNineColorGroupColors() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/dodeca_chain_loop_color.3mf"))

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 3040)
        #expect(mesh.triangleCount == 7680)
        let colors = try #require(mesh.triangleColors)
        #expect(colors.count == 7680)
        #expect(Set(colors).count == 9)
        #expect(Set(colors).contains(ColorRGBA(red: 0xFC, green: 0xDD, blue: 0x03)))
    }

    @Test(.enabled(if: Corpus.has("vanilla/synthetic_basematerials.3mf")))
    func syntheticFileResolvesBaseMaterialObjectColors() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("vanilla/synthetic_basematerials.3mf"))

        #expect(doc.objects.count == 2)
        let cube = try #require(doc.objects.first)
        #expect(cube.name == "Red Cube")
        #expect(cube.defaultColor == ColorRGBA(red: 255, green: 0, blue: 0))
        #expect(cube.mesh?.triangleCount == 12)

        let tetra = try #require(doc.objects.last)
        #expect(tetra.defaultColor == ColorRGBA(red: 0x46, green: 0x82, blue: 0xB4))
        #expect(tetra.mesh?.triangleCount == 4)

        #expect(doc.buildItems.count == 2)
        #expect(doc.buildItems[0].transform == matrix_identity_float4x4)
        #expect(doc.buildItems[1].transform.columns.3 == SIMD4(30, 0, 0, 1))
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/FlightScnr.3mf")))
    func productionExtensionResolvesMultiPartComponents() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("slicer-projects/FlightScnr.3mf"))

        // 3 component objects in the root part + 3 mesh objects across
        // 3D/Objects/object_{3,4,5}.model.
        #expect(doc.objects.count == 6)
        #expect(doc.buildItems.count == 3)

        let rootObject = try #require(doc.object(ResourceRef(partPath: "/3D/3dmodel.model", id: 2)))
        let component = try #require(rootObject.components?.first)
        #expect(component.objectRef == ResourceRef(partPath: "/3D/Objects/object_5.model", id: 1))

        let referenced = try #require(doc.object(component.objectRef)?.mesh)
        #expect(referenced.positions.count == 4032)
        #expect(referenced.triangleCount == 8064)

        let item = try #require(doc.buildItems.first)
        #expect(item.objectRef == rootObject.ref)
        let translation = item.transform.columns.3
        #expect(abs(translation.x - 167.5) < 1e-4)
        #expect(abs(translation.y - 140.80236) < 1e-4)
        #expect(abs(translation.z - 47.0781822) < 1e-4)
    }

    @Test(.enabled(if: Corpus.has("slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf")))
    func millionTriangleFileParsesWithinBaseline() throws {
        let url = Corpus.url("slicer-projects/Civilization-Atlas-Diorama-FanArt-3Dprint.3mf")

        var doc = ThreeMFDocument()
        let elapsed = try ContinuousClock().measure {
            doc = try ThreeMFParser().parse(fileAt: url)
        }

        // Root component object + two mesh objects in 3D/Objects/object_2.model.
        #expect(doc.objects.count == 3)
        let meshTriangles = doc.objects.compactMap(\.mesh).map(\.triangleCount).reduce(0, +)
        #expect(meshTriangles == 1_702_438)
        let meshVertices = doc.objects.compactMap(\.mesh).map(\.positions.count).reduce(0, +)
        #expect(meshVertices == 846_230)

        // Coarse regression guard; the recorded baseline (time and peak
        // memory) lives in docs/perf-baseline.md, measured by threemf-bench.
        #expect(elapsed < .seconds(10), "1.7M-triangle parse took \(elapsed)")
    }

    @Test(.enabled(if: Corpus.has("pathological/beamlattice_pyramid.3mf")))
    func beamLatticeFileStillYieldsCoreGeometryLeniently() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("pathological/beamlattice_pyramid.3mf"))

        // The beam-lattice extension is not implemented; its elements are
        // skipped but the core vertices survive.
        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 123)
        #expect(mesh.triangleCount == 0)
    }

    @Test(.enabled(if: Corpus.has("pathological/box_sliced.3mf")))
    func sliceExtensionFileStillYieldsCoreGeometryLeniently() throws {
        let doc = try ThreeMFParser().parse(fileAt: Corpus.url("pathological/box_sliced.3mf"))

        let mesh = try #require(doc.objects.first?.mesh)
        #expect(mesh.positions.count == 8)
        #expect(mesh.triangleCount == 12)

        let translation = try #require(doc.buildItems.first).transform.columns.3
        #expect(abs(translation.x - 33.0327) < 1e-3)
        #expect(abs(translation.y - 31.5297) < 1e-3)
        #expect(abs(translation.z - 14.9670) < 1e-3)
    }
}
