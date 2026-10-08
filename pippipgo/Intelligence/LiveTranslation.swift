import SwiftUI
import AVFoundation

/// Languages accepted by the backend interpreter (`/v1/translate/live`). Keep in sync with
/// backend `app/live_translation.py`.
struct TranslationLanguage: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let nativeName: String
    var id: String { code }

    /// Picker order requested by the user. Retained languages still decode saved choices.
    static let all: [TranslationLanguage] = ["zh", "ja", "ko", "vi", "fil", "tl", "fa", "tr", "ar", "ru", "it", "fr", "en"]
        .compactMap { code in supported.first { $0.code == code } }

    private static let supported: [TranslationLanguage] = [
        .init(code: "fil", name: "Filipino", nativeName: "Filipino"),
        .init(code: "tl", name: "Tagalog", nativeName: "Tagalog"),
        .init(code: "ar", name: "Arabic", nativeName: "العربية"),
        .init(code: "zh", name: "Chinese", nativeName: "中文"),
        .init(code: "nl", name: "Dutch", nativeName: "Nederlands"),
        .init(code: "en", name: "English", nativeName: "English"),
        .init(code: "fr", name: "French", nativeName: "Français"),
        .init(code: "de", name: "German", nativeName: "Deutsch"),
        .init(code: "el", name: "Greek", nativeName: "Ελληνικά"),
        .init(code: "he", name: "Hebrew", nativeName: "עברית"),
        .init(code: "hi", name: "Hindi", nativeName: "हिन्दी"),
        .init(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia"),
        .init(code: "it", name: "Italian", nativeName: "Italiano"),
        .init(code: "ja", name: "Japanese", nativeName: "日本語"),
        .init(code: "ko", name: "Korean", nativeName: "한국어"),
        .init(code: "fa", name: "Farsi", nativeName: "فارسی"),
        .init(code: "pl", name: "Polish", nativeName: "Polski"),
        .init(code: "pt", name: "Portuguese", nativeName: "Português"),
        .init(code: "ru", name: "Russian", nativeName: "Русский"),
        .init(code: "es", name: "Spanish", nativeName: "Español"),
        .init(code: "sv", name: "Swedish", nativeName: "Svenska"),
        .init(code: "th", name: "Thai", nativeName: "ไทย"),
        .init(code: "tr", name: "Turkish", nativeName: "Türkçe"),
        .init(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt"),
    ]

    static func language(_ code: String) -> TranslationLanguage? { supported.first { $0.code == code } }
}

/// The traveler's language and the other person's language for a two-way interpreter session.
struct TranslationPair: Equatable, Sendable {
    let mine: TranslationLanguage
    let theirs: TranslationLanguage
    var listenOnly = false

    init?(mine: String, theirs: String, listenOnly: Bool = false) {
        guard mine != theirs, let a = TranslationLanguage.language(mine), let b = TranslationLanguage.language(theirs) else { return nil }
        self.mine = a; self.theirs = b; self.listenOnly = listenOnly
    }

    /// Value of the `X-Pip-Translate` WebSocket header.
    var headerValue: String { "\(mine.code),\(theirs.code)" }
    var swapped: TranslationPair { TranslationPair(mine: theirs.code, theirs: mine.code, listenOnly: listenOnly)! }

    init?(headerValue: String) {
        let parts = headerValue.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { return nil }
        self.init(mine: parts[0], theirs: parts[1])
    }

    static func defaultPair(locale: Locale = .current) -> TranslationPair {
        let device = locale.language.languageCode?.identifier ?? "en"
        let mine = TranslationLanguage.all.contains { $0.code == device } ? device : "en"
        return TranslationPair(mine: mine, theirs: mine == "en" ? "fa" : "en")!
    }

    private static let storageKey = "translationLanguages"
    static func saved(_ defaults: UserDefaults = .standard) -> TranslationPair {
        var pair = defaults.string(forKey: storageKey).flatMap(TranslationPair.init(headerValue:)) ?? defaultPair()
        pair.listenOnly = defaults.bool(forKey: "translationListenOnly")
        return pair
    }
    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(headerValue, forKey: Self.storageKey)
        defaults.set(listenOnly, forKey: "translationListenOnly")
    }
}

enum LiveVoiceMode: Equatable, Sendable {
    case pip
    case translate(TranslationPair)

    var path: String {
        switch self {
        case .pip: "/v1/travel-chat/live"
        case .translate: "/v1/translate/live"
        }
    }
    var translation: TranslationPair? {
        if case .translate(let pair) = self { return pair }
        return nil
    }
}

