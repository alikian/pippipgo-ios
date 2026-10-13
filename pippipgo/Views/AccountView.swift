import SwiftUI

struct AccountDeletionErrorView: View {
    let message: String
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Account deletion incomplete", systemImage: "exclamationmark.triangle")
        } description: {
            Text(LocalizedStringKey(message))
        } actions: {
            Button("Retry deletion", role: .destructive, action: retry)
                .accessibilityIdentifier("account.retryDeletion")
            Button("Sign out", action: signOut)
        }
    }
}

struct AccountLoadingView: View {
    var body: some View {
        StartupLoadingView(message: "Loading your account…")
    }
}

struct AccountErrorView: View {
    let message: String
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Account unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(LocalizedStringKey(message))
            } actions: {
                Button("Try again", action: retry).buttonStyle(.borderedProminent)
                Button("Sign out", role: .destructive, action: signOut)
            }
            .navigationTitle("PipPipGo")
        }
    }
}

/// Versioned, device-local permission scoped to the authenticated issuer and subject.
@MainActor @Observable
final class AISharingConsent {
    static let shared = AISharingConsent()
    private static let disclosureVersion = 1
    private var accountKey: String?
    private var epoch = UUID()
    private(set) var allowed = false
    var presented = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func configure(accessToken: String) {
        // The backend has already authenticated this token. Claims only scope local UI preferences.
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { reset(); return }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let issuer = claims["iss"] as? String, let subject = claims["sub"] as? String,
              !issuer.isEmpty, !subject.isEmpty else { reset(); return }
        let key = "pip.aiSharingConsent.\(issuer).\(subject)"
        guard accountKey != key else { return }
        reset()
        accountKey = key
        allowed = UserDefaults.standard.integer(forKey: key) == Self.disclosureVersion
    }

    func forgetAccount() {
        if let accountKey { UserDefaults.standard.removeObject(forKey: accountKey) }
        reset()
    }

    func request() async throws {
        try Task.checkCancellation()
        if allowed { return }
        let ticket = epoch
        let id = UUID()
        let approved = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
                presented = true
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
        try Task.checkCancellation()
        guard approved, allowed, epoch == ticket else { throw APIClientError.invalidRequest("AI sharing was not allowed. You can still use your saved travel information.") }
    }

    func resolve(_ approved: Bool) {
        allowed = approved
        if approved, let accountKey {
            UserDefaults.standard.set(Self.disclosureVersion, forKey: accountKey)
        }
        presented = false
        let pending = waiters.values
        waiters.removeAll()
        for waiter in pending { waiter.resume(returning: approved) }
    }

    func reset() {
        epoch = UUID()
        resolve(false)
        accountKey = nil
    }

    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: false)
        if waiters.isEmpty { presented = false }
    }
}

struct AISharingConsentView: View {
    var consent: AISharingConsent = .shared
    let deleteAccount: () -> Void
    @State private var confirmDeletion = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Allow sharing with OpenAI?").font(.title2.bold())
                    Text("ai.sharing.details")
                    Link("Privacy policy", destination: URL(string: "https://pippipgo.com/privacy")!)
                    Text("ai.sharing.acceptance").font(.callout)
                    Button("Allow sharing with OpenAI") { consent.resolve(true) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("aiConsent.allow")
                    Button("Deny and delete account", role: .destructive) { confirmDeletion = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .accessibilityIdentifier("aiConsent.deny")
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("AI privacy")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        .alert("Permanently delete your PipPipGo account?", isPresented: $confirmDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete account", role: .destructive, action: deleteAccount)
        } message: {
            Text("This permanently deletes your PipPipGo profile, companions, trips, saved preferences and conversations. You will be signed out and cannot undo this. Your Google account is not deleted.")
        }
    }
}
