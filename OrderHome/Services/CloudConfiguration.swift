import Foundation

/// Only public project configuration belongs in the app bundle. Account tokens
/// are managed separately in the device Keychain.
struct CloudConfiguration: Equatable {
    let projectURL: URL
    let publishableKey: String
    let inviteBaseURL: URL?
    let appleSignInEnabled: Bool

    private static let lock = NSLock()
    private static var cachedMainResult: Result<CloudConfiguration, CloudConfigurationError>?

    static func load(bundle: Bundle = .main) -> Result<CloudConfiguration, CloudConfigurationError> {
        if bundle == .main {
            lock.lock()
            if let cached = cachedMainResult {
                lock.unlock()
                return cached
            }
            lock.unlock()
        }
        let result: Result<CloudConfiguration, CloudConfigurationError>
        do { result = .success(try CloudConfiguration(info: bundle.infoDictionary ?? [:])) }
        catch let error as CloudConfigurationError { result = .failure(error) }
        catch { result = .failure(.invalidProjectURL) }
        if bundle == .main {
            lock.lock()
            cachedMainResult = result
            lock.unlock()
        }
        return result
    }

    init(info: [String: Any], allowLocalhost: Bool = CloudConfiguration.localDevelopmentAllowed) throws {
        func value(_ key: String) -> String? {
            guard let text = info[key] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("$("), !trimmed.contains("YOUR_") else { return nil }
            return trimmed
        }
        guard let rawURL = value("SUPABASE_URL") else { throw CloudConfigurationError.missingProjectURL }
        guard let url = URL(string: rawURL), Self.isAllowedURL(url, allowLocalhost: allowLocalhost),
              url.path.isEmpty || url.path == "/" else { throw CloudConfigurationError.invalidProjectURL }
        guard let key = value("SUPABASE_PUBLISHABLE_KEY") else { throw CloudConfigurationError.missingPublishableKey }
        guard Self.isPublicKey(key) else { throw CloudConfigurationError.unsafeKey }
        projectURL = url
        publishableKey = key
        if let rawInviteURL = value("ORDER_HOME_INVITE_BASE_URL") {
            guard let inviteURL = URL(string: rawInviteURL), Self.isAllowedURL(inviteURL, allowLocalhost: allowLocalhost) else {
                throw CloudConfigurationError.invalidInviteURL
            }
            inviteBaseURL = inviteURL
        } else {
            inviteBaseURL = nil
        }
        if let enabled = info["ORDER_HOME_APPLE_SIGNIN_ENABLED"] as? Bool {
            appleSignInEnabled = enabled
        } else {
            appleSignInEnabled = ["YES", "TRUE", "1"].contains(value("ORDER_HOME_APPLE_SIGNIN_ENABLED")?.uppercased() ?? "")
        }
    }

    static var localDevelopmentAllowed: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static func isAllowedURL(_ url: URL, allowLocalhost: Bool) -> Bool {
        guard let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        return allowLocalhost && url.scheme?.lowercased() == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    static func isPublicKey(_ key: String) -> Bool {
        // New Supabase public keys carry an explicit prefix. Secret keys are
        // rejected before any client or network connection can be created.
        if key.hasPrefix("sb_publishable_") {
            return key.range(of: "^sb_publishable_[A-Za-z0-9_-]{16,}$", options: .regularExpression) != nil
        }
        // Legacy anon JWTs remain supported, but service-role and authenticated
        // JWTs must never be embedded in the app.
        let pieces = key.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, !pieces[0].isEmpty, !pieces[2].isEmpty else { return false }
        var payload = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["role"] as? String == "anon"
    }
}

enum CloudConfigurationError: LocalizedError, Equatable {
    case missingProjectURL, invalidProjectURL, missingPublishableKey, unsafeKey, invalidInviteURL

    var errorDescription: String? {
        switch self {
        case .missingProjectURL: "Shared kitchens are not connected in this build. Add the Supabase project URL to the build configuration."
        case .invalidProjectURL: "The shared kitchen project URL must use a secure connection."
        case .missingPublishableKey: "The shared kitchen public project key is missing from this build."
        case .unsafeKey: "This build needs a Supabase publishable key or legacy anon key. Secret and service-role keys are not allowed in the app."
        case .invalidInviteURL: "The kitchen invitation base URL must use a secure connection."
        }
    }
}

enum CloudServiceError: LocalizedError, Equatable {
    case notConfigured, offline, signedOut, invalidEmail, invalidCode, expiredCode, throttled
    case permissionDenied, invalidInvitation, dinnerChanged, unavailable, secureStorage

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Shared kitchens are not connected in this build yet. Your kitchen on this iPhone is still available."
        case .offline: "You appear to be offline. Connect to the internet and try again."
        case .signedOut: "Please sign in again to reconnect your kitchen."
        case .invalidEmail: "Enter a valid email address."
        case .invalidCode: "That code could not be verified. Check the code in your email and try again."
        case .expiredCode: "That sign-in code has expired. Request a new code."
        case .throttled: "Please wait a moment before trying again."
        case .permissionDenied: "Your account cannot make that change in this kitchen."
        case .invalidInvitation: "This invitation is invalid, expired, or already used. Ask the kitchen owner for a new invitation."
        case .dinnerChanged: "Dinner has changed. Refresh your kitchen and try again."
        case .unavailable: "Your kitchen could not be reached. Please try again shortly."
        case .secureStorage: "Your sign-in could not be saved securely on this iPhone. Please try again."
        }
    }
}
