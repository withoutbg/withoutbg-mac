import Foundation

/// How the app identifies itself to withoutbg.com services.
///
/// `withoutbg-mac/1.3 (macOS 15.1; arm64)`. The API parses the
/// `withoutbg-<client>/<version>` prefix to split traffic per client. Holds no
/// user or machine identifiers.
public enum ClientIdentity {
    public static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        return "withoutbg-mac/\(version) (macOS \(osVersion); \(architecture))"
    }

    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
