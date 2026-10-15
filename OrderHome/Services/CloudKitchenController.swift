import Foundation
import Observation

/// Shared state is loaded from authenticated server operations. Local sample
/// data remains separate, and a signed-in diner cannot choose another identity.
@MainActor
@Observable
final class CloudKitchenController {
    private(set) var identity: CloudIdentity?
    private(set) var kitchens: [CloudHousehold] = []
    private(set) var activeHouseholdID: String?
    private(set) var isBusy = false
    private(set) var connectionStatus = "On this iPhone"
    var errorMessage: String?
    var pendingInviteToken: String?
    var showAccountSheet = false
    private(set) var hasUnsubmittedChanges = false
    private(set) var lastUpdatedAt: Date?

    @ObservationIgnored private let service: any KitchenCloudService
    @ObservationIgnored private let store: OrderHomeStore
    @ObservationIgnored private let configuration: CloudConfiguration?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var latestSnapshot: CloudKitchenSnapshot?
    @ObservationIgnored private var drafts: [String: Reaction] = [:]
    @ObservationIgnored private var draftSessionID: String?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var contextVersion = 0
    @ObservationIgnored private var refreshVersion = 0
    @ObservationIgnored private var applicationActive = true

    var isConfigured: Bool { service.isConfigured }
    var isSharedKitchen: Bool { activeHouseholdID != nil && identity != nil && store.isSharedPresentation }
    var appleSignInEnabled: Bool { configuration?.appleSignInEnabled == true }
    var hasActiveDinner: Bool { latestSnapshot?.session != nil }
    var activeDinnerID: String? { latestSnapshot?.session?.id }
    var canManageHousehold: Bool { identity?.id == latestSnapshot?.household.ownerUserID && isSharedKitchen }
    var canManageDinner: Bool {
        guard isSharedKitchen, let ownID = authenticatedMemberID else { return false }
        if let session = latestSnapshot?.session { return session.headChefID == ownID }
        return canManageHousehold
    }
    var authenticatedMemberID: String? {
        guard let identity else { return nil }
        return latestSnapshot?.members.first { $0.userID == identity.id }?.id
    }
    var currentOrderSubmitted: Bool {
        guard let ownID = authenticatedMemberID else { return false }
        return latestSnapshot?.orders.first { $0.memberID == ownID }?.submittedAt != nil
    }
    var canSubmitOrder: Bool {
        isSharedKitchen && store.session.stage == .voting && !isBusy &&
        (!store.currentMember.attending || store.hasReactedToAll(memberID: store.selectedMemberID))
    }

    /// `service` defaults to the Supabase client. The default is created in the
    /// body rather than as a default argument, because default arguments are not
    /// main-actor isolated and the client's initializer is.
    init(service: (any KitchenCloudService)? = nil, store: OrderHomeStore,
         configuration: CloudConfiguration? = try? CloudConfiguration.load().get(), defaults: UserDefaults = .standard) {
        if let service {
            self.service = service
        } else if let configuration {
            self.service = SupabaseKitchenService(configuration: configuration)
        } else {
            self.service = SupabaseKitchenService()
        }
        self.store = store
        self.configuration = configuration
        self.defaults = defaults
    }

    func restore() async {
        guard isConfigured, identity == nil, !isBusy else { return }
        let version = contextVersion
        isBusy = true
        defer { isBusy = false }
        do {
            let restored = try await service.restoreSession()
            guard contextVersion == version else { return }
            identity = restored
            guard let restored else { return }
            kitchens = try await service.listKitchens()
            guard contextVersion == version else { return }
            if defaults.bool(forKey: enabledKey(userID: restored.id)),
               let id = defaults.string(forKey: selectionKey(userID: restored.id)),
               kitchens.contains(where: { $0.id == id }) {
                try await activate(id)
            }
        } catch { fail(error) }
    }

    func requestEmailCode(_ email: String) async -> Bool {
        await run { try await self.service.requestEmailCode(email: email) }
    }

    func verifyEmailCode(email: String, code: String) async -> Bool {
        await run {
            self.identity = try await self.service.verifyEmailCode(email: email, code: code)
            self.kitchens = try await self.service.listKitchens()
        }
    }

    func signInWithApple(idToken: String, nonce: String, displayName: String?) async -> Bool {
        await run {
            self.identity = try await self.service.signInWithApple(idToken: idToken, nonce: nonce, displayName: displayName)
            self.kitchens = try await self.service.listKitchens()
        }
    }

