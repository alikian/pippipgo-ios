import SwiftUI

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
