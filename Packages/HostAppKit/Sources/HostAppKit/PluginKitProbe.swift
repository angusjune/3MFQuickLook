import Foundation

/// Queries PluginKit (via `/usr/bin/pluginkit -m -i`, a read-only match) for
/// the current election of each Quick Look extension.
public struct PluginKitProbe: ExtensionStatusProbing {
    public var previewExtensionIdentifier: String
    public var thumbnailExtensionIdentifier: String

    public init(previewExtensionIdentifier: String, thumbnailExtensionIdentifier: String) {
        self.previewExtensionIdentifier = previewExtensionIdentifier
        self.thumbnailExtensionIdentifier = thumbnailExtensionIdentifier
    }

    public func status() async -> QuickLookExtensionStatus {
        async let preview = enablement(ofIdentifier: previewExtensionIdentifier)
        async let thumbnail = enablement(ofIdentifier: thumbnailExtensionIdentifier)
        return await QuickLookExtensionStatus(preview: preview, thumbnail: thumbnail)
    }

    private func enablement(ofIdentifier identifier: String) async -> ExtensionEnablement {
        guard let result = await Self.runPluginKitMatch(forIdentifier: identifier) else {
            return .unknown
        }
        return Self.interpret(
            exitStatus: result.exitStatus, output: result.output, forIdentifier: identifier)
    }

    /// Maps one `pluginkit -m -i <identifier>` run to an enablement.
    ///
    /// A clean exit with no output is how pluginkit reports "not registered";
    /// a failure exit means the query itself was refused — notably, pkd denies
    /// discovery to sandboxed callers ("unauthorized discovery flag") — which
    /// must read as "couldn't determine", never as "not registered".
    public static func interpret(
        exitStatus: Int32,
        output: String,
        forIdentifier identifier: String
    ) -> ExtensionEnablement {
        guard exitStatus == 0 else { return .unknown }
        return PluginKitElection.enablement(ofIdentifier: identifier, inMatchOutput: output)
    }

    private static func runPluginKitMatch(
        forIdentifier identifier: String
    ) async -> (exitStatus: Int32, output: String)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
            process.arguments = ["-m", "-i", identifier]
            process.standardOutput = Pipe()
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                // Match output for a single identifier is at most a few lines,
                // far below the pipe buffer, so reading after exit is safe.
                let data = (process.standardOutput as? Pipe)?
                    .fileHandleForReading.readDataToEndOfFile() ?? Data()
                continuation.resume(returning: (
                    exitStatus: process.terminationStatus,
                    output: String(data: data, encoding: .utf8) ?? ""))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
