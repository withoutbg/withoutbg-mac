import Foundation

enum WithoutBGCoreResources {
    private static let resourceBundleName = "WithoutBGCore_WithoutBGCore"

    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        if let resourceURL = Bundle.main.resourceURL {
            let nested = resourceURL.appendingPathComponent("\(resourceBundleName).bundle")
            if let nestedBundle = Bundle(url: nested),
               let url = nestedBundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return Bundle.main.url(forResource: name, withExtension: ext)
    }
}
