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

    // Workspace UTM convention: source = where the reader is, medium = surface kind,
    // campaign = current launch, content = which link (derived from the URL path).
    private static var configuredUTMSource = "mac-app"
    private static var configuredUTMMedium = "app"
    private static var configuredUTMCampaign = "open-weights-v4"

    public static func configure(
        utmSource: String,
        utmMedium: String = "app",
        utmCampaign: String = "open-weights-v4"
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
        website: URL(string: "https://withoutbg.com")!,  // utm-ok: tagged by withUTM
        openWeights: URL(string: "https://withoutbg.com/open-model")!,  // utm-ok: tagged by withUTM
        api: URL(string: "https://withoutbg.com/pro-model")!,  // utm-ok: tagged by withUTM
        apiSignup: URL(string: "https://withoutbg.com/signup")!,  // utm-ok: tagged by withUTM
        documentation: URL(string: "https://withoutbg.com/docs")!,  // utm-ok: tagged by withUTM
        benchmarks: URL(string: "https://withoutbg.com/open-model/results")!,  // utm-ok: tagged by withUTM
        github: URL(string: "https://github.com/withoutbg/withoutbg")!,
        license: URL(string: "https://withoutbg.com/open-model/license")!,  // utm-ok: tagged by withUTM
        support: URL(string: "https://withoutbg.com/open-model/support")!,  // utm-ok: tagged by withUTM
        gpuFund: URL(string: "https://withoutbg.com/open-model/support/gpu-fund")!,  // utm-ok: tagged by withUTM
        enterprise: URL(string: "https://withoutbg.com/contact")!,  // utm-ok: tagged by withUTM
        productUpdates: URL(string: "https://api.withoutbg.com/updates")!,  // utm-ok: tagged by withUTM
        privacyPolicy: URL(string: "https://withoutbg.com/privacy")!,  // utm-ok: tagged by withUTM
        ossRepo: URL(string: "https://github.com/withoutbg/withoutbg")!,
        dinov3Repo: URL(string: "https://github.com/facebookresearch/dinov3")!,
        dinov3License: URL(string: "https://ai.meta.com/resources/models-and-libraries/dinov3-license/")!,
        macApp: URL(string: "https://withoutbg.com/mac")!,  // utm-ok: tagged by withUTM
        localAPIDocs: URL(string: "https://withoutbg.com/docs/open-model/local-api")!,  // utm-ok: tagged by withUTM
        localAPIOpenAPI: URL(string: "https://withoutbg.com/openapi/local-api.json")!,  // utm-ok: tagged by withUTM
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

        var queryItems = (components.queryItems ?? []).filter { !$0.name.hasPrefix("utm_") }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let spot = path.isEmpty ? "home" : path.replacingOccurrences(of: "/", with: "-")
        queryItems.append(contentsOf: [
            URLQueryItem(name: "utm_source", value: configuredUTMSource),
            URLQueryItem(name: "utm_medium", value: configuredUTMMedium),
            URLQueryItem(name: "utm_campaign", value: configuredUTMCampaign),
            URLQueryItem(name: "utm_content", value: "\(configuredUTMSource)-\(spot)"),
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
