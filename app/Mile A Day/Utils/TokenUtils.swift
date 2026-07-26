import Foundation

/// Utilities for working with JWT tokens
enum TokenUtils {
    
    /// Decode a JWT's payload (second segment) into its claims.
    /// - Parameter token: JWT token string
    /// - Returns: Claim dictionary if the token is a well-formed JWT, nil otherwise
    static func claims(from token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else {
            return nil
        }

        // Decode the payload (second part)
        let payload = parts[1]

        // Add padding if needed (base64url decoding)
        var base64 = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 = base64.padding(toLength: base64.count + 4 - remainder, withPad: "=", startingAt: 0)
        }

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    /// Decode JWT and extract expiration time
    /// - Parameter token: JWT token string
    /// - Returns: Expiration date if valid, nil otherwise
    static func getExpirationDate(from token: String) -> Date? {
        guard let exp = claims(from: token)?["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    /// The `sub` claim — the backend user id this access token was minted for.
    ///
    /// This is the only authoritative answer to "who am I?". The locally cached
    /// ids (`currentUser.backendUserId`, `UserDefaults["backendUserId"]`) can
    /// drift away from it, and every self-scoped endpoint puts the cached id in
    /// the URL path where the server compares it against this claim.
    /// - Parameter token: JWT token string
    /// - Returns: The subject if present and non-empty, nil otherwise
    static func subject(from token: String) -> String? {
        guard let sub = claims(from: token)?["sub"] as? String, !sub.isEmpty else {
            return nil
        }

        return sub
    }
    
    /// Check if access token is expired or expiring soon
    /// - Parameters:
    ///   - token: JWT token string
    ///   - bufferSeconds: Buffer time in seconds before expiration to consider token expired (default: 60 seconds)
    /// - Returns: true if token is expired or expiring soon, false otherwise
    static func isTokenExpired(_ token: String, bufferSeconds: TimeInterval = 60) -> Bool {
        guard let expirationDate = getExpirationDate(from: token) else {
            // If we can't decode the token, consider it expired for safety
            return true
        }
        
        let now = Date()
        let bufferDate = expirationDate.addingTimeInterval(-bufferSeconds)
        
        return now >= bufferDate
    }
    
    /// Check if access token exists and is valid (not expired)
    /// - Parameter token: Optional JWT token string
    /// - Returns: true if token exists and is not expired, false otherwise
    static func isTokenValid(_ token: String?) -> Bool {
        guard let token = token, !token.isEmpty else {
            return false
        }
        
        return !isTokenExpired(token)
    }
}

