import SwiftUI

@main
struct pippipgoApp: App {
    @AppStorage("pip.language") private var language = "en"
    @State private var authenticationStore = AuthenticationStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var needsOpeningSound = true

    var body: some Scene {
        WindowGroup {
            RootView(store: authenticationStore)
                .environment(\.locale, Locale(identifier: AppLanguage.selected(language).localizationIdentifier))
                .environment(\.layoutDirection, AppLanguage.selected(language).direction)
                .task { await authenticationStore.restoreSession() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active, needsOpeningSound {
                        needsOpeningSound = false
                        if !authenticationStore.chat.voice.active && !authenticationStore.chat.translator.active {
                            PipStartupSound.shared.play()
                        }
                    } else if phase == .background {
                        needsOpeningSound = true
                        PipStartupSound.shared.stop()
                    } else if phase == .inactive {
                        PipStartupSound.shared.stop()
                    }
                }
        }
    }
}

/// Uses the existing language preference without recreating account or editor state.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case persian = "fa"
    case japanese = "ja"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case simplifiedChinese = "zh-Hans"
    case korean = "ko"
    case vietnamese = "vi"
    case filipino = "fil"
    case tagalog = "tl"
    case turkish = "tr"
    case arabic = "ar"
    case russian = "ru"
    static var current: AppLanguage { selected(UserDefaults.standard.string(forKey: "pip.language") ?? "en") }
    static var currentLocale: Locale { Locale(identifier: current.localizationIdentifier) }
    static var currentBundle: Bundle { current.bundle }
    // Xcode canonicalizes tl to fil. Use a regional resource for the separate
    // Tagalog choice while retaining tl in preferences and voice API headers.
    var localizationIdentifier: String { self == .tagalog ? "fil-PH" : rawValue }
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: localizationIdentifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .english: "English"
        case .persian: "فارسی"
        case .japanese: "日本語"
        case .spanish: "Español"
        case .french: "Français"
        case .italian: "Italiano"
        case .simplifiedChinese: "简体中文"
        case .korean: "한국어"
        case .vietnamese: "Tiếng Việt"
        case .filipino: "Filipino"
        case .tagalog: "Tagalog"
        case .turkish: "Türkçe"
        case .arabic: "العربية"
        case .russian: "Русский"
        }
    }
    var direction: LayoutDirection { self == .persian || self == .arabic ? .rightToLeft : .leftToRight }
    static func selected(_ stored: String) -> AppLanguage { AppLanguage(rawValue: stored) ?? .english }
}

struct AppLanguageMenu: View {
    @AppStorage("pip.language") private var language = "en"
    var body: some View {
        Menu {
            Picker("Application language", selection: $language) {
                ForEach(AppLanguage.allCases) { choice in
                    Text(verbatim: choice.nativeName).tag(choice.rawValue)
                }
            }
        } label: {
            Label("Language", systemImage: "globe")
        }
        .accessibilityIdentifier("app.languagePicker")
        .accessibilityValue(AppLanguage.selected(language).nativeName)
    }
}

/// A dedicated bottom-tab destination keeps language choices one tap away.
struct AppLanguageSelectionView: View {
    @AppStorage("pip.language") private var language = "en"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Application language", selection: $language) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(verbatim: choice.nativeName).tag(choice.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("app.languageSelection")
            }
            .scrollContentBackground(.hidden)
            .background(PipAppearance.cream.ignoresSafeArea())
            .navigationTitle("Language")
        }
    }
}

struct AppVersionView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"

    var body: some View {
        Text("Version \(version) (Build \(build))")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("app.versionAndBuild")
    }
}
