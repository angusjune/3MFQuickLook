import Foundation
import simd
import Testing
import ThreeMFKit

/// Seam tests for the Info Line data (issue #7): given a document, it
/// exposes these staged bounding dimensions, object counts, and used
/// filaments. Documents are hand-built — the metrics are pure functions of
/// the domain model; corpus files cross the parse boundary in
/// SlicerProjectSeamTests.
@Suite struct SceneMetricsTests {

    private static let rootPart = "/3D/3dmodel.model"

    private static func ref(_ id: UInt32, part: String = rootPart) -> ResourceRef {
        ResourceRef(partPath: part, id: id)
    }

    /// An axis-aligned cube [0, size]^3: 8 vertices, 12 triangles.
    private static func cubeMesh(size: Float = 10) -> Mesh {
        var positions: [SIMD3<Float>] = []
        for z: Float in [0, 1] {
            for y: Float in [0, 1] {
                for x: Float in [0, 1] {
                    positions.append(SIMD3(x, y, z) * size)
                }
            }
        }
        let triangles: [UInt32] = [
            0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6,
            0, 1, 4, 1, 5, 4, 2, 6, 3, 3, 6, 7,
            0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5,
        ]
        return Mesh(positions: positions, triangleIndices: triangles)
    }

    private static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(x, y, z, 1)
        return matrix
    }

    private static func cubeObject(_ id: UInt32, size: Float = 10) -> ObjectResource {
        ObjectResource(ref: ref(id), content: .mesh(cubeMesh(size: size)))
    }

    // MARK: Dimensions and object count

    @Test func cubeSpansItsEdgeLength() {
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        let metrics = doc.sceneMetrics()
        #expect(metrics.sizeMillimeters == SIMD3(10, 10, 10))
        #expect(metrics.objectCount == 1)
    }

    @Test func translationMovesWithoutResizing() {
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1), transform: Self.translation(80, 80, 0))])
        #expect(doc.sceneMetrics().sizeMillimeters == SIMD3(10, 10, 10))
    }

    @Test func twoItemsSpanTheirCombinedArrangement() {
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [
                BuildItem(objectRef: Self.ref(1)),
                BuildItem(objectRef: Self.ref(1), transform: Self.translation(30, 0, 0)),
            ])
        let metrics = doc.sceneMetrics()
        #expect(metrics.sizeMillimeters == SIMD3(40, 10, 10))
        #expect(metrics.objectCount == 2)
    }

    @Test func rotationIsMeasuredFromTransformedVertices() throws {
        // 45° about Z: the cube's XY footprint becomes its diagonal, 10√2.
        // Corner-of-AABB approximations would report the same for 90°; exact
        // vertex transforms are required to get √2 here and 10 at 90°.
        let angle = Float.pi / 4
        var rotation = matrix_identity_float4x4
        rotation.columns.0 = SIMD4(cos(angle), sin(angle), 0, 0)
        rotation.columns.1 = SIMD4(-sin(angle), cos(angle), 0, 0)
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1), transform: rotation)])
        let size = try #require(doc.sceneMetrics().sizeMillimeters)
        let diagonal = 10 * Float(2).squareRoot()
        #expect(abs(size.x - diagonal) < 0.001)
        #expect(abs(size.y - diagonal) < 0.001)
        #expect(size.z == 10)
    }

    @Test func sizeConvertsModelUnitsToMillimeters() throws {
        let doc = ThreeMFDocument(
            unit: .inch,
            objects: [Self.cubeObject(1, size: 1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        let size = try #require(doc.sceneMetrics().sizeMillimeters)
        #expect(abs(size.x - 25.4) < 0.001)
    }

    @Test func emptyDocumentHasNoSizeAndZeroObjects() {
        let metrics = ThreeMFDocument().sceneMetrics()
        #expect(metrics.sizeMillimeters == nil)
        #expect(metrics.objectCount == 0)
    }

    @Test func meshObjectsWithoutBuildItemsStillMeasure() {
        // Lenient fallback mirroring the scene: no build items → stage the
        // mesh objects themselves.
        let doc = ThreeMFDocument(objects: [Self.cubeObject(1)])
        let metrics = doc.sceneMetrics()
        #expect(metrics.sizeMillimeters == SIMD3(10, 10, 10))
        #expect(metrics.objectCount == 1)
    }

    @Test func componentTransformsCompound() {
        // Object 4 = cube + the same cube lifted 15: spans z 0…25.
        let composite = ObjectResource(ref: Self.ref(4), content: .components([
            Component(objectRef: Self.ref(1)),
            Component(objectRef: Self.ref(1), transform: Self.translation(0, 0, 15)),
        ]))
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1), composite],
            buildItems: [BuildItem(objectRef: Self.ref(4), transform: Self.translation(75, 75, 0))])
        let metrics = doc.sceneMetrics()
        #expect(metrics.sizeMillimeters == SIMD3(10, 10, 25))
        #expect(metrics.objectCount == 1)
    }

    // MARK: Plate staging

    private static func twoPlateDocument() -> ThreeMFDocument {
        ThreeMFDocument(
            objects: [Self.cubeObject(1), Self.cubeObject(2, size: 20)],
            buildItems: [
                BuildItem(objectRef: Self.ref(1)),
                BuildItem(objectRef: Self.ref(2), transform: Self.translation(50, 0, 0)),
            ],
            slicerProject: SlicerProjectInfo(plates: [
                Plate(id: 1, objectRefs: [Self.ref(1)]),
                Plate(id: 2, objectRefs: [Self.ref(2)]),
                Plate(id: 3),
            ]))
    }

    @Test func metricsFollowTheRequestedPlate() {
        let doc = Self.twoPlateDocument()
        let plates = doc.slicerProject!.plates
        #expect(doc.sceneMetrics(for: plates[0]).sizeMillimeters == SIMD3(10, 10, 10))
        #expect(doc.sceneMetrics(for: plates[1]).sizeMillimeters == SIMD3(20, 20, 20))
        #expect(doc.sceneMetrics(for: plates[1]).objectCount == 1)
    }

    @Test func defaultPlateMetricsMatchTheDefaultScene() {
        // No plate given → the default Plate (first with objects), exactly
        // what the scene shows.
        let doc = Self.twoPlateDocument()
        #expect(doc.sceneMetrics() == doc.sceneMetrics(for: doc.slicerProject?.defaultPlate))
    }

    @Test func emptyPlateHasZeroObjectsAndNoSize() {
        let doc = Self.twoPlateDocument()
        let metrics = doc.sceneMetrics(for: doc.slicerProject!.plates[2])
        #expect(metrics.sizeMillimeters == nil)
        #expect(metrics.objectCount == 0)
    }

    @Test func plateAssignmentsMatchingNoItemsFallBackToTheWholeBuild() {
        // Lenient: a broken config must not empty the preview — or its
        // Info Line.
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        let orphanPlate = Plate(id: 9, objectRefs: [Self.ref(99)])
        let metrics = doc.sceneMetrics(for: orphanPlate)
        #expect(metrics.sizeMillimeters == SIMD3(10, 10, 10))
        #expect(metrics.objectCount == 1)
    }

    // MARK: Used filaments

    private static func slicerDocument(
        filaments: [Filament],
        filamentIndexByObject: [ResourceRef: Int] = [:],
        plates: [Plate] = [],
        objects: [ObjectResource],
        buildItems: [BuildItem]
    ) -> ThreeMFDocument {
        ThreeMFDocument(
            objects: objects,
            buildItems: buildItems,
            slicerProject: SlicerProjectInfo(
                filaments: filaments,
                plates: plates,
                filamentIndexByObject: filamentIndexByObject))
    }

    private static let twoFilaments = [
        Filament(color: ColorRGBA(red: 255, green: 0, blue: 0), type: "PLA"),
        Filament(color: ColorRGBA(red: 0, green: 255, blue: 0), type: "PETG"),
    ]

    @Test func vanillaFileUsesNoFilaments() {
        let doc = ThreeMFDocument(
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        #expect(doc.usedFilamentIndices() == [])
    }

    @Test func unassignedObjectsPrintOnFilamentZero() {
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        #expect(doc.usedFilamentIndices() == [0])
    }

    @Test func objectAssignmentsCollectSortedAndUnique() {
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            filamentIndexByObject: [Self.ref(1): 1, Self.ref(2): 1],
            objects: [Self.cubeObject(1), Self.cubeObject(2)],
            buildItems: [
                BuildItem(objectRef: Self.ref(1)),
                BuildItem(objectRef: Self.ref(2)),
            ])
        #expect(doc.usedFilamentIndices() == [1])
    }

    @Test func partLevelOverridesAddTheirFilament() {
        // The synthetic_multiplate plate-3 shape: object on filament 1, one
        // component part overridden to filament 0.
        let partRef = Self.ref(2, part: "/3D/Objects/object_2.model")
        let bodyRef = Self.ref(1, part: "/3D/Objects/object_2.model")
        let composite = ObjectResource(ref: Self.ref(4), content: .components([
            Component(objectRef: bodyRef),
            Component(objectRef: partRef),
        ]))
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            filamentIndexByObject: [Self.ref(4): 1, partRef: 0],
            objects: [
                ObjectResource(ref: bodyRef, content: .mesh(Self.cubeMesh())),
                ObjectResource(ref: partRef, content: .mesh(Self.cubeMesh())),
                composite,
            ],
            buildItems: [BuildItem(objectRef: Self.ref(4))])
        #expect(doc.usedFilamentIndices() == [0, 1])
    }

    @Test func filamentsFollowTheRequestedPlate() {
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            filamentIndexByObject: [Self.ref(1): 0, Self.ref(2): 1],
            plates: [
                Plate(id: 1, objectRefs: [Self.ref(1)]),
                Plate(id: 2, objectRefs: [Self.ref(2)]),
            ],
            objects: [Self.cubeObject(1), Self.cubeObject(2)],
            buildItems: [
                BuildItem(objectRef: Self.ref(1)),
                BuildItem(objectRef: Self.ref(2)),
            ])
        let plates = doc.slicerProject!.plates
        #expect(doc.usedFilamentIndices(for: plates[0]) == [0])
        #expect(doc.usedFilamentIndices(for: plates[1]) == [1])
    }

    @Test func recordedPlateFilamentsWinOverDerivation() {
        // A sliced plate records its filaments in slice_info.config — that
        // list is authoritative (it sees paint colors derivation can't).
        let plate = Plate(id: 1, objectRefs: [Self.ref(1)], usedFilamentIndices: [1])
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            filamentIndexByObject: [Self.ref(1): 0],
            plates: [plate],
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        #expect(doc.usedFilamentIndices(for: plate) == [1])
    }

    @Test func outOfRangeIndicesFallBackToFilamentZero() {
        // Matches SlicerProjectInfo.filamentColor's slicer-compatible
        // fallback.
        let doc = Self.slicerDocument(
            filaments: Self.twoFilaments,
            filamentIndexByObject: [Self.ref(1): 7],
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        #expect(doc.usedFilamentIndices() == [0])
    }

    @Test func projectWithoutFilamentDefinitionsUsesNone() {
        let doc = Self.slicerDocument(
            filaments: [],
            filamentIndexByObject: [Self.ref(1): 0],
            objects: [Self.cubeObject(1)],
            buildItems: [BuildItem(objectRef: Self.ref(1))])
        #expect(doc.usedFilamentIndices() == [])
    }
}