    func createKitchen(name: String, personName: String, mode: HouseholdMode) async -> Bool {
        await run {
            guard self.identity != nil else { throw CloudServiceError.signedOut }
            let id = try await self.service.createKitchen(name: name, mode: mode, displayName: personName)
            self.kitchens = try await self.service.listKitchens()
            try await self.activate(id)
            // The owner opens the first dinner so a joining partner can nominate.
            try await self.service.perform(.openDinner(householdID: id, deadline: .now.addingTimeInterval(3600)))
            try await self.loadCurrentSnapshot()
        }
    }

    func joinKitchen(token: String, personName: String) async -> Bool {
        await run {
            guard self.identity != nil else { throw CloudServiceError.signedOut }
            guard let value = self.invitationToken(from: token) else { throw CloudServiceError.invalidInvitation }
            let id = try await self.service.joinKitchen(token: value, displayName: personName)
            self.kitchens = try await self.service.listKitchens()
            try await self.activate(id)
            self.pendingInviteToken = nil
        }
    }

    func selectKitchen(_ id: String) async {
        _ = await run {
            guard self.kitchens.contains(where: { $0.id == id }) else { throw CloudServiceError.permissionDenied }
            try await self.activate(id)
        }
    }

    func generateInvite() async -> CloudInvitation? {
        guard canManageHousehold, let id = activeHouseholdID else { fail(CloudServiceError.permissionDenied); return nil }
        guard !isBusy else { return nil }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { return try await service.createInvite(householdID: id) }
        catch { fail(error); return nil }
    }

