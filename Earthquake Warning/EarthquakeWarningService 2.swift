//
//  EarthquakeWarningService.swift
//  Earthquake Warning
//
//  Created by Assistant on 2026-06-24.
//

import Foundation

// Public model mirrors ContentView's model for convenience
struct ParsedEarthquakeWarning: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let receivedAt: Date
}

enum EarthquakeRegion: String {
    case korea = "대한민국 (한국어)"
    case chinaMainland = "中国 (简体中文)"
    case taiwan = "臺灣 (繁體中文)"
}

extension EarthquakeWarningService {

    // MARK: - Korea (KMA)
    // KMA provides an Atom feed for earthquake info (example public feed)
    // We'll parse a generic RSS/Atom XML and extract title/summary/date.
    private func fetchKMA() async throws -> [ParsedEarthquakeWarning] {
        // Example feed: https://www.weather.go.kr/w/rss/earthquake.jsp (subject to change)
        // Provide multiple candidates and use the first that responds.
        let candidates: [URL] = [
            URL(string: "https://www.weather.go.kr/w/rss/earthquake.jsp")!,
            URL(string: "https://www.kma.go.kr/weather/earthquake_volcano/domesticlist.jsp?type=xml")!
        ]
        if let (data, _) = try await firstSuccessfulData(from: candidates) {
            return try parseRSSOrAtom(data: data)
        }
        return []
    }

    // MARK: - Taiwan (CWA)
    // CWA (Central Weather Administration) provides quake feeds (JSON or XML). We'll attempt JSON first.
    private func fetchCWA() async throws -> [ParsedEarthquakeWarning] {
        // Public JSON feed reference (subject to availability). Alternative XML feeds exist.
        let candidates: [URL] = [
            URL(string: "https://opendata.cwa.gov.tw/api/v1/rest/datastore/E-A0015-001?limit=10")!,
            URL(string: "https://opendata.cwa.gov.tw/fileapi/v1/opendataapi/E-A0015-001?downloadType=WEB&format=JSON")!
        ]
        if let (data, _) = try await firstSuccessfulData(from: candidates) {
            if let parsed = try? parseCWAJSON(data: data) {
                return parsed
            }
            // Fallback to XML parsing if JSON fails
            if let parsed = try? parseRSSOrAtom(data: data) {
                return parsed
            }
        }
        return []
    }

    // MARK: - China Mainland (CENC) with USGS fallback
    private func fetchCENCOrUSGS() async throws -> [ParsedEarthquakeWarning] {
        // CENC has public pages/feeds; we'll try a known RSS-like endpoint, then fallback to USGS global feed filtered later by ContentView (region text).
        let cencCandidates: [URL] = [
            URL(string: "https://news.ceic.ac.cn/rss/eqs/earthquake.xml")!,
            URL(string: "https://www.ceic.ac.cn/ajax/LatestEarthquakeWarning3")! // JSON-like
        ]
        if let (data, url) = try await firstSuccessfulData(from: cencCandidates) {
            if url.absoluteString.contains("LatestEarthquakeWarning3"), let parsed = try? parseCENCJSON(data: data) {
                return parsed
            } else if let parsed = try? parseRSSOrAtom(data: data) {
                return parsed
            }
        }
        // USGS fallback: All earthquakes past hour/day JSON
        let usgsCandidates: [URL] = [
            URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_hour.geojson")!,
            URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson")!
        ]
        if let (data, _) = try await firstSuccessfulData(from: usgsCandidates) {
            return try parseUSGSGEOJSON(data: data)
        }
        return []
    }

