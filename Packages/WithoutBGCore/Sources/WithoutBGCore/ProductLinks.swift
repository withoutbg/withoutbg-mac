import Foundation

/// External links loaded from bundled `product-links.json`.
public struct ProductLinks: Decodable, Sendable {
    public let website: URL
    public let openWeights: URL
    public let api: URL
    public let apiSignup: URL
    public let documentation: URL
    public let benchmarks: URL
    public let github: URL
    public let license: URL
    public let support: URL
    public let gpuFund: URL
    public let enterprise: URL
    public let productUpdates: URL
    public let privacyPolicy: URL
    public let ossRepo: URL
    public let dinov3Repo: URL
    public let dinov3License: URL
    public let macApp: URL
    public let localAPIDocs: URL
    public let localAPIOpenAPI: URL
    public let localAPIGitHub: URL

    private static var configuredUTMSource = "withoutbg-mac-desktop"
    private static var configuredUTMMedium = "mac-app"
    private static var configuredUTMCampaign = "in-app-links"

    public static func configure(
        utmSource: String,
        utmMedium: String = "mac-app",
        utmCampaign: String = "in-app-links"
    ) {
        configuredUTMSource = utmSource
        configuredUTMMedium = utmMedium
        configuredUTMCampaign = utmCampaign
        _shared = load()
    }

    private static var _shared: ProductLinks = load()
    public static var shared: ProductLinks { _shared }

    public var supportFromSettings: URL {
        support.appendingQueryItems([
            URLQueryItem(name: "utm_source", value: Self.configuredUTMSource),
            URLQueryItem(name: "utm_medium", value: Self.configuredUTMMedium),
            URLQueryItem(name: "utm_campaign", value: "settings"),
        ])
    }

    /// OpenAPI spec URL for the running local server (bundled route when server is up).
    public func localOpenAPIURL(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)/openapi.json")!
    }

    private static func load() -> ProductLinks {
        let links: ProductLinks
        if
            let url = WithoutBGCoreResources.url(forResource: "product-links", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(ProductLinks.self, from: data)
        {
            links = decoded
        } else {
            links = ProductLinks.fallback
        }
        return links.taggedForAnalytics()
    }

    private static let fallback = ProductLinks(
        website: URL(string: "https://withoutbg.com")!,
        openWeights: URL(string: "https://withoutbg.com/open-model")!,
        api: URL(string: "https://withoutbg.com/pro-model")!,
        apiSignup: URL(string: "https://withoutbg.com/signup")!,
        documentation: URL(string: "https://withoutbg.com/docs")!,
        benchmarks: URL(string: "https://withoutbg.com/open-model/results")!,
        github: URL(string: "https://github.com/withoutbg/withoutbg")!,
        license: URL(string: "https://withoutbg.com/open-model/license")!,
        support: URL(string: "https://withoutbg.com/open-model/support")!,
        gpuFund: URL(string: "https://withoutbg.com/open-model/support/gpu-fund")!,
        enterprise: URL(string: "https://withoutbg.com/contact")!,
        productUpdates: URL(string: "https://api.withoutbg.com/updates")!,
        privacyPolicy: URL(string: "https://withoutbg.com/privacy")!,
        ossRepo: URL(string: "https://github.com/withoutbg/withoutbg")!,
        dinov3Repo: URL(string: "https://github.com/facebookresearch/dinov3")!,
        dinov3License: URL(string: "https://ai.meta.com/resources/models-and-libraries/dinov3-license/")!,
        macApp: URL(string: "https://withoutbg.com/mac")!,
        localAPIDocs: URL(string: "https://withoutbg.com/docs/open-model/local-api")!,
        localAPIOpenAPI: URL(string: "https://withoutbg.com/openapi/local-api.json")!,
        localAPIGitHub: URL(string: "https://github.com/withoutbg/withoutbg-mac")!
    )

    private func taggedForAnalytics() -> ProductLinks {
        ProductLinks(
            website: Self.withUTM(website),
            openWeights: Self.withUTM(openWeights),
            api: Self.withUTM(api),
            apiSignup: Self.withUTM(apiSignup),
            documentation: Self.withUTM(documentation),
            benchmarks: Self.withUTM(benchmarks),
            github: github,
            license: Self.withUTM(license),
            support: Self.withUTM(support),
            gpuFund: Self.withUTM(gpuFund),
            enterprise: Self.withUTM(enterprise),
            productUpdates: productUpdates,
            privacyPolicy: Self.withUTM(privacyPolicy),
            ossRepo: ossRepo,
            dinov3Repo: dinov3Repo,
            dinov3License: dinov3License,
            macApp: Self.withUTM(macApp),
            localAPIDocs: Self.withUTM(localAPIDocs),
            localAPIOpenAPI: localAPIOpenAPI,
            localAPIGitHub: localAPIGitHub
        )
    }

    private static func withUTM(_ url: URL) -> URL {
        guard url.host?.hasSuffix("withoutbg.com") == true else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: [
            URLQueryItem(name: "utm_source", value: configuredUTMSource),
            URLQueryItem(name: "utm_medium", value: configuredUTMMedium),
            URLQueryItem(name: "utm_campaign", value: configuredUTMCampaign),
        ])
        components.queryItems = queryItems
        return components.url ?? url
    }
}

private extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var queryItems = components.queryItems ?? []
        queryItems.append(contentsOf: items)
        components.queryItems = queryItems
        return components.url ?? self
    }
}
