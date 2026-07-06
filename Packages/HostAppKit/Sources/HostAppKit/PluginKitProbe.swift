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
        guard let output = await Self.pluginKitMatchOutput(forIdentifier: identifier) else {
            return .unknown
        }
        return PluginKitElection.enablement(ofIdentifier: identifier, inMatchOutput: output)
    }

    /// The raw stdout of `pluginkit -m -i <identifier>`, or nil if the query
    /// could not run at all. An unregistered identifier legitimately produces
    /// empty output, which the election parser reports as `.notRegistered`.
    private static func pluginKitMatchOutput(forIdentifier identifier: String) async -> String? {
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
                continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
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
