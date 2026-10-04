import SwiftUI

/// Languages accepted by the backend interpreter (`/v1/translate/live`). Keep in sync with
/// backend `app/live_translation.py`.
struct TranslationLanguage: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    let nativeName: String
    var id: String { code }

    static let all: [TranslationLanguage] = [
        .init(code: "ar", name: "Arabic", nativeName: "العربية"),
        .init(code: "zh", name: "Chinese (Mandarin)", nativeName: "中文"),
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
        .init(code: "fa", name: "Persian (Farsi)", nativeName: "فارسی"),
        .init(code: "pl", name: "Polish", nativeName: "Polski"),
        .init(code: "pt", name: "Portuguese", nativeName: "Português"),
        .init(code: "ru", name: "Russian", nativeName: "Русский"),
        .init(code: "es", name: "Spanish", nativeName: "Español"),
        .init(code: "sv", name: "Swedish", nativeName: "Svenska"),
        .init(code: "th", name: "Thai", nativeName: "ไทย"),
        .init(code: "tr", name: "Turkish", nativeName: "Türkçe"),
        .init(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt"),
    ]

    static func language(_ code: String) -> TranslationLanguage? { all.first { $0.code == code } }
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
        let mine = TranslationLanguage.language(device) == nil ? "en" : device
        return TranslationPair(mine: mine, theirs: mine == "es" ? "en" : "es")!
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

/// Leaving this tab stops the interpreter and clears its captions (see LiveVoiceView.onDisappear).
struct TranslateTab: View {
    let store: LiveVoiceStore

    var body: some View {
        NavigationStack {
            LiveVoiceView(store: store)
                .safeAreaInset(edge: .top, spacing: 0) { TranslationLanguageBar(store: store) }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct TranslationLanguageBar: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let store: LiveVoiceStore
    private var pair: TranslationPair { store.mode.translation ?? .saved() }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                languageMenu(title: "You speak", selection: pair.mine) { code in
                    update(mine: code, theirs: code == pair.theirs.code ? pair.mine.code : pair.theirs.code)
                }
                Image(systemName: pair.listenOnly
                      ? (layoutDirection == .rightToLeft ? "arrow.right" : "arrow.left")
                      : "arrow.left.arrow.right")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .accessibilityLabel(pair.listenOnly ? "Translation from their language to yours" : "Two-way translation")
                languageMenu(title: "They speak", selection: pair.theirs) { code in
                    update(mine: code == pair.mine.code ? pair.theirs.code : pair.mine.code, theirs: code)
                }
            }
            .disabled(store.active)
            Toggle(isOn: Binding(get: { pair.listenOnly }, set: { enabled in
                var next = pair
                next.listenOnly = enabled
                setPair(next)
            })) {
                Label("Headphone mode", systemImage: "headphones")
                    .font(.subheadline)
            }
            .disabled(store.active)
            Text(pair.listenOnly ? "Hear only their translation." : "Translate both ways.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Speech goes to OpenAI; profile, trips and location don’t.")
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
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
            VStack(spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(selection.name).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
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

#if DEBUG
#Preview("Translation") {
    TranslateTab(store: .translationPreview)
}
#endif
