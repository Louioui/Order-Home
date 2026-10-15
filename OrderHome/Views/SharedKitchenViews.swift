import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

/// Account access and household membership stay separate: opening an invitation
/// never joins a kitchen until the signed-in person chooses Join kitchen.
struct SharedKitchenView: View {
    @Environment(CloudKitchenController.self) private var cloud
    @Environment(OrderHomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sentTo = ""
    @State private var code = ""
    @State private var codeRequested = false
    @State private var personName = ""
    @State private var kitchenName = ""
    @State private var inviteToken = ""
    @State private var mode: HouseholdMode = .family
    @State private var appleNonce: String?
    @State private var appleError: String?
    @State private var showingInvite = false
    @State private var confirmingDeleteAccount = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SheetHeader(title: "Your shared kitchen", subtitle: "Your people. One dinner plan. Every iPhone.")
                if !cloud.isConfigured {
                    connectionPending
                } else if cloud.identity == nil {
                    signIn
                } else {
                    signedIn
                }
                if cloud.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().tint(OHTheme.accent)
                        Text("Connecting your kitchen…").font(.system(size: 12))
                    }.foregroundStyle(OHTheme.muted).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("sharedKitchenBusy")
                }
                if let message = appleError ?? cloud.errorMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.system(size: 13)).foregroundStyle(OHTheme.accent)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityIdentifier("sharedKitchenError")
                }
            }.padding(24)
        }
        .background(OHTheme.background)
        .sheet(isPresented: $showingInvite) { SharedKitchenInviteView() }
        .confirmationDialog("Delete Account & All Data?", isPresented: $confirmingDeleteAccount, titleVisibility: .visible) {
            Button("Delete Account & Data", role: .destructive) {
                Task {
                    await cloud.signOut()
                    store.resetAllData()
                    dismiss()
                }
            }
        } message: {
            Text("This will sign you out of Order Home, delete all local kitchen records, votes, and history, and clear the shared App Group container.")
        }
        .onAppear {
            if let pending = cloud.pendingInviteToken { inviteToken = pending }
            if personName.isEmpty { personName = cloud.identity?.displayName ?? "" }
        }
        .onChange(of: cloud.pendingInviteToken) { _, pending in
            if let pending { inviteToken = pending }
        }
        .onChange(of: cloud.identity?.id) { _, _ in
            if personName.isEmpty { personName = cloud.identity?.displayName ?? "" }
        }
    }

    private var connectionPending: some View {
        VStack(alignment: .leading, spacing: 17) {
            Image(systemName: "house.and.flag").font(.system(size: 36)).foregroundStyle(OHTheme.green)
            Text("Shared kitchens are being connected.").font(OHTheme.serif(27)).foregroundStyle(OHTheme.ink)
            Text("You can still plan dinner in your kitchen on this iPhone. Shared kitchens will let everyone bring their own phone to the table.")
                .font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
            PrimaryButton(title: "Continue on this iPhone", systemImage: "arrow.right") { dismiss() }
        }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 21) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: cloud.pendingInviteToken == nil ? "A PLACE FOR EVERYONE" : "YOU’VE BEEN INVITED")
                Text(cloud.pendingInviteToken == nil ? "Dinner together, wherever you are." : "There’s a seat waiting for you.")
                    .font(OHTheme.serif(29)).foregroundStyle(OHTheme.ink)
                Text(cloud.pendingInviteToken == nil
                     ? "Sign in to create a kitchen or join your people. Your dinner choices and kitchen ticket will stay together across phones."
                     : "Sign in first, then choose your name and join the kitchen. Keep this invitation for yourself.")
                    .font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
            }
            if cloud.appleSignInEnabled {
                SignInWithAppleButton(.continue, onRequest: prepareAppleRequest, onCompletion: finishAppleRequest)
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54).clipShape(RoundedRectangle(cornerRadius: 15))
                    .disabled(cloud.isBusy).accessibilityIdentifier("signInWithApple")
                HStack {
                    Rectangle().fill(OHTheme.line).frame(height: 1)
                    Text("OR USE EMAIL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(OHTheme.muted)
                    Rectangle().fill(OHTheme.line).frame(height: 1)
                }
            }
            if codeRequested { emailVerification } else { emailEntry }
            Text("Use the same sign-in method each time to return to your kitchen.")
                .font(.system(size: 11)).foregroundStyle(OHTheme.muted).lineSpacing(4)
        }
    }

    private var emailEntry: some View {
        VStack(alignment: .leading, spacing: 15) {
            field("YOUR EMAIL", placeholder: "you@example.com", text: $email)
                .textContentType(.emailAddress).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("sharedKitchenEmail")
            PrimaryButton(title: "Email me a sign-in code", systemImage: "envelope") {
                appleError = nil
                let destination = email.trimmingCharacters(in: .whitespacesAndNewlines)
                Task {
                    if await cloud.requestEmailCode(destination) {
                        sentTo = destination
                        code = ""
                        codeRequested = true
                    }
                }
            }.disabled(cloud.isBusy || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("requestEmailCode")
        }
    }

    private var emailVerification: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Check \(sentTo) for your sign-in code.").font(.system(size: 13)).foregroundStyle(OHTheme.ink)
            field("SIGN-IN CODE", placeholder: "Code from your email", text: $code)
                .textContentType(.oneTimeCode).keyboardType(.numberPad)
                .accessibilityIdentifier("sharedKitchenEmailCode")
                .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(8)) }
            PrimaryButton(title: "Continue to my kitchen", systemImage: "arrow.right") {
                appleError = nil
                Task { _ = await cloud.verifyEmailCode(email: sentTo, code: code) }
            }.disabled(cloud.isBusy || code.count < 6).accessibilityIdentifier("verifyEmailCode")
            HStack {
                Button("Send a new code") {
                    Task { if await cloud.requestEmailCode(sentTo) { code = "" } }
                }
                Spacer()
                Button("Use another email") { codeRequested = false; code = "" }
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.accent).disabled(cloud.isBusy)
        }.padding(19).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 24) {
            accountCard
            if !cloud.kitchens.isEmpty { kitchenList }
            if cloud.isSharedKitchen {
                if cloud.canManageHousehold {
                    PrimaryButton(title: "Invite someone to the table", systemImage: "person.badge.plus") { showingInvite = true }
                        .disabled(cloud.isBusy)
                } else {
                    Text("The kitchen owner can invite more people to your table.")
                        .font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                }
            }
            kitchenMembership
            Button {
                cloud.useLocalKitchen()
                dismiss()
            } label: {
                Label("Use my kitchen on this iPhone", systemImage: "iphone")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(OHTheme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.disabled(cloud.isBusy)
            Button(role: .destructive) {
                confirmingDeleteAccount = true
            } label: {
                Label("Delete Account & All Data", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .disabled(cloud.isBusy)
            .accessibilityIdentifier("deleteAccountButton")
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 31)).foregroundStyle(OHTheme.green)
                VStack(alignment: .leading, spacing: 5) {
                    Text("You’re signed in").font(.system(size: 14, weight: .semibold)).foregroundStyle(OHTheme.ink)
                    Text(cloud.identity?.email ?? cloud.identity?.displayName ?? "Your Order Home account")
                        .font(.system(size: 12)).foregroundStyle(OHTheme.muted).textSelection(.enabled)
                }
                Spacer()
                Button("Sign out") { Task { await cloud.signOut() } }
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(OHTheme.accent).disabled(cloud.isBusy)
            }
            if cloud.isSharedKitchen { SharedKitchenConnectionStatus() }
        }.padding(19).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private var kitchenList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "YOUR KITCHENS")
            ForEach(cloud.kitchens) { kitchen in
                Button {
                    Task {
                        await cloud.selectKitchen(kitchen.id)
                        if cloud.activeHouseholdID == kitchen.id && cloud.isSharedKitchen { dismiss() }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: kitchen.mode == .couple ? "heart" : "house")
                            .font(.system(size: 20)).foregroundStyle(OHTheme.green).frame(width: 27)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(kitchen.name).font(.system(size: 15, weight: .semibold))
                            Text(kitchen.mode.title).font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                        }
                        Spacer()
                        Image(systemName: kitchen.id == cloud.activeHouseholdID && cloud.isSharedKitchen ? "checkmark.circle.fill" : "arrow.right")
                            .foregroundStyle(OHTheme.green)
                    }.foregroundStyle(OHTheme.ink).padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(cloud.isBusy)
            }
        }
    }

    private var kitchenMembership: some View {
        VStack(alignment: .leading, spacing: 23) {
            field("YOUR NAME AT THE TABLE", placeholder: "e.g. Alex", text: $personName)
                .textContentType(.givenName).accessibilityIdentifier("sharedKitchenPersonName")
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Have an invitation?")
                Text("Paste the invitation link sent by your kitchen owner. Each invitation brings one person to the table.")
                    .font(.system(size: 12)).foregroundStyle(OHTheme.muted).lineSpacing(4)
                TextField("Paste your invitation link", text: $inviteToken, axis: .vertical)
                    .font(.system(size: 13)).lineLimit(2...4)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(17).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("sharedKitchenInviteToken")
                PrimaryButton(title: "Join kitchen", systemImage: "person.2") {
                    Task {
                        if await cloud.joinKitchen(token: inviteToken, personName: personName) { dismiss() }
                    }
                }.disabled(cloud.isBusy || cleanName.isEmpty || inviteToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("joinSharedKitchen")
            }
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Start a new kitchen")
                field("NAME YOUR KITCHEN", placeholder: "e.g. The Sunday Kitchen", text: $kitchenName)
                    .accessibilityIdentifier("sharedKitchenName")
                Picker("Your kind of table", selection: $mode) {
                    ForEach(HouseholdMode.allCases) { choice in Text(choice.title).tag(choice) }
                }.pickerStyle(.segmented)
                Text(mode.subtitle).font(.system(size: 12)).foregroundStyle(OHTheme.muted)
                PrimaryButton(title: "Create shared kitchen", systemImage: "house") {
                    Task {
                        if await cloud.createKitchen(name: kitchenName, personName: personName, mode: mode) { dismiss() }
                    }
                }.disabled(cloud.isBusy || cleanName.isEmpty || kitchenName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("createSharedKitchen")
            }
        }
    }

    private var cleanName: String { personName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            TextField(placeholder, text: text).font(.system(size: 14)).padding(17)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        appleError = nil
        appleNonce = nil
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            appleError = "Apple sign-in could not start securely. Please try again."
            return
        }
        let rawNonce = bytes.map { String(format: "%02x", $0) }.joined()
        appleNonce = rawNonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func finishAppleRequest(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                appleError = "Apple sign-in could not be completed. Please try again."
                appleNonce = nil
                return
            }
            let displayName = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            appleNonce = nil
            Task { _ = await cloud.signInWithApple(idToken: token, nonce: nonce, displayName: displayName) }
        case .failure(let error):
            appleNonce = nil
            if let authorizationError = error as? ASAuthorizationError, authorizationError.code == .canceled { return }
            appleError = "Apple sign-in could not be completed. Please try again."
        }
    }
}

