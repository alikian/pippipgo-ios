import SwiftUI

struct WelcomeView: View {
    let isBusy: Bool
    let errorMessage: String?
    let signIn: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    PipWelcomeArtwork()
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .padding(.top, 40)
                    VStack(spacing: 10) {
                        Text("PipPipGo")
                            .font(.largeTitle.bold())
                        Text("A thoughtful local guide for the journey ahead.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityLabel("Sign-in error: \(errorMessage)")
                    }
                    Button(action: signIn) {
                        HStack(spacing: 12) {
                            if isBusy { ProgressView().tint(.white) }
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text(LocalizedStringKey(isBusy ? "Connecting…" : "Sign in or create account"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(isBusy)
                    Text("Use Google or email and password. When creating an account, enter your email address as both username and email.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    AppVersionView()
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            AppLanguageMenu().padding()
        }
    }
}

/// Displays only the illustration within the supplied screen mockup.
/// Keep the original asset intact; real text and controls remain accessible.
struct PipWelcomeArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            Image("PipWelcome")
                .resizable()
                .frame(width: geometry.size.width, height: geometry.size.width * 1848 / 851)
                .offset(y: -geometry.size.width * 235 / 851)
        }
        .aspectRatio(851.0 / 700.0, contentMode: .fit)
        .clipped()
        .accessibilityLabel("Pip, a fluffy dog, on a sunny seaside terrace")
        .allowsHitTesting(false)
    }
}
