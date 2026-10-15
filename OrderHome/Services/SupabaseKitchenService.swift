import Foundation
import Security
import Supabase

@MainActor
final class SupabaseKitchenService: KitchenCloudService {
    let configuration: CloudConfiguration?
    let setupError: String?
    private var _client: SupabaseClient?
    private var _secureStorage: KitchenKeychainStorage?
    private var hasAttemptedClientInit = false

    var isConfigured: Bool { configuration != nil }

    private var client: SupabaseClient? {
        if !hasAttemptedClientInit {
            hasAttemptedClientInit = true
            guard let configuration else { return nil }
            let namespace = "com.orderhome.auth.\(configuration.projectURL.host ?? "project"):\(configuration.projectURL.port ?? 443)"
            let storage = KitchenKeychainStorage(service: namespace)
            _secureStorage = storage
            _client = SupabaseClient(
                supabaseURL: configuration.projectURL,
                supabaseKey: configuration.publishableKey,
                options: .init(
                    db: .init(decoder: CloudJSON.decoder()),
                    auth: .init(
                        storage: storage,
                        storageKey: "order-home-session",
                        autoRefreshToken: true,
                        emitLocalSessionAsInitialSession: false
                    )
                )
            )
        }
        return _client
    }

    private var secureStorage: KitchenKeychainStorage? {
        _ = client
        return _secureStorage
    }

    init(configurationResult: Result<CloudConfiguration, CloudConfigurationError> = CloudConfiguration.load()) {
        switch configurationResult {
        case .success(let configuration):
            self.configuration = configuration
            setupError = nil
        case .failure(let error):
            self.configuration = nil
            setupError = error.localizedDescription
            hasAttemptedClientInit = true
        }
    }

    convenience init(configuration: CloudConfiguration) {
        self.init(configurationResult: .success(configuration))
    }

    func restoreSession() async throws -> CloudIdentity? {
        guard let client else { return nil }
        do {
            return Self.identity(try await client.auth.session.user)
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            throw Self.sanitized(error)
        }
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async throws -> CloudIdentity {
        let client = try connectedClient()
        do {
            let session = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            // The SDK reports storage failures only to its optional logger.
            // Verify persistence before presenting a successful sign-in.
            guard client.auth.currentSession != nil else { throw CloudServiceError.secureStorage }
            var identity = Self.identity(session.user)
            if let displayName, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Apple supplies a name only on its first authorization. Store
                // that display value as metadata; it never grants permissions.
                let name = String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                if let user = try? await client.auth.update(user: .init(data: ["display_name": .string(name)])) {
                    identity = Self.identity(user)
                } else {
                    identity.displayName = name
                }
            }
            return identity
        } catch {
            throw Self.sanitized(error)
        }
    }

    func requestEmailCode(email: String) async throws {
        let client = try connectedClient()
        let email = try Self.validatedEmail(email)
        do {
            try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
        } catch {
            throw Self.sanitized(error)
        }
    }

    func verifyEmailCode(email: String, code: String) async throws -> CloudIdentity {
        let client = try connectedClient()
        let email = try Self.validatedEmail(email)
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (6...10).contains(code.count), code.allSatisfy(\.isNumber) else { throw CloudServiceError.invalidCode }
        do {
            let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
            guard let session = response.session else { throw CloudServiceError.invalidCode }
            guard client.auth.currentSession != nil else { throw CloudServiceError.secureStorage }
            return Self.identity(session.user)
        } catch {
            throw Self.sanitized(error)
        }
    }

    func signOut() async throws {
        let client = try connectedClient()
        await client.removeAllChannels()
        do {
            try await client.auth.signOut(scope: .local)
        } catch {
            // The SDK clears this device's session before revoking it remotely.
            // An offline revoke must not strand the UI in a signed-in state.
        }
        // Confirm removal ourselves because the SDK intentionally swallows
        // local-storage deletion failures. A failed device sign-out must be
        // visible rather than silently restoring the old account next launch.
        do { try secureStorage?.remove(key: "order-home-session") }
        catch { throw CloudServiceError.secureStorage }
        guard client.auth.currentSession == nil else { throw CloudServiceError.secureStorage }
    }

    func listKitchens() async throws -> [CloudHousehold] {
        let client = try connectedClient()
        do {
            let response = try await client.rpc("my_kitchens").execute()
            return try CloudJSON.decoder().decode([CloudHousehold].self, from: response.data)
        }
        catch { throw Self.sanitized(error) }
    }

    func snapshot(householdID: String) async throws -> CloudKitchenSnapshot {
        try await rpc("kitchen_snapshot", parameters: ["p_household_id": .string(householdID)])
    }