struct SharedKitchenInviteView: View {
    @Environment(CloudKitchenController.self) private var cloud
    @State private var invitation: CloudInvitation?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                SheetHeader(title: "Pull up another chair.", subtitle: "Invite one person into your shared kitchen.")
                Image(systemName: "person.2.wave.2").font(.system(size: 46)).foregroundStyle(OHTheme.green)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                if !cloud.isSharedKitchen || !cloud.canManageHousehold {
                    Text("Ask your kitchen owner for an invitation.").font(.system(size: 14)).foregroundStyle(OHTheme.muted)
                } else if let invitation, invitation.expiresAt > Date() {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("A seat at \(invitation.householdName)").font(OHTheme.serif(27)).foregroundStyle(OHTheme.ink)
                        Text("Send this private invitation to the person you want to join. They’ll sign in on their own iPhone and choose Join kitchen.")
                            .font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                        ShareLink(item: shareMessage(invitation)) {
                            Label("Share kitchen invitation", systemImage: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                                .background(OHTheme.accent, in: RoundedRectangle(cornerRadius: 17))
                        }.accessibilityIdentifier("shareKitchenInvitation")
                        Label("One person · Expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "lock")
                            .font(.system(size: 11)).foregroundStyle(OHTheme.muted)
                    }.padding(21).background(.white, in: RoundedRectangle(cornerRadius: 22))
                } else {
                    Text("Each invitation can be used once. Create a separate invitation for every person you’d like at the table.")
                        .font(.system(size: 13)).foregroundStyle(OHTheme.muted).lineSpacing(5)
                    PrimaryButton(title: "Create an invitation", systemImage: "person.badge.plus") {
                        Task { invitation = await cloud.generateInvite() }
                    }.disabled(cloud.isBusy).accessibilityIdentifier("generateKitchenInvitation")
                }
                if cloud.isBusy { ProgressView("Making room at the table…").font(.system(size: 12)).tint(OHTheme.accent) }
                if let error = cloud.errorMessage {
                    Text(error).font(.system(size: 13)).foregroundStyle(OHTheme.accent)
                }
            }.padding(24)
        }.background(OHTheme.background)
    }

    private func shareMessage(_ invitation: CloudInvitation) -> String {
        "Join me at \(invitation.householdName) on Order Home 🍽️\nPick dinner together from your own iPhone.\n\(cloud.inviteURL(for: invitation).absoluteString)\nThis private invitation is for one person and expires \(invitation.expiresAt.formatted(date: .abbreviated, time: .shortened))."
    }
}

struct SharedKitchenConnectionStatus: View {
    @Environment(CloudKitchenController.self) private var cloud

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if cloud.isBusy { ProgressView().controlSize(.mini).tint(OHTheme.green) }
            else { Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12)) }
            Text(cloud.connectionStatus).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { Task { await cloud.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
            }.accessibilityLabel("Refresh shared kitchen").disabled(cloud.isBusy)
        }.foregroundStyle(OHTheme.green).accessibilityIdentifier("sharedKitchenConnectionStatus")
    }
}
