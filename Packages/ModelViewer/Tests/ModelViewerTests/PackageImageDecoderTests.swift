import AppKit
import Foundation
import Testing
@testable import ModelViewer

/// Image-bomb defense (issue #10): package-supplied image bytes — Embedded
/// Thumbnails, Plate Thumbnails — decode only when their declared pixel
/// dimensions are sane. A tiny PNG whose header declares a gigapixel canvas
/// must be rejected from the header alone, never expanded.
@Suite struct PackageImageDecoderTests {

    @Test func smallValidPNGDecodes() throws {
        let image = try #require(PackageImageDecoder.nsImage(from: Self.solidPNG(width: 4, height: 4)))
        #expect(image.size.width == 4)
        #expect(image.size.height == 4)
    }

    @Test func gigapixelPNGHeaderIsRejected() {
        // ~100 bytes on disk, 100_000 × 100_000 declared: a 40 GB RGBA
        // decode if trusted. The decoder must return nil.
        let bomb = Self.craftedPNG(declaredWidth: 100_000, declaredHeight: 100_000)
        #expect(PackageImageDecoder.nsImage(from: bomb) == nil)
        #expect(PackageImageDecoder.cgImage(from: bomb) == nil)
    }

    @Test func oversizedSingleSideIsRejected() {
        // One sane side does not excuse the other.
        let wide = Self.craftedPNG(declaredWidth: 50_000, declaredHeight: 2)
        #expect(PackageImageDecoder.cgImage(from: wide) == nil)
    }

    @Test func garbageBytesAreRejected() {
        #expect(PackageImageDecoder.nsImage(from: Data(repeating: 0xAB, count: 512)) == nil)
        #expect(PackageImageDecoder.nsImage(from: Data()) == nil)
    }

    // MARK: PNG fixtures

    /// A real solid-white PNG rendered through AppKit.
    private static func solidPNG(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for x in 0..<width {
            for y in 0..<height {
                rep.setColor(.white, atX: x, y: y)
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }

    /// A hand-built PNG whose IHDR declares arbitrary dimensions with only a
    /// stub of pixel data behind it — the shape of a real image bomb.
    private static func craftedPNG(declaredWidth: UInt32, declaredHeight: UInt32) -> Data {
        func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            let typeBytes = Array(type.utf8)
            var out = withUnsafeBytes(of: UInt32(payload.count).bigEndian, Array.init)
            out += typeBytes + payload
            out += withUnsafeBytes(of: crc32(typeBytes + payload).bigEndian, Array.init)
            return out
        }
        var ihdr = withUnsafeBytes(of: declaredWidth.bigEndian, Array.init)
        ihdr += withUnsafeBytes(of: declaredHeight.bigEndian, Array.init)
        ihdr += [8, 0, 0, 0, 0]  // 8-bit grayscale, deflate, standard filter, no interlace
        // An empty zlib deflate stream: nowhere near enough pixel data, which
        // is the point — bombs lie.
        let idat: [UInt8] = [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", ihdr)
        png += chunk("IDAT", idat)
        png += chunk("IEND", [])
        return Data(png)
    }

    /// Plain table-less CRC-32 (the PNG polynomial), enough for fixtures.
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}