    func createKitchen(name: String, mode: HouseholdMode, displayName: String) async throws -> String {
        try await rpc("create_kitchen", parameters: [
            "p_name": .string(name), "p_mode": .string(mode.rawValue), "p_display_name": .string(displayName)
        ])
    }

    func createInvite(householdID: String) async throws -> CloudInvitation {
        try await rpc("create_kitchen_invite", parameters: ["p_household_id": .string(householdID)])
    }

    func joinKitchen(token: String, displayName: String) async throws -> String {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.range(of: "^[A-Fa-f0-9]{64}$", options: .regularExpression) != nil else {
            throw CloudServiceError.invalidInvitation
        }
        return try await rpc("join_kitchen", parameters: ["p_token": .string(token.lowercased()), "p_display_name": .string(displayName)])
    }

    func perform(_ command: CloudCommand) async throws {
        let (name, parameters) = Self.request(for: command)
        let client = try connectedClient()
        do { _ = try await client.rpc(name, params: parameters).execute() }
        catch { throw Self.sanitized(error) }
    }

    /// SDK channels reconnect automatically and receive fresh access tokens from
    /// Supabase Auth. Every subscription/rejoin triggers a full snapshot, so a
    /// disconnected phone catches up even if it missed individual changes.
    func changes(householdID: String) -> AsyncStream<Void> {
        guard let client else { return AsyncStream { $0.finish() } }
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { @MainActor in
                let channel = client.channel("kitchen:\(householdID):\(UUID().uuidString)")
                let tables = ["household_members", "dinner_sessions", "dish_pitches", "dish_votes", "diner_orders"]
                // Register all listeners before joining. RLS controls which
                // rows are delivered; filters reduce unrelated notifications.
                var streams = tables.map {
                    channel.postgresChange(AnyAction.self, schema: "public", table: $0, filter: .eq("household_id", value: householdID))
                }
                streams.append(channel.postgresChange(AnyAction.self, schema: "public", table: "households", filter: .eq("id", value: householdID)))
                let listeners = streams.map { stream in
                    Task {
                        for await _ in stream {
                            guard !Task.isCancelled else { break }
                            continuation.yield(())
                        }
                    }
                }
                let statusListener = Task {
                    for await status in channel.statusChange {
                        guard !Task.isCancelled else { break }
                        if status == .subscribed { continuation.yield(()) }
                    }
                }
                var retrySeconds: UInt64 = 2
                while !Task.isCancelled {
                    do {
                        try await channel.subscribeWithError()
                        // The SDK manages reconnects after the first join.
                        while !Task.isCancelled { try await Task.sleep(nanoseconds: 60_000_000_000) }
                    } catch {
                        if Task.isCancelled { break }
                        // Keep the observation alive when opening the app with
                        // no connection. The controller also polls snapshots.
                        do { try await Task.sleep(nanoseconds: retrySeconds * 1_000_000_000) }
                        catch { break }
                        retrySeconds = min(retrySeconds * 2, 30)
                    }
                }
                listeners.forEach { $0.cancel() }
                statusListener.cancel()
                await client.removeChannel(channel)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func connectedClient() throws -> SupabaseClient {
        guard let client else { throw CloudServiceError.notConfigured }
        return client
    }

    private func rpc<T: Decodable>(_ name: String, parameters: [String: AnyJSON]) async throws -> T {
        let client = try connectedClient()
        do {
            let response = try await client.rpc(name, params: parameters).execute()
            return try CloudJSON.decoder().decode(T.self, from: response.data)
        }
        catch { throw Self.sanitized(error) }
    }

    static func request(for command: CloudCommand) -> (String, [String: AnyJSON]) {
        func session(_ id: String) -> [String: AnyJSON] { ["p_session_id": .string(id)] }
        switch command {
        case let .openDinner(householdID, deadline):
            return ("open_dinner", ["p_household_id": .string(householdID), "p_deadline": .string(CloudJSON.timestamp(deadline))])
        case let .nominate(sessionID, recipeID):
            return ("add_pitch", session(sessionID).merging(["p_recipe_id": .string(recipeID)]) { _, value in value })
        case let .removePitch(sessionID, recipeID):
            return ("remove_pitch", session(sessionID).merging(["p_recipe_id": .string(recipeID)]) { _, value in value })
        case let .startVoting(sessionID): return ("start_voting", session(sessionID))
        case let .submitOrder(sessionID, reactions, attending, note):
            return ("submit_order", [
                "p_session_id": .string(sessionID),
                "p_reactions": .array(reactions.map { .object(["pitch_id": .string($0.pitchID), "weight": .integer($0.weight)]) }),
                "p_eating_home": .bool(attending), "p_tags": .array([]), "p_note": .string(note)
            ])
        case let .closeVoting(sessionID): return ("close_voting", session(sessionID))
        case let .advanceKitchen(sessionID, status, stepIndex, groceries):
            return ("advance_kitchen", [
                "p_session_id": .string(sessionID), "p_status": .string(status), "p_step_index": .integer(stepIndex),
                "p_missing_groceries": .array(groceries.map(AnyJSON.string))
            ])
        case let .updateProfile(householdID, name, emoji, tags):
            return ("update_own_profile", [
                "p_household_id": .string(householdID), "p_display_name": .string(name), "p_avatar_emoji": .string(emoji),
                "p_dietary_tags": .array(tags.map(AnyJSON.string))
            ])
        case let .setMode(householdID, mode):
            return ("set_kitchen_mode", ["p_household_id": .string(householdID), "p_mode": .string(mode.rawValue)])
        case let .expireVoting(sessionID): return ("expire_voting", session(sessionID))
        case let .extendVoting(sessionID, deadline):
            return ("extend_voting", session(sessionID).merging(["p_deadline": .string(CloudJSON.timestamp(deadline))]) { _, value in value })
        case let .savePreferences(sessionID, attending, note):
            return ("save_diner_preferences", ["p_session_id": .string(sessionID), "p_eating_home": .bool(attending), "p_tags": .array([]), "p_note": .string(note)])
        case let .cancelDinner(sessionID): return ("cancel_dinner", session(sessionID))
        }
    }

    private static func identity(_ user: User) -> CloudIdentity {
        // Metadata is used for display only; kitchen roles come from RLS-backed
        // household membership rows returned by the server.
        CloudIdentity(id: user.id.uuidString.lowercased(), email: user.email,
                      displayName: user.userMetadata["display_name"]?.stringValue ?? user.userMetadata["full_name"]?.stringValue)
    }

    private static func validatedEmail(_ value: String) throws -> String {
        let email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.count <= 254, email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil else {
            throw CloudServiceError.invalidEmail
        }
        return email
    }

    /// Never surface SDK error bodies, URLs, JWTs, or database detail strings.
    static func sanitized(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let error = error as? CloudServiceError { return error }
        if let error = error as? URLError {
            return error.code == .cancelled ? CancellationError() : CloudServiceError.offline
        }
        if error is KitchenKeychainError { return CloudServiceError.secureStorage }
        if let error = error as? AuthError {
            switch error.errorCode.rawValue {
            case "session_not_found", "session_expired", "refresh_token_not_found", "refresh_token_already_used": return CloudServiceError.signedOut
            case "otp_expired": return CloudServiceError.expiredCode
            case "over_email_send_rate_limit", "over_request_rate_limit", "over_sms_send_rate_limit": return CloudServiceError.throttled
            case "otp_disabled", "invalid_credentials", "validation_failed": return CloudServiceError.invalidCode
            default: return CloudServiceError.unavailable
            }
        }
        if let error = error as? PostgrestError {
            if ["42501"].contains(error.code ?? "") { return CloudServiceError.permissionDenied }
            if ["PGRST301", "PGRST302", "PGRST303"].contains(error.code ?? "") { return CloudServiceError.signedOut }
            let message = error.message.lowercased()
            if message.contains("invitation") || message.contains("invite") { return CloudServiceError.invalidInvitation }
            if message.contains("chef") || message.contains("owner") || message.contains("member") { return CloudServiceError.permissionDenied }
            if error.code == "23505" || error.code == "P0001" { return CloudServiceError.dinnerChanged }
        }
        return CloudServiceError.unavailable
    }
}

private struct KitchenKeychainError: Error { let status: OSStatus }

/// A device-only Keychain item isolates each Supabase project's refresh token.
/// No credentials are written to the kitchen JSON save or UserDefaults.
private struct KitchenKeychainStorage: AuthLocalStorage {
    let service: String

    func store(key: String, value: Data) throws {
        let query = item(key)
        let attributes: [String: Any] = [kSecValueData as String: value, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            result = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard result == errSecSuccess else { throw KitchenKeychainError(status: result) }
    }

    func retrieve(key: String) throws -> Data? {
        var query = item(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &value)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess else { throw KitchenKeychainError(status: result) }
        return value as? Data
    }

    func remove(key: String) throws {
        let result = SecItemDelete(item(key) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw KitchenKeychainError(status: result) }
    }

    private func item(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
    }
}
