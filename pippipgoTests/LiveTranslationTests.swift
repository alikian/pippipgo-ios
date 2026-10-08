import Foundation
import AVFoundation
import Testing
@testable import pippipgo

struct LiveTranslationTests {
    @MainActor @Test func headphoneIndicatorFollowsOutputRouteNotTranslationMode() {
        #expect(TranslationHeadphoneControl.hasHeadphoneOutput([.headphones]))
        #expect(TranslationHeadphoneControl.hasHeadphoneOutput([.bluetoothA2DP]))
        #expect(TranslationHeadphoneControl.hasHeadphoneOutput([.bluetoothHFP]))
        #expect(!TranslationHeadphoneControl.hasHeadphoneOutput([.builtInSpeaker]))
        #expect(!TranslationHeadphoneControl.hasHeadphoneOutput([.builtInReceiver]))
        #expect(!TranslationHeadphoneControl.hasHeadphoneOutput([.airPlay]))
        #expect(!TranslationHeadphoneControl.hasHeadphoneOutput([.headphones, .builtInSpeaker]))
        #expect(!TranslationHeadphoneControl.hasHeadphoneOutput([]))
    }

    @Test func pairsRequireDistinctSupportedLanguages() {
        #expect(TranslationPair(mine: "en", theirs: "es")?.headerValue == "en,es")
        #expect(TranslationPair(mine: "en", theirs: "en") == nil)
        #expect(TranslationPair(mine: "en", theirs: "xx") == nil)
        #expect(TranslationPair(headerValue: "fa,ja")?.theirs.name == "Japanese")
        #expect(TranslationPair(headerValue: "en,es,fr") == nil)
        #expect(TranslationPair(headerValue: "") == nil)
        #expect(TranslationPair(headerValue: "en,,es") == nil)
        #expect(TranslationPair(headerValue: ",en,es") == nil)
        #expect(TranslationPair(headerValue: "en,es,") == nil)
        #expect(TranslationPair(mine: "en", theirs: "es")?.swapped.headerValue == "es,en")
    }

    @Test func languagePickerMatchesRequestedOrder() {
        let codes = TranslationLanguage.all.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(codes == ["zh", "ja", "ko", "vi", "fil", "tl", "fa", "tr", "ar", "ru", "it", "fr", "en"])
        #expect(TranslationPair(headerValue: "fil,tl")?.headerValue == "fil,tl")
    }

    @Test func defaultPairFollowsDeviceLanguage() {
        #expect(TranslationPair.defaultPair(locale: Locale(identifier: "fr_FR")).headerValue == "fr,en")
        #expect(TranslationPair.defaultPair(locale: Locale(identifier: "es_MX")).headerValue == "en,fa")
        #expect(TranslationPair.defaultPair(locale: Locale(identifier: "sw_KE")).headerValue == "en,fa")
    }

    @Test func savedPairRoundTripsAndIgnoresInvalidValues() throws {
        let defaults = try #require(UserDefaults(suiteName: "LiveTranslationTests-\(UUID())"))
        TranslationPair(mine: "ja", theirs: "ko")!.save(defaults)
        #expect(TranslationPair.saved(defaults).headerValue == "ja,ko")
        defaults.set("en,en", forKey: "translationLanguages")
        #expect(TranslationPair.saved(defaults) == TranslationPair.defaultPair())
    }

    @MainActor @Test func translationRequestUsesInterpreterEndpointWithoutNavigation() throws {
        let pair = try #require(TranslationPair(mine: "en", theirs: "it"))
        let request = try LiveVoiceStore.request(baseURL: URL(string: "https://api-dev.pippipgo.com")!, token: "test-access-token", mode: .translate(pair))
        #expect(request.url?.absoluteString == "wss://api-dev.pippipgo.com/v1/translate/live")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        #expect(request.value(forHTTPHeaderField: "X-Pip-Translate") == "en,it")
        #expect(request.value(forHTTPHeaderField: "X-Pip-Navigation") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Pip-Context") == nil)
        let voice = try LiveVoiceStore.request(baseURL: URL(string: "https://api-dev.pippipgo.com")!, token: "t")
        #expect(voice.value(forHTTPHeaderField: "X-Pip-Translate") == nil)
        #expect(voice.value(forHTTPHeaderField: "X-Pip-Navigation") == "1")
    }

    @MainActor @Test func headphoneModePersistsAndUsesDedicatedHeader() throws {
        let defaults = try #require(UserDefaults(suiteName: "HeadphoneTranslation-\(UUID())"))
        let pair = try #require(TranslationPair(mine: "en", theirs: "ja", listenOnly: true))
        pair.save(defaults)
        #expect(TranslationPair.saved(defaults).listenOnly)
        #expect(pair.swapped.listenOnly)
        let request = try LiveVoiceStore.request(baseURL: URL(string: "https://api.pippipgo.com")!, token: "test", mode: .translate(pair))
        #expect(request.value(forHTTPHeaderField: "X-Pip-Translate") == "en,ja")
        #expect(request.value(forHTTPHeaderField: "X-Pip-Translate-Listen-Only") == "1")
        let twoWay = try LiveVoiceStore.request(baseURL: URL(string: "https://api.pippipgo.com")!, token: "test", mode: .translate(TranslationPair(mine: "en", theirs: "ja")!))
        #expect(twoWay.value(forHTTPHeaderField: "X-Pip-Translate-Listen-Only") == nil)
    }

    @MainActor @Test func headphoneModeRequiresBackendConfirmation() {
        let mode = LiveVoiceMode.translate(TranslationPair(mine: "en", theirs: "fa", listenOnly: true)!)
        #expect(!LiveVoiceStore.acceptsTranslationSession(["type": "session.started"], mode: mode))
        #expect(!LiveVoiceStore.acceptsTranslationSession(["translation_mode": "two_way"], mode: mode))
        #expect(LiveVoiceStore.acceptsTranslationSession(["translation_mode": "listen_only"], mode: mode))
        #expect(LiveVoiceStore.acceptsTranslationSession([:], mode: .translate(TranslationPair(mine: "en", theirs: "fa")!)))
    }

    @MainActor @Test func languagesChangeOnlyWhileInactive() throws {
        let store = LiveVoiceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: NoTokens(),
                                   mode: .translate(TranslationPair(mine: "en", theirs: "es")!))
        let next = try #require(TranslationPair(mine: "en", theirs: "de"))
        store.setMode(.translate(next))
        #expect(store.mode.translation == next)
    }
}

private struct NoTokens: AccessTokenProviding {
    func validAccessToken(forceRefresh: Bool) async throws -> String { throw APIClientError.connection }
}


@MainActor struct VoiceLanguageRequestTests {
    @Test(arguments: ["en", "fa", "ja", "es", "fr", "it", "zh-Hans"])
    func voiceCarriesAppLanguage(language: String) throws {
        let request = try LiveVoiceStore.request(baseURL: URL(string: "https://api-dev.pippipgo.com")!, token: "test", language: language)
        #expect(request.value(forHTTPHeaderField: "X-Pip-Language") == language)
    }
}
