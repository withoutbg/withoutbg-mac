import Foundation

/// Static external links, loaded once from `product-links.json`. Single source
/// for every URL used in Help, About and Settings.
struct ProductLinks: Decodable {
    let website: URL
    let api: URL
    let benchmarks: URL
    let github: URL
    let license: URL
    let ossRepo: URL

    static let shared: ProductLinks = load()

    private static func load() -> ProductLinks {
        guard
            let url = Bundle.main.url(forResource: "product-links", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(ProductLinks.self, from: data)
        else {
            // Fallback mirrors the bundled JSON so the app never crashes if the
            // resource is missing.
            return ProductLinks(
                website: URL(string: "https://withoutbg.com")!,
                api: URL(string: "https://withoutbg.com/docs/api-model")!,
                benchmarks: URL(string: "https://withoutbg.com/open-weight-model/results")!,
                github: URL(string: "https://github.com/withoutbg/withoutbg")!,
                license: URL(string: "https://withoutbg.com/open-weight-model/license")!,
                ossRepo: URL(string: "https://github.com/withoutbg/withoutbg")!
            )
        }
        return decoded
    }
}
