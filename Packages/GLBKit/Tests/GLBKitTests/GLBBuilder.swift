import Foundation
import simd

/// Assembles GLB bytes for tests: a JSON chunk from a dictionary, an
/// optional BIN chunk, and the 12-byte header around them. Written by hand
/// rather than exported, so a test can describe exactly the file it needs —
/// including the malformed ones no real exporter would produce.
enum GLBBuilder {
    static let magic: UInt32 = 0x46546C67
    static let jsonChunkType: UInt32 = 0x4E4F534A
    static let binaryChunkType: UInt32 = 0x004E4942

    static func glb(json: [String: Any], binary: Data? = nil, version: UInt32 = 2) -> Data {
        let jsonData = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        var chunks = chunk(jsonData, type: jsonChunkType, padding: 0x20)
        if let binary {
            chunks += chunk(binary, type: binaryChunkType, padding: 0)
        }

        var data = Data()
        data.append(uint32: magic)
        data.append(uint32: version)
        data.append(uint32: UInt32(12 + chunks.count))
        data.append(chunks)
        return data
    }

    private static func chunk(_ payload: Data, type: UInt32, padding: UInt8) -> Data {
        var padded = payload
        while !padded.count.isMultiple(of: 4) { padded.append(padding) }
        var chunk = Data()
        chunk.append(uint32: UInt32(padded.count))
        chunk.append(uint32: type)
        chunk.append(padded)
        return chunk
    }

    // MARK: Common fixtures

    /// A single triangle in the XY plane, one node, one scene — the smallest
    /// file that renders. `extraJSON` merges over the top so a test can vary
    /// one thing about it.
    static func triangle(
        positions: [SIMD3<Float>] = [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0),
        ],
        indices: [UInt16] = [0, 1, 2],
        node: [String: Any] = ["mesh": 0],
        primitive: [String: Any] = [:],
        extraJSON: [String: Any] = [:],
        trailingBinary: Data = Data()
    ) -> Data {
        var binary = Data()
        for position in positions {
            binary.append(float: position.x)
            binary.append(float: position.y)
            binary.append(float: position.z)
        }
        let indexOffset = binary.count
        for index in indices { binary.append(uint16: index) }
        while !binary.count.isMultiple(of: 4) { binary.append(0) }
        // Anything a test wants after the geometry — texture images, most
        // often — starts at this padded offset.
        binary.append(trailingBinary)

        var mergedPrimitive: [String: Any] = ["attributes": ["POSITION": 0], "indices": 1]
        mergedPrimitive.merge(primitive) { _, new in new }

        var json: [String: Any] = [
            "asset": ["version": "2.0"],
            "scene": 0,
            "scenes": [["nodes": [0]]],
            "nodes": [node],
            "meshes": [["primitives": [mergedPrimitive]]],
            "accessors": [
                [
                    "bufferView": 0, "componentType": 5126,
                    "count": positions.count, "type": "VEC3",
                ],
                [
                    "bufferView": 1, "componentType": 5123,
                    "count": indices.count, "type": "SCALAR",
                ],
            ],
            "bufferViews": [
                ["buffer": 0, "byteOffset": 0, "byteLength": indexOffset],
                [
                    "buffer": 0, "byteOffset": indexOffset,
                    "byteLength": indices.count * 2,
                ],
            ],
            "buffers": [["byteLength": binary.count]],
        ]
        json.merge(extraJSON) { _, new in new }
        return glb(json: json, binary: binary)
    }

    /// A 1×1 opaque red PNG, for texture-carrying tests.
    static let pngPixel = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!
}

extension Data {
    fileprivate mutating func append(uint32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(uint16 value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(float value: Float) {
        Swift.withUnsafeBytes(of: value.bitPattern.littleEndian) { append(contentsOf: $0) }
    }
}
