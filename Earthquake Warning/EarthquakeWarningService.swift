import Foundation

// MARK: - Earthquake API Service
struct EarthquakeAPIWarning: Decodable {
    let id: String
    let properties: Properties
    
    struct Properties: Decodable {
        let place: String?
        let mag: Double?
        let time: Double?
        let title: String?
    }
}

final class EarthquakeWarningService {
    static let shared = EarthquakeWarningService()
    
    private init() {}
    
    // Fetch earthquake warnings for a region (Korea, Japan, etc)
    func fetchWarnings(for region: String) async throws -> [EarthquakeWarning] {
        // USGS API provides worldwide data. We'll use a bounding box for Korea or filter by region keyword.
        // Korea bounding box: minlatitude=33, maxlatitude=39, minlongitude=124, maxlongitude=132
        let urlString: String
        switch region {
        case "대한민국", "Korea":
            urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=33&maxlatitude=39&minlongitude=124&maxlongitude=132&limit=20"
        case "日本", "Japan":
            urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=24&maxlatitude=46&minlongitude=122&maxlongitude=153&limit=20"
        case "中国大陆", "China":
            urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=18&maxlatitude=54&minlongitude=73&maxlongitude=135&limit=20"
        case "臺灣", "Taiwan":
            urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&minlatitude=21.5&maxlatitude=25.5&minlongitude=119&maxlongitude=123.5&limit=20"
        default:
            urlString = "https://earthquake.usgs.gov/fdsnws/event/1/query?format=geojson&limit=20"
        }
        guard let url = URL(string: urlString) else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(USGSResponse.self, from: data)
        return response.features.map { feature in
            EarthquakeWarning(
                title: feature.properties.title ?? "Earthquake Warning",
                description: "Magnitude \(feature.properties.mag ?? 0) at \(feature.properties.place ?? "Unknown location")",
                receivedAt: Date(timeIntervalSince1970: (feature.properties.time ?? 0)/1000)
            )
        }
    }
    
    struct USGSResponse: Decodable {
        let features: [EarthquakeAPIWarning]
    }
}