    func inviteURL(for invitation: CloudInvitation) -> URL {
        var components = URLComponents(url: configuration?.inviteBaseURL ?? URL(string: "orderhome://join")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: invitation.token)]
        return components.url!
    }

    func handleURL(_ url: URL) -> Bool {
        guard let token = invitationToken(from: url.absoluteString) else { return false }
        pendingInviteToken = token
        showAccountSheet = true
        return true
    }

    func invitationToken(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil { return trimmed.lowercased() }
        guard let components = URLComponents(string: trimmed), components.user == nil, components.password == nil,
              components.fragment == nil else { return nil }
        let custom = components.scheme?.lowercased() == "orderhome" && components.host?.lowercased() == "join" && components.path.isEmpty
        let https: Bool
        if let allowed = configuration?.inviteBaseURL {
            https = components.scheme?.lowercased() == "https" && components.host?.lowercased() == allowed.host?.lowercased() &&
                components.port == allowed.port && components.path == allowed.path
        } else { https = false }
        guard custom || https, let items = components.queryItems, items.count == 1,
              items[0].name == "token", let token = items[0].value,
              token.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return token.lowercased()
    }

    func useLocalKitchen() {
        if let identity { defaults.set(false, forKey: enabledKey(userID: identity.id)) }
        clearSharedPresentation()
        showAccountSheet = false
        errorMessage = nil
    }

    func signOut() async {
        guard !isBusy else { return }
        isBusy = true
        let prior = identity
        clearSharedPresentation()
        identity = nil
        kitchens = []
        if let prior { defaults.set(false, forKey: enabledKey(userID: prior.id)) }
        do { try await service.signOut() } catch { fail(error) }
        isBusy = false
    }

    func refresh() async {
        guard isSharedKitchen, !isBusy else { return }
        do { try await loadCurrentSnapshot() }
        catch {
            fail(error)
            if error as? CloudServiceError == .permissionDenied || error as? CloudServiceError == .signedOut {
                clearSharedPresentation()
                if error as? CloudServiceError == .signedOut { identity = nil; kitchens = [] }
            }
        }
    }

    func recordReaction(_ reaction: Reaction, for recipeID: String) {
        guard isSharedKitchen, !isBusy, store.session.stage == .voting,
              let memberID = authenticatedMemberID else { return }
        store.selectedMemberID = memberID
        if draftSessionID != store.session.id { drafts = [:]; draftSessionID = store.session.id }
        drafts[recipeID] = reaction
        hasUnsubmittedChanges = true
        store.vote(reaction, for: recipeID)
    }

    func submitOrder() async -> Bool {
        guard canSubmitOrder, let sessionID = activeDinnerID else {
            errorMessage = "React to every dish before sending your order, or mark yourself as eating out."
            return false
        }
        return await run {
            guard let snapshot = self.latestSnapshot else { throw CloudServiceError.dinnerChanged }
            let reactions = snapshot.pitches.compactMap { pitch -> CloudReaction? in
                guard let reaction = self.store.reaction(for: pitch.recipeID) else { return nil }
                return CloudReaction(pitchID: pitch.id, weight: reaction.rawValue)
            }
            try await self.service.perform(.submitOrder(sessionID: sessionID, reactions: reactions,
                attending: self.store.currentMember.attending, note: self.store.orders[self.store.selectedMemberID] ?? ""))
            self.drafts = [:]
            self.hasUnsubmittedChanges = false
            try await self.loadCurrentSnapshot()
        }
    }

    func nominate(_ recipe: Recipe) async {
        _ = await run {
            guard RecipeCatalog.all.contains(where: { $0.id == recipe.id }) else {
                self.errorMessage = "Saved creator links stay in your personal collection. Choose a house recipe for this shared dinner."
                return
            }
            let sessionID = try await self.ensureDinner()
            try await self.service.perform(.nominate(sessionID: sessionID, recipeID: recipe.id))
            try await self.loadCurrentSnapshot()
        }
    }

    func removePitch(_ recipeID: String) async {
        _ = await command { .removePitch(sessionID: try self.requireDinner(), recipeID: recipeID) }
    }

    func startVoting() async -> Bool {
        await command { .startVoting(sessionID: try self.requireChefDinner()) }
    }

    func lockWinner() async { _ = await command { .closeVoting(sessionID: try self.requireChefDinner()) } }
    func startCooking() async {
        _ = await command { .advanceKitchen(sessionID: try self.requireChefDinner(), status: "cooking", stepIndex: 0, missingGroceries: Array(self.store.session.missingIngredientIDs).sorted()) }
    }
    func advanceStep() async {
        _ = await command {
            .advanceKitchen(sessionID: try self.requireChefDinner(), status: "cooking",
                stepIndex: min(self.store.session.stepIndex + 1, max(0, (self.store.winner?.steps.count ?? 1) - 1)),
                missingGroceries: Array(self.store.session.missingIngredientIDs).sorted())
        }
    }
    func ringDinnerBell() async -> Bool {
        await command {
            .advanceKitchen(sessionID: try self.requireChefDinner(), status: "served",
                stepIndex: max(0, (self.store.winner?.steps.count ?? 1) - 1),
                missingGroceries: Array(self.store.session.missingIngredientIDs).sorted())
        }
    }
    func toggleMissing(_ id: String) async {
        _ = await command {
            var missing = self.store.session.missingIngredientIDs
            if missing.contains(id) { missing.remove(id) } else { missing.insert(id) }
            return .advanceKitchen(sessionID: try self.requireChefDinner(), status: self.serverStatus,
                stepIndex: self.store.session.stepIndex, missingGroceries: Array(missing).sorted())
        }
    }
    func updateOwnPreferences(attending: Bool, note: String) async -> Bool {
        await command { .savePreferences(sessionID: try self.requireDinner(), attending: attending, note: note) }
    }
    func saveProfile(name: String, emoji: String, dietaryNotes: String) async -> Bool {
        await command {
            guard let id = self.activeHouseholdID else { throw CloudServiceError.signedOut }
            return .updateProfile(householdID: id, name: name, emoji: emoji,
                dietaryTags: dietaryNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [dietaryNotes])
        }
    }
    func changeMode(_ mode: HouseholdMode) async {
        _ = await command {
            guard self.canManageHousehold, let id = self.activeHouseholdID else { throw CloudServiceError.permissionDenied }
            return .setMode(householdID: id, mode: mode)
        }
    }
    func extendVoting(deadline: Date = .now.addingTimeInterval(1800)) async {
        _ = await command { .extendVoting(sessionID: try self.requireChefDinner(), deadline: deadline) }
    }
    func newDinner() async {
        _ = await run {
            guard self.canManageDinner, let id = self.activeHouseholdID else { throw CloudServiceError.permissionDenied }
            if let session = self.latestSnapshot?.session, session.status != "served" {
                try await self.service.perform(.cancelDinner(sessionID: session.id))
            }
            self.drafts = [:]
            self.hasUnsubmittedChanges = false
            try await self.service.perform(.openDinner(householdID: id, deadline: .now.addingTimeInterval(3600)))
            try await self.loadCurrentSnapshot()
        }
    }

    func setApplicationActive(_ active: Bool) {
        applicationActive = active
        if active, let id = activeHouseholdID, isSharedKitchen {
            startObserving(id)
            Task { [weak self] in await self?.refresh() }
        } else { stopObserving() }
    }

    private func command(_ build: () throws -> CloudCommand) async -> Bool {
        await run {
            let value = try build()
            try await self.service.perform(value)
            try await self.loadCurrentSnapshot()
        }
    }
    private func run(_ operation: () async throws -> Void) async -> Bool {
        guard isConfigured else { fail(CloudServiceError.notConfigured); return false }
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do { try await operation(); return true }
        catch { fail(error); return false }
    }
    private func requireDinner() throws -> String {
        guard isSharedKitchen, let id = activeDinnerID else { throw CloudServiceError.dinnerChanged }
        return id
    }
    private func requireChefDinner() throws -> String {
        guard canManageDinner else { throw CloudServiceError.permissionDenied }
        return try requireDinner()
    }
    private var serverStatus: String {
        latestSnapshot?.session?.status ?? "pitching"
    }
    private func ensureDinner() async throws -> String {
        if let id = activeDinnerID, serverStatus == "pitching" { return id }
        guard canManageHousehold, let householdID = activeHouseholdID,
              latestSnapshot?.session == nil || serverStatus == "served" else { throw CloudServiceError.permissionDenied }
        try await service.perform(.openDinner(householdID: householdID, deadline: .now.addingTimeInterval(3600)))
        try await loadCurrentSnapshot()
        return try requireDinner()
    }
    private func activate(_ id: String) async throws {
        guard let identity else { throw CloudServiceError.signedOut }
        contextVersion += 1
        stopObserving()
        drafts = [:]
        draftSessionID = nil
        hasUnsubmittedChanges = false
        let snapshot = try await service.snapshot(householdID: id)
        guard snapshot.household.id == id else { throw CloudServiceError.permissionDenied }
        try store.applySharedSnapshot(snapshot, userID: identity.id)
        latestSnapshot = snapshot
        activeHouseholdID = id
        draftSessionID = snapshot.session?.id
        defaults.set(id, forKey: selectionKey(userID: identity.id))
        defaults.set(true, forKey: enabledKey(userID: identity.id))
        connectionStatus = "Up to date"
        lastUpdatedAt = .now
        if applicationActive { startObserving(id) }
    }
    private func loadCurrentSnapshot() async throws {
        guard let householdID = activeHouseholdID, let userID = identity?.id else { throw CloudServiceError.signedOut }
        let context = contextVersion
        refreshVersion += 1
        let refresh = refreshVersion
        let snapshot = try await service.snapshot(householdID: householdID)
        guard context == contextVersion, refresh == refreshVersion,
              activeHouseholdID == householdID, identity?.id == userID else { return }
        guard snapshot.household.id == householdID else { throw CloudServiceError.permissionDenied }
        if draftSessionID != snapshot.session?.id || snapshot.session?.status != "voting" {
            drafts = [:]
            hasUnsubmittedChanges = false
        }
        try store.applySharedSnapshot(snapshot, userID: userID, drafts: drafts)
        latestSnapshot = snapshot
        draftSessionID = snapshot.session?.id
        connectionStatus = "Up to date"
        lastUpdatedAt = .now
    }
    private func startObserving(_ householdID: String) {
        stopObserving()
        let context = contextVersion
        let stream = service.changes(householdID: householdID)
        changesTask = Task { [weak self] in
            for await _ in stream {
                guard !Task.isCancelled, let self, self.contextVersion == context else { break }
                await self.refresh()
            }
        }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                guard let self, self.contextVersion == context else { break }
                // Polling is a recovery path for missed socket events/reconnects.
                await self.refresh()
                if !self.isBusy, self.store.session.stage == .voting,
                   self.store.session.deadline <= .now, let sessionID = self.activeDinnerID {
                    _ = await self.command { .expireVoting(sessionID: sessionID) }
                }
            }
        }
    }
    private func stopObserving() {
        changesTask?.cancel()
        pollingTask?.cancel()
        changesTask = nil
        pollingTask = nil
    }
    private func clearSharedPresentation() {
        contextVersion += 1
        refreshVersion += 1
        stopObserving()
        activeHouseholdID = nil
        latestSnapshot = nil
        drafts = [:]
        draftSessionID = nil
        hasUnsubmittedChanges = false
        connectionStatus = "On this iPhone"
        lastUpdatedAt = nil
        store.restoreLocalKitchen()
    }
    private func fail(_ error: Error) {
        errorMessage = (error as? CloudServiceError)?.localizedDescription ?? "Your shared kitchen could not be updated. Please try again."
        if isSharedKitchen { connectionStatus = "Waiting to reconnect" }
    }
    private func selectionKey(userID: String) -> String { "orderhome.shared.selection.\(configuration?.projectURL.host ?? "test").\(userID)" }
    private func enabledKey(userID: String) -> String { "orderhome.shared.enabled.\(configuration?.projectURL.host ?? "test").\(userID)" }
}
