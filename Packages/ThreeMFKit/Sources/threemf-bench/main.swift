import Darwin
import Foundation
import ThreeMFKit

// Parse-seam benchmark: wall time (best of N) plus the process's lifetime
// peak physical footprint. Run against a fresh process per file so the peak
// is attributable to the parse:
//
//     swift run -c release threemf-bench <file.3mf> [iterations]

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: threemf-bench <file.3mf> [iterations]\n", stderr)
    exit(2)
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let iterations = CommandLine.arguments.count > 2 ? max(Int(CommandLine.arguments[2]) ?? 1, 1) : 1

var bestSeconds = Double.infinity
var triangles = 0
var vertices = 0
for _ in 0..<iterations {
    do {
        var document: ThreeMFDocument?
        let elapsed = try ContinuousClock().measure {
            document = try ThreeMFParser().parse(fileAt: url)
        }
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) * 1e-18
        bestSeconds = min(bestSeconds, seconds)
        triangles = 0
        vertices = 0
        for object in document!.objects {
            if case .mesh(let mesh) = object.content {
                triangles += mesh.triangleCount
                vertices += mesh.positions.count
            }
        }
    } catch {
        fputs("parse failed: \(error)\n", stderr)
        exit(1)
    }
}

var usage = rusage_info_current()
let status = withUnsafeMutablePointer(to: &usage) { pointer in
    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
        proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, reboundPointer)
    }
}
let peakFootprintMB = status == 0
    ? Double(usage.ri_lifetime_max_phys_footprint) / 1_048_576
    : Double.nan

print("file: \(url.lastPathComponent)")
print("triangles: \(triangles), vertices: \(vertices)")
print(String(format: "parse time (best of %d): %.3f s", iterations, bestSeconds))
print(String(format: "peak physical footprint: %.0f MB", peakFootprintMB))
