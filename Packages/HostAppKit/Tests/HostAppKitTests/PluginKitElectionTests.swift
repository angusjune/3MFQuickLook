import Testing
import HostAppKit

/// `pluginkit -m -i <id>` output, as captured on macOS 15/26:
/// an election marker in column 0 (`+` elected, `-` rejected, `!` problem,
/// space for "no explicit election"), whitespace, then `identifier(version)`.
/// No output at all means the extension is not registered.
@Suite struct PluginKitElectionTests {
    private let preview = "com.angusjune.ThreeMFQuickLook.PreviewExt"

    private func enablement(of identifier: String, in output: String) -> ExtensionEnablement {
        PluginKitElection.enablement(ofIdentifier: identifier, inMatchOutput: output)
    }

    @Test func electedMarkerMeansEnabled() {
        let output = "+    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)\n"
        #expect(enablement(of: preview, in: output) == .enabled)
    }

    /// A space marker means "no explicit election" — the default policy, under
    /// which macOS runs Quick Look extensions (verified: this machine serves
    /// thumbnails from an extension pluginkit lists with a space marker).
    @Test func defaultElectionMeansEnabled() {
        let output = "     com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)\n"
        #expect(enablement(of: preview, in: output) == .enabled)
    }

    @Test func rejectedMarkerMeansDisabled() {
        let output = "-    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)\n"
        #expect(enablement(of: preview, in: output) == .disabled)
    }

    @Test func problemMarkerMeansProblem() {
        let output = "!    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)\n"
        #expect(enablement(of: preview, in: output) == .problem)
    }

    @Test(arguments: ["", "\n"])
    func noOutputMeansNotRegistered(output: String) {
        #expect(enablement(of: preview, in: output) == .notRegistered)
    }

    @Test func otherIdentifiersDoNotMatch() {
        let output = "+    com.angusjune.ThreeMFQuickLook.ThumbExt(1.0)\n"
        #expect(enablement(of: preview, in: output) == .notRegistered)
    }

    @Test func identifierMatchIsExactNotPrefix() {
        let output = "+    com.angusjune.ThreeMFQuickLook.PreviewExtra(1.0)\n"
        #expect(enablement(of: preview, in: output) == .notRegistered)
    }

    /// Stale duplicate registrations (a DerivedData build plus /Applications)
    /// can disagree; any elected record counts, since elections apply to the
    /// identifier as a whole.
    @Test func duplicateRecordsPreferTheElectedOne() {
        let output = """
            -    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)
            +    com.angusjune.ThreeMFQuickLook.PreviewExt(1.1)

            """
        #expect(enablement(of: preview, in: output) == .enabled)
    }

    @Test func duplicateRecordsPreferDisabledOverProblem() {
        let output = """
            !    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)
            -    com.angusjune.ThreeMFQuickLook.PreviewExt(1.1)

            """
        #expect(enablement(of: preview, in: output) == .disabled)
    }

    @Test func surroundingUnrelatedLinesAreIgnored() {
        let output = """
                 com.apple.Safari.SafariQuickLookPreview(26.5)
            -    com.angusjune.ThreeMFQuickLook.PreviewExt(1.0)
            +    com.apple.SceneKitQLPreviewExtension(1.0)

            """
        #expect(enablement(of: preview, in: output) == .disabled)
    }
}