/// Reuses the live voice transcript, audio lifecycle and interruption handling.
struct TranslateTab: View {
    let store: LiveVoiceStore
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TranslationLanguageBar(store: store).padding(.top, 16)
                LiveVoiceView(store: store, companionStyle: true, translationStyle: true, translationSettings: { showingSettings = true })
            }
            .background(PipAppearance.cream.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    Form {
                        Section {
                            TranslationHeadphoneControl(store: store, fullLabel: true)
                        } footer: {
                            Text("Headphone mode translates their speech into your language. Turn it off to translate both ways. Change languages or mode before starting.")
                        }
                        Section("Privacy") {
                            Text("Speech goes to OpenAI; profile, trips and location don’t.")
                        }
                    }
                    .navigationTitle("Translation settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSettings = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}

struct TranslationLanguageBar: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let store: LiveVoiceStore
    private var pair: TranslationPair { store.mode.translation ?? .saved() }

    var body: some View {
        HStack(spacing: 10) {
            languageMenu(title: "You speak", selection: pair.mine) { code in
                update(mine: code, theirs: code == pair.theirs.code ? pair.mine.code : pair.theirs.code)
            }
            Button { setPair(pair.swapped) } label: {
                Image(systemName: pair.listenOnly
                      ? (layoutDirection == .rightToLeft ? "arrow.right" : "arrow.left")
                      : "arrow.left.arrow.right")
                    .font(.body.weight(.bold)).foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(.blue.opacity(0.06), in: Circle())
            }
            .accessibilityLabel("Swap languages")
            .accessibilityValue(pair.listenOnly ? "Translation from their language to yours" : "Two-way translation")
            languageMenu(title: "They speak", selection: pair.theirs) { code in
                update(mine: code == pair.mine.code ? pair.theirs.code : pair.mine.code, theirs: code)
            }
        }
        .disabled(store.active)
        .padding(.horizontal, 22).padding(.bottom, 4)
    }

    private func languageMenu(title: LocalizedStringKey, selection: TranslationLanguage, choose: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(TranslationLanguage.all) { language in
                Button { choose(language.code) } label: {
                    if language == selection { Label(language.name, systemImage: "checkmark") }
                    else { Text(language.name) }
                }
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(selection.code == "fa" ? "Farsi" : selection.name)
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                }
                Text(selection.symbol).font(.body).accessibilityHidden(true)
            }
            .foregroundStyle(PipAppearance.navy)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: PipAppearance.navy.opacity(0.04), radius: 10, y: 4)
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(selection.name))
    }

    private func update(mine: String, theirs: String) {
        if let next = TranslationPair(mine: mine, theirs: theirs, listenOnly: pair.listenOnly) { setPair(next) }
    }

    private func setPair(_ next: TranslationPair) {
        guard !store.active else { return }
        next.save()
        store.setMode(.translate(next))
    }
}

private extension TranslationLanguage {
    var symbol: String {
        ["fil": "🇵🇭", "tl": "🇵🇭", "en": "🇺🇸", "fa": "🇮🇷", "ar": "🌐", "zh": "🇨🇳", "nl": "🇳🇱",
         "fr": "🇫🇷", "de": "🇩🇪", "el": "🇬🇷", "he": "🇮🇱", "hi": "🇮🇳",
         "id": "🇮🇩", "it": "🇮🇹", "ja": "🇯🇵", "ko": "🇰🇷", "pl": "🇵🇱",
         "pt": "🇵🇹", "ru": "🇷🇺", "es": "🇪🇸", "sv": "🇸🇪", "th": "🇹🇭",
         "tr": "🇹🇷", "vi": "🇻🇳"][code] ?? "🌐"
    }
}

struct TranslationHeadphoneControl: View {
    let store: LiveVoiceStore
    var fullLabel = false
    @State private var headphonesConnected = false
    @Environment(\.scenePhase) private var scenePhase
    private var pair: TranslationPair { store.mode.translation ?? .saved() }
    private var enabled: Binding<Bool> {
        Binding(get: { pair.listenOnly }, set: { value in
            guard !store.active else { return }
            var next = pair
            next.listenOnly = value
            next.save()
            store.setMode(.translate(next))
        })
    }

    var body: some View {
        Group {
            if fullLabel {
                Toggle("Headphone mode", systemImage: "headphones", isOn: enabled)
            } else {
                Button { enabled.wrappedValue.toggle() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "headphones").font(.title2)
                            .frame(width: 46, height: 46)
                            .background(pair.listenOnly ? Color.blue.opacity(0.12) : .white, in: Circle())
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(headphonesConnected ? Color.green : Color.gray.opacity(0.35))
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(PipAppearance.cream, lineWidth: 2))
                                    .accessibilityHidden(true)
                            }
                    }
                    .foregroundStyle(pair.listenOnly ? .blue : PipAppearance.secondary)
                }
                .accessibilityLabel("Headphone mode")
                .accessibilityValue("\(headphonesConnected ? "Headphones or Bluetooth audio connected" : "No headphone output"). Headphone mode \(pair.listenOnly ? "on" : "off")")
                .accessibilityHint("Translate only their speech into your language")
            }
        }
        .disabled(store.active)
        .onAppear { updateRoute() }
        .onChange(of: scenePhase) { _, _ in updateRoute() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in updateRoute() }
    }

    private func updateRoute() {
        headphonesConnected = Self.hasHeadphoneOutput(AVAudioSession.sharedInstance().currentRoute.outputs.map(\.portType))
    }

    static func hasHeadphoneOutput(_ ports: [AVAudioSession.Port]) -> Bool {
        !ports.isEmpty && ports.allSatisfy { [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0) }
    }
}

struct TranslationLanding: View {
    let store: LiveVoiceStore

    var body: some View {
        VStack(spacing: 0) {
            Image("PipTranslate")
                .resizable().scaledToFit()
                .frame(width: 125, height: 100)
                .accessibilityHidden(true)
                .zIndex(1)
            Button { store.active ? store.stop() : store.start() } label: {
                Image(systemName: store.active ? "stop.fill" : "mic.fill")
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 154, height: 154)
                    .background(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .padding(12).background(.blue.opacity(0.12), in: Circle())
                    .padding(12).background(.blue.opacity(0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.active ? "Stop translating" : "Start translation")
            .padding(.top, -20)

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

#if DEBUG
#Preview("Translation") {
    TranslateTab(store: .translationPreview)
}
#endif
