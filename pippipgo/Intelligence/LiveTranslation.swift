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

    /// Shown to the other person in their own language: they did not sign up for PipPipGo.
    /// Accurate only while the backend never stores interpreter transcripts.
    var bystanderNotice: String { Self.notices[code] ?? Self.notices["en"]! }
    var isRightToLeft: Bool { ["ar", "fa", "he"].contains(code) }

    private static let notices: [String: String] = [
        "en": "This conversation is translated by AI. PipPipGo does not save your words.",
        "fil": "Isinasalin ng AI ang usapang ito. Hindi sine-save ng PipPipGo ang iyong mga salita.",
        "tl": "Isinasalin ng AI ang usapang ito. Hindi sine-save ng PipPipGo ang iyong mga salita.",
        "ar": "تُترجم هذه المحادثة بالذكاء الاصطناعي. لا يحفظ PipPipGo كلامك.",
        "zh": "这段对话由 AI 翻译。PipPipGo 不会保存你说的话。",
        "nl": "Dit gesprek wordt door AI vertaald. PipPipGo slaat je woorden niet op.",
        "fr": "Cette conversation est traduite par une IA. PipPipGo n’enregistre pas vos paroles.",
        "de": "Dieses Gespräch wird von einer KI übersetzt. PipPipGo speichert Ihre Worte nicht.",
        "el": "Αυτή η συνομιλία μεταφράζεται από τεχνητή νοημοσύνη. Το PipPipGo δεν αποθηκεύει τα λόγια σας.",
        "he": "השיחה הזו מתורגמת על ידי בינה מלאכותית. PipPipGo לא שומרת את הדברים שלך.",
        "hi": "इस बातचीत का अनुवाद AI करता है। PipPipGo आपके शब्द सहेजता नहीं है।",
        "id": "Percakapan ini diterjemahkan oleh AI. PipPipGo tidak menyimpan kata-kata Anda.",
        "it": "Questa conversazione è tradotta da un’IA. PipPipGo non salva le tue parole.",
        "ja": "この会話はAIが翻訳しています。PipPipGoはあなたの言葉を保存しません。",
        "ko": "이 대화는 AI가 통역합니다. PipPipGo는 말씀하신 내용을 저장하지 않습니다.",
        "fa": "این گفت‌وگو با هوش مصنوعی ترجمه می‌شود. PipPipGo حرف‌های شما را ذخیره نمی‌کند.",
        "pl": "Ta rozmowa jest tłumaczona przez AI. PipPipGo nie zapisuje Twoich słów.",
        "pt": "Esta conversa é traduzida por IA. O PipPipGo não guarda suas palavras.",
        "ru": "Этот разговор переводит ИИ. PipPipGo не сохраняет ваши слова.",
        "es": "Esta conversación la traduce una IA. PipPipGo no guarda tus palabras.",
        "sv": "Det här samtalet översätts av AI. PipPipGo sparar inte dina ord.",
        "th": "บทสนทนานี้แปลโดย AI และ PipPipGo จะไม่บันทึกคำพูดของคุณ",
        "tr": "Bu konuşma yapay zekâ ile çevriliyor. PipPipGo sözlerinizi kaydetmez.",
        "vi": "Cuộc trò chuyện này được AI dịch. PipPipGo không lưu lời nói của bạn.",
    ]
}

/// Live Translate inside the map's panel: notice for the other person, the two languages,
/// live captions and one Start/Stop button. Same look as the rest of the app.
struct InlineTranslationPanel: View {
    let store: LiveVoiceStore
    let close: () -> Void
    private var pair: TranslationPair { store.mode.translation ?? .saved() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Translate", systemImage: "character.bubble").font(.title3.weight(.bold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Close"))
            }
            TranslationBystanderNotice(language: pair.theirs)
            TranslationLanguageBar(store: store).padding(.horizontal, -22)
            TranslationHeadphoneControl(store: store)
            ForEach(store.transcript.messages.suffix(2)) { message in
                Text(verbatim: message.text)
                    .font(message.speaker == .pip ? .title3.weight(.semibold) : .body)
                    .foregroundStyle(message.speaker == .pip ? Color.primary : Color.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = store.error {
                Text(LocalizedStringKey(error)).font(.footnote).foregroundStyle(.red)
            } else if store.active {
                Label(LocalizedStringKey(store.connected ? (store.microphoneReceiving ? "Translating — take turns speaking" : "Starting microphone…") : "Connecting…"),
                      systemImage: "waveform")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                if store.active { store.stop() } else {
                    if store.mode.translation == nil { store.setMode(.translate(.saved())) }
                    store.start()
                }
            } label: {
                Label(LocalizedStringKey(store.active ? "Stop translating" : "Start translation"),
                      systemImage: store.active ? "stop.fill" : "mic.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(store.active ? Color(red: 0.75, green: 0.15, blue: 0.12) : .blue)
            .accessibilityIdentifier("translation.toggle")
        }
    }
}

/// A notice the other person can read in their own language before and during translation.
struct TranslationBystanderNotice: View {
    let language: TranslationLanguage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.wave.2").font(.title3).foregroundStyle(PipAppearance.navy)
                .accessibilityHidden(true)
            Text(spoken).font(.callout).foregroundStyle(PipAppearance.navy)
                .multilineTextAlignment(language.isRightToLeft ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: language.isRightToLeft ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("translation.bystanderNotice")
    }

    /// Tags the language so VoiceOver reads the notice with the right voice.
    private var spoken: AttributedString {
        var text = AttributedString(language.bystanderNotice)
        text.languageIdentifier = language.code
        return text
    }
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
        return TranslationPair(mine: mine, theirs: "es")!
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
                HStack {
                    AppLanguageMenu()
                    Spacer()
                }
                .padding(.horizontal, 16)
                TranslationLanguageBar(store: store).padding(.top, 16)
                TranslationBystanderNotice(language: (store.mode.translation ?? .saved()).theirs)
                    .padding(.horizontal, 22).padding(.top, 8)
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
            .accessibilityValue(LocalizedStringKey(pair.listenOnly ? "Translation from their language to yours" : "Two-way translation"))
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
                    if language == selection { Label(LocalizedStringKey(language.name), systemImage: "checkmark") }
                    else { Text(LocalizedStringKey(language.name)) }
                }
            }
        } label: {
            VStack(spacing: 5) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(selection.name))
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
        .accessibilityValue(Text(LocalizedStringKey(selection.name)))
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
                .accessibilityValue(LocalizedStringKey(headphonesConnected
                    ? (pair.listenOnly ? "Headphones connected. Headphone mode on." : "Headphones connected. Headphone mode off.")
                    : (pair.listenOnly ? "No headphone output. Headphone mode on." : "No headphone output. Headphone mode off.")))
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
            .accessibilityLabel(LocalizedStringKey(store.active ? "Stop translating" : "Start translation"))
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
