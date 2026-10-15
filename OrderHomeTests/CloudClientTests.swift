import XCTest
@testable import OrderHome

final class CloudClientTests: XCTestCase {
    private let publicKey = "sb_publishable_examplePublicTestKey12345"

    private func info(url: String = "https://kitchen.example.supabase.co", key: String? = nil) -> [String: Any] {
        ["SUPABASE_URL": url, "SUPABASE_PUBLISHABLE_KEY": key ?? publicKey]
    }

    func testConfigurationRequiresPublicCredentialsAndSecureURLs() throws {
        let configuration = try CloudConfiguration(info: info())
        XCTAssertEqual(configuration.projectURL.host, "kitchen.example.supabase.co")
        XCTAssertFalse(configuration.appleSignInEnabled)
        XCTAssertNil(configuration.inviteBaseURL)
        XCTAssertThrowsError(try CloudConfiguration(info: info(key: "sb_secret_do_not_ship_to_clients"))) {
            XCTAssertEqual($0 as? CloudConfigurationError, .unsafeKey)
        }
        XCTAssertThrowsError(try CloudConfiguration(info: info(url: "http://kitchen.example.com"), allowLocalhost: true))
        XCTAssertThrowsError(try CloudConfiguration(info: info(url: "https://user:password@kitchen.example.com")))
        XCTAssertThrowsError(try CloudConfiguration(info: info(url: "https://kitchen.example.com?key=value")))
        XCTAssertThrowsError(try CloudConfiguration(info: ["SUPABASE_URL": "$(SUPABASE_URL)"]))
    }

    func testConfigurationAllowsExplicitLocalDevelopmentOnly() throws {
        XCTAssertNoThrow(try CloudConfiguration(info: info(url: "http://127.0.0.1:54321"), allowLocalhost: true))
        XCTAssertThrowsError(try CloudConfiguration(info: info(url: "http://127.0.0.1:54321"), allowLocalhost: false))
        XCTAssertThrowsError(try CloudConfiguration(info: info(url: "http://192.168.1.100:54321"), allowLocalhost: true))
    }

    func testLegacyServiceRoleAndAuthenticatedJWTsAreRejected() {
        func jwt(_ role: String) -> String {
            let payload = Data("{\"role\":\"\(role)\"}".utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            return "header.\(payload).signature"
        }
        XCTAssertTrue(CloudConfiguration.isPublicKey(jwt("anon")))
        XCTAssertFalse(CloudConfiguration.isPublicKey(jwt("service_role")))
        XCTAssertFalse(CloudConfiguration.isPublicKey(jwt("authenticated")))
        XCTAssertFalse(CloudConfiguration.isPublicKey("invalid.jwt"))
    }

    func testSnapshotDecodesPostgresDatesAndIgnoresAdditionalServerFields() throws {
        let json = """
        {
          "household":{"id":"home","name":"Our table","mode":"family","owner_user_id":"user"},
          "members":[{"id":"member","user_id":"user","display_name":"Alex","avatar_emoji":"🍽️","default_role":"head_chef","dietary_tags":[]}],
          "session":{"id":"dinner","household_id":"home","head_chef_id":"member","status":"ticket_locked","voting_deadline":"2026-10-16T01:30:00.123456+00:00","winning_pitch_id":"pitch","missing_groceries":["lime"],"cooking_step_index":0,"poll_mode":"open_cravings"},
          "pitches":[{"id":"pitch","recipe_id":"tacos","pitched_by_member_id":"member","custom_note":"ignored"}],
          "votes":[{"pitch_id":"pitch","member_id":"member","vote_weight":2}],
          "orders":[{"member_id":"member","is_eating_home":true,"modifier_tags":[],"diner_note":"Less spicy","submitted_at":"2026-10-16T01:20:00Z"}]
        }
        """
        let snapshot = try CloudJSON.decoder().decode(CloudKitchenSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.household.name, "Our table")
        XCTAssertEqual(snapshot.session?.status, "ticket_locked")
        XCTAssertEqual(snapshot.session?.winningPitchID, snapshot.pitches.first?.id)
        XCTAssertEqual(snapshot.orders.first?.dinerNote, "Less spicy")
        XCTAssertNotNil(snapshot.orders.first?.submittedAt)
        XCTAssertEqual(snapshot.votes.first?.voteWeight, 2)
    }

    func testSnapshotWithNoDinnerAndUnsubmittedOrderDecodes() throws {
        let json = """
        {"household":{"id":"home","name":"Our table","mode":"couple","owner_user_id":"user"},"members":[],"session":null,"pitches":[],"votes":[],"orders":[{"member_id":"person","is_eating_home":true,"modifier_tags":[],"diner_note":"","submitted_at":null}]}
        """
        let snapshot = try CloudJSON.decoder().decode(CloudKitchenSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.orders.first?.submittedAt)
    }

    @MainActor
    func testSubmitOrderMapsFullBallotAndNeverIncludesAnotherMemberIdentity() throws {
        let (name, parameters) = SupabaseKitchenService.request(for: .submitOrder(
            sessionID: "dinner", reactions: [CloudReaction(pitchID: "a", weight: 2), CloudReaction(pitchID: "b", weight: 0)], attending: true, note: "No onions"
        ))
        XCTAssertEqual(name, "submit_order")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameters)) as? [String: Any])
        XCTAssertEqual(json["p_session_id"] as? String, "dinner")
        XCTAssertEqual(json["p_eating_home"] as? Bool, true)
        XCTAssertEqual((json["p_reactions"] as? [[String: Any]])?.count, 2)
        XCTAssertNil(json["p_member_id"], "The server derives membership from the authenticated user")
        XCTAssertEqual(json["p_note"] as? String, "No onions")
        XCTAssertEqual((json["p_tags"] as? [String])?.count, 0)
    }

    @MainActor
    func testUnconfiguredServiceNeverCreatesFakeSessionOrAttemptsNetwork() async throws {
        let service = SupabaseKitchenService(configurationResult: .failure(.missingProjectURL))
        XCTAssertFalse(service.isConfigured)
        XCTAssertNotNil(service.setupError)
        let identity = try await service.restoreSession()
        XCTAssertNil(identity)
        do {
            _ = try await service.listKitchens()
            XCTFail("Unconfigured service must fail clearly")
        } catch {
            XCTAssertEqual(error as? CloudServiceError, .notConfigured)
        }
    }

    @MainActor
    func testUnexpectedErrorsAreSanitized() {
        let source = NSError(domain: "api", code: 500, userInfo: [NSLocalizedDescriptionKey: "secret-token-auth-body"])
        let safe = SupabaseKitchenService.sanitized(source)
        XCTAssertFalse(safe.localizedDescription.contains("secret-token"))
        XCTAssertEqual(safe as? CloudServiceError, .unavailable)
    }
}
