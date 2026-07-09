//
//  HTTPClient.swift
//  LunaAnime
//
//  Thin URLSession wrapper with sensible defaults for anime scraping:
//  configurable headers (Referer, User-Agent), retry, and JSON / text helpers.
//

import Foundation

public struct HTTPRequest {
    public let url: URL
    public var method: String = "GET"
    public var headers: [String: String] = [:]
    public var body: Data? = nil

    public init(url: URL,
                method: String = "GET",
                headers: [String: String] = [:],
                body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

public protocol HTTPClientProtocol {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse)
    func text(_ request: HTTPRequest) async throws -> String
    func decoded<T: Decodable>(_ type: T.Type, from request: HTTPRequest) async throws -> T
}

public final class HTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private let preferredUserAgent: String

    public init(session: URLSession = HTTPClient.makeSession(),
                userAgent: String = HTTPClient.defaultUserAgent) {
        self.session = session
        self.preferredUserAgent = userAgent
    }

    public static var defaultUserAgent: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + "Version/17.4 Mobile/15E148 Safari/604.1"
    }

    public static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = [
            "Accept": "application/json, text/plain, text/html, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": HTTPClient.defaultUserAgent,
            "Connection": "keep-alive"
        ]
        cfg.timeoutIntervalForRequest = 25
        cfg.timeoutIntervalForResource = 60
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }

    public func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        var urlReq = URLRequest(url: request.url)
        urlReq.httpMethod = request.method
        urlReq.httpBody = request.body
        urlReq.setValue(preferredUserAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in request.headers { urlReq.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await session.data(for: urlReq)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network(underlying: "Non-HTTP response")
        }

        if http.statusCode == 429 {
            let retryHeader = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw ProviderError.rateLimited(retryAfter: retryHeader)
        }
        if http.statusCode == 404 {
            throw ProviderError.notFound
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProviderError.network(underlying: "HTTP \(http.statusCode) on \(request.url.absoluteString)")
        }
        return (data, http)
    }

    public func text(_ request: HTTPRequest) async throws -> String {
        let (data, _) = try await send(request)
        let enc = String.Encoding.utf8
        return String(data: data, encoding: enc) ?? ""
    }

    public func decoded<T: Decodable>(_ type: T.Type, from request: HTTPRequest) async throws -> T {
        let (data, _) = try await send(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ProviderError.decode(reason: "\(error)")
        }
    }
}