    // MARK: - Networking helpers
    private func firstSuccessfulData(from candidates: [URL]) async throws -> (Data, URL)? {
        for url in candidates {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, !data.isEmpty {
                    return (data, url)
                }
            } catch { continue }
        }
        return nil
    }

    // MARK: - Parsers
    private func parseRSSOrAtom(data: Data) throws -> [ParsedEarthquakeWarning] {
        // A very lightweight and permissive XML parser extracting <item>/<entry> title, description/summary, pubDate/updated.
        let xml = String(data: data, encoding: .utf8) ?? ""
        var items: [ParsedEarthquakeWarning] = []

        // Split by common item tags; this is simplistic but robust enough for feeds used here.
        let itemBlocks = xml.components(separatedBy: "<item>") + xml.components(separatedBy: "<entry>")
        for block in itemBlocks {
            let title = extractFirst(from: block, tags: ["title"]) ?? ""
            let desc = extractFirst(from: block, tags: ["description", "summary", "content"]) ?? ""
            let dateString = extractFirst(from: block, tags: ["pubDate", "updated", "dc:date"]) ?? ""
            let date = parseDatePermissive(dateString) ?? Date()
            if !title.isEmpty || !desc.isEmpty {
                items.append(ParsedEarthquakeWarning(title: title.trimmedXML(), description: desc.trimmedXML(), receivedAt: date))
            }
        }
        return items
    }

    private func parseCWAJSON(data: Data) throws -> [ParsedEarthquakeWarning] {
        // CWA JSON structure may vary; attempt to read common fields.
        struct Root: Decodable { let records: Records? }
        struct Records: Decodable { let Earthquake: [EQ]? }
        struct EQ: Decodable {
            let EarthquakeInfo: EQInfo
            let ReportContent: String?
        }
        struct EQInfo: Decodable {
            let OriginTime: String
            let Location: String?
            let EarthquakeMagnitude: EQMag?
        }
        struct EQMag: Decodable { let MagnitudeValue: Double? }

        let root = try JSONDecoder().decode(Root.self, from: data)
        let list = root.records?.Earthquake ?? []
        var results: [ParsedEarthquakeWarning] = []
        for eq in list {
            let magStr: String
            if let mv = eq.EarthquakeInfo.EarthquakeMagnitude?.MagnitudeValue { magStr = String(format: "%.1f", mv) } else { magStr = "?" }
            let loc = eq.EarthquakeInfo.Location ?? ""
            let title = "M\(magStr) \(loc)"
            let desc = eq.ReportContent ?? loc
            let date = parseDatePermissive(eq.EarthquakeInfo.OriginTime) ?? Date()
            results.append(ParsedEarthquakeWarning(title: title, description: desc, receivedAt: date))
        }
        return results
    }

    private func parseCENCJSON(data: Data) throws -> [ParsedEarthquakeWarning] {
        // CENC unofficial JSON endpoint. We'll handle a loose structure.
        struct Item: Decodable {
            let M: String? // magnitude
            let O: String? // origin time
            let L: String? // location
        }
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([Item].self, from: data) {
            return arr.map { item in
                let mag = item.M ?? "?"
                let loc = item.L ?? ""
                let title = "M\(mag) \(loc)"
                let date = parseDatePermissive(item.O ?? "") ?? Date()
                return ParsedEarthquakeWarning(title: title, description: loc, receivedAt: date)
            }
        }
        // If not array, attempt dictionary with key "shuju" or similar
        return []
    }

    private func parseUSGSGEOJSON(data: Data) throws -> [ParsedEarthquakeWarning] {
        struct Root: Decodable { let features: [Feature] }
        struct Feature: Decodable { let properties: Properties }
        struct Properties: Decodable { let mag: Double?; let place: String?; let time: Double? }
        let root = try JSONDecoder().decode(Root.self, from: data)
        return root.features.map { f in
            let magStr = f.properties.mag.map { String(format: "%.1f", $0) } ?? "?"
            let place = f.properties.place ?? ""
            let date = f.properties.time.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date()
            return ParsedEarthquakeWarning(title: "M\(magStr) \(place)", description: place, receivedAt: date)
        }
    }

    // MARK: - Utilities
    private func parseDatePermissive(_ s: String) -> Date? {
        if s.isEmpty { return nil }
        let fmts = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd'T'HH:mm:ssXXX"
        ]
        for f in fmts {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private func extractFirst(from block: String, tags: [String]) -> String? {
        for tag in tags {
            if let range1 = block.range(of: "<\(tag)>") ?? block.range(of: "<\(tag) "),
               let range2 = block.range(of: "</\(tag)>") {
                let start = range1.upperBound
                let inner = block[start..<range2.lowerBound]
                // Trim attributes if present in opening tag
                if let close = inner.firstIndex(of: ">"), range1.lowerBound != block.range(of: "<\(tag) ")?.lowerBound {
                    let after = inner.index(after: close)
                    return String(inner[after...])
                }
                return String(inner)
            }
        }
        return nil
    }
}

private extension String {
    func trimmedXML() -> String {
        self.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

