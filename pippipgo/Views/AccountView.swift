import SwiftUI

struct AccountDeletionErrorView: View {
    let message: String
    let retry: () -> Void
    let signOut: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Account deletion incomplete", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
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
                Text(message)
            } actions: {
                Button("Try again", action: retry).buttonStyle(.borderedProminent)
                Button("Sign out", role: .destructive, action: signOut)
            }
            .navigationTitle("PipPipGo")
        }
    }
}
