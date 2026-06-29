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

    private enum UTM {
        static let source = "withoutbg-mac-desktop"
        static let medium = "mac-app"
        static let campaign = "in-app-links"
    }

    private static func load() -> ProductLinks {
        let links: ProductLinks
        if
            let url = Bundle.main.url(forResource: "product-links", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(ProductLinks.self, from: data)
        {
            links = decoded
        } else {
            // Fallback mirrors the bundled JSON so the app never crashes if the
            // resource is missing.
            links = ProductLinks(
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
        return links.taggedForAnalytics()
    }

    private func taggedForAnalytics() -> ProductLinks {
        ProductLinks(
            website: Self.withUTM(website),
            openWeights: Self.withUTM(openWeights),
            api: Self.withUTM(api),
            benchmarks: Self.withUTM(benchmarks),
            github: github,
            license: Self.withUTM(license),
            support: Self.withUTM(support),
            ossRepo: ossRepo,
            dinov3Repo: dinov3Repo,
            dinov3License: dinov3License
        )
    }

    private static func withUTM(_ url: URL) -> URL {
        guard url.host?.hasSuffix("withoutbg.com") == true else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "utm_source", value: UTM.source),
            URLQueryItem(name: "utm_medium", value: UTM.medium),
            URLQueryItem(name: "utm_campaign", value: UTM.campaign),
        ])
        components.queryItems = queryItems
        return components.url ?? url
    }
}
