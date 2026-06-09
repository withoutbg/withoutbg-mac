import Foundation

/// Static external links, loaded once from `product-links.json`. Single source
/// for every URL used in Help, About and Settings.
struct ProductLinks: Decodable {
    let website: URL
    let openWeights: URL
    let api: URL
    let benchmarks: URL
    let github: URL
    let license: URL
    let support: URL
    let ossRepo: URL
    let dinov3Repo: URL
    let dinov3License: URL

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
                openWeights: URL(string: "https://withoutbg.com/open-weights-model")!,
                api: URL(string: "https://withoutbg.com/api-model")!,
                benchmarks: URL(string: "https://withoutbg.com/open-weights-model/results")!,
                github: URL(string: "https://github.com/withoutbg/withoutbg")!,
                license: URL(string: "https://withoutbg.com/open-weights-model/license")!,
                support: URL(string: "https://withoutbg.com/open-weights-model/support")!,
                ossRepo: URL(string: "https://github.com/withoutbg/withoutbg")!,
                dinov3Repo: URL(string: "https://github.com/facebookresearch/dinov3")!,
                dinov3License: URL(string: "https://ai.meta.com/resources/models-and-libraries/dinov3-license/")!
            )
        }
        return decoded
    }
}
