import Foundation

/// Fire-and-forget usage pings for features the database can't otherwise see
/// (a flyover PLAY leaves no row anywhere). The server validates against an
/// allowlist and the admin adoption panel charts them next to every
/// DB-derived feature. Failures are silently dropped — nothing user-facing
/// may ever depend on a telemetry write.
enum TelemetryService {
    static func record(_ feature: String) {
        Task.detached(priority: .utility) {
            struct Body: Encodable { let feature: String }
            struct Response: Decodable { let recorded: Bool }
            guard let body = try? JSONEncoder().encode(Body(feature: feature)) else { return }
            _ = try? await APIClient.fancyFetch(
                endpoint: "/telemetry/feature",
                method: .POST,
                body: body,
                responseType: Response.self
            )
        }
    }
}
