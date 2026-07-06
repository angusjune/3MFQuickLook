/// Interprets `pluginkit -m` match output.
///
/// Each match line carries an election marker in column 0 — `+` elected,
/// `-` explicitly rejected, `!` problem, space for "no explicit election"
/// (the default policy, under which macOS runs Quick Look extensions) —
/// followed by whitespace and `identifier(version)`. No matching line means
/// the extension is not registered.
public enum PluginKitElection {
    public static func enablement(
        ofIdentifier identifier: String,
        inMatchOutput output: String
    ) -> ExtensionEnablement {
        var best = ExtensionEnablement.notRegistered
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            guard body.prefix(while: { $0 != "(" }) == identifier else { continue }
            let enablement: ExtensionEnablement =
                switch marker {
                case "+", " ": .enabled
                case "-": .disabled
                default: .problem
                }
            if rank(enablement) > rank(best) { best = enablement }
        }
        return best
    }

    /// Stale duplicate registrations (a debug build plus an installed copy)
    /// can disagree; elections apply to the identifier as a whole, so the
    /// most-enabled record wins.
    private static func rank(_ enablement: ExtensionEnablement) -> Int {
        switch enablement {
        case .enabled: 3
        case .disabled: 2
        case .problem: 1
        case .notRegistered, .unknown: 0
        }
    }
}
