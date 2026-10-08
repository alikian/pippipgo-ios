import Foundation
import Testing
@testable import pippipgo

struct AppConfigurationTests {
    private func info(_ environment: String = "local", url: String = "http://localhost:8765") -> [String: Any] {
        ["AppEnvironment": environment, "BackendBaseURL": url,
         "CognitoDomain": environment == "prod" ? "https://auth.pippipgo.com" : "https://auth-dev.pippipgo.com", "CognitoClientID": "public-client"]
    }

    @Test func localAcceptsSimulatorAndLAN() throws {
        for host in ["localhost", "192.168.0.156"] {
            let config = try AppConfiguration.from(info: info(url: "http://\(host):8765"))
            #expect(config.environment == .local)
            #expect(config.backendBaseURL.host == host)
            #expect(config.callbackURL.absoluteString == "pippipgo://auth/callback")
        }
    }

    @Test func hostedBuildsUseTheirOwnHTTPSHost() throws {
        for (environment, host) in [("dev", "api-dev.pippipgo.com"), ("prod", "api.pippipgo.com")] {
            let config = try AppConfiguration.from(info: info(environment, url: "https://\(host)"))
            #expect(config.environment.rawValue == environment)
            #expect(config.backendBaseURL.host == host)
            #expect(config.cognitoDomain.host == (environment == "prod" ? "auth.pippipgo.com" : "auth-dev.pippipgo.com"))
        }
    }

    @Test func hostedBuildsRejectLocalHTTPAndWrongEnvironment() {
        for (environment, url) in [("dev", "http://api-dev.pippipgo.com"), ("dev", "http://localhost:8765"),
                                   ("prod", "https://api-dev.pippipgo.com"), ("dev", "https://pippipgo.com"),
                                   ("prod", "https://pippipgo.com:8765")] {
            #expect(throws: AppConfigurationError.invalidValue("BackendBaseURL")) {
                try AppConfiguration.from(info: info(environment, url: url))
            }
        }
    }

    @Test func missingOrUnexpandedBuildSettingsFailClearly() {
        for key in ["AppEnvironment", "BackendBaseURL", "CognitoDomain", "CognitoClientID"] {
            var values = info(); values.removeValue(forKey: key)
            #expect(throws: AppConfigurationError.invalidValue(key)) { try AppConfiguration.from(info: values) }
            values[key] = "$(UNEXPANDED)"
            #expect(throws: AppConfigurationError.invalidValue(key)) { try AppConfiguration.from(info: values) }
        }
        #expect(throws: AppConfigurationError.invalidValue("AppEnvironment")) {
            try AppConfiguration.from(info: info("unknown"))
        }
    }

    @Test func baseURLsRejectCredentialsQueriesAndPaths() {
        for url in ["https://user:password@pippipgo.com", "https://pippipgo.com?key=test", "https://pippipgo.com/path", "https://pippipgo.com#fragment"] {
            #expect(throws: AppConfigurationError.invalidValue("BackendBaseURL")) {
                try AppConfiguration.from(info: info("prod", url: url))
            }
        }
        var values = info(); values["CognitoDomain"] = "http://auth-dev.pippipgo.com"
        #expect(throws: AppConfigurationError.invalidValue("CognitoDomain")) { try AppConfiguration.from(info: values) }
    }

    @Test func productionRejectsDevelopmentIdentity() {
        var values = info("prod", url: "https://api.pippipgo.com")
        values["CognitoDomain"] = "https://auth-dev.pippipgo.com"
        #expect(throws: AppConfigurationError.invalidValue("CognitoDomain")) { try AppConfiguration.from(info: values) }
        values["CognitoDomain"] = "https://auth.pippipgo.com"
        values["CognitoClientID"] = "5ungc4grbiid7de7rjbh0jn2ff"
        #expect(throws: AppConfigurationError.invalidValue("CognitoClientID")) { try AppConfiguration.from(info: values) }
        values["CognitoClientID"] = ""
        #expect(throws: AppConfigurationError.invalidValue("CognitoClientID")) { try AppConfiguration.from(info: values) }
    }

    @Test func tokenNamespacesAreDistinctForRenamedApp() {
        #expect(AppEnvironment.local.keychainService == "com.pippipgo.ios.authentication")
        #expect(Set([AppEnvironment.local, .dev, .prod].map(\.keychainService)).count == 3)
    }

    @Test func builtBundleMatchesConfigurationAndTransportPolicy() throws {
        let config = AppConfiguration.live
        let info = try #require(Bundle.main.infoDictionary)
        let ats = info["NSAppTransportSecurity"] as? [String: Any]
        if config.environment == .local {
            #expect(config.backendBaseURL.host == "localhost")
            let domains = try #require(ats?["NSExceptionDomains"] as? [String: Any])
            #expect(domains["localhost"] != nil)
            #expect(domains["$(PIPPIPGO_LAN_HOST)"] == nil)
            #expect(domains["192.168.0.156"] != nil)
            #expect(info["CFBundleDisplayName"] as? String == "PipPipGo Local")
        } else {
            #expect(ats == nil)
            #expect(info["NSLocalNetworkUsageDescription"] == nil)
            #expect(config.backendBaseURL.scheme == "https")
        }
    }
}


@MainActor
struct TalkToPipLaunchTests {
    @Test func coldStartWaitsForActiveSceneAndConsumesOnce() {
        let launch = TalkToPipLaunch()
        launch.request()
        let request = launch.requestID
        #expect(launch.take(isActive: false, blocked: false) == nil)
        #expect(launch.requestID == request)
        #expect(launch.take(isActive: true, blocked: false) == request)
        #expect(launch.take(isActive: true, blocked: false) == nil)
    }

    @Test func editorAndPendingChatDoNotLoseLaunchOrEdits() {
        let launch = TalkToPipLaunch()
        launch.request()
        #expect(launch.take(isActive: true, blocked: true) == nil)
        #expect(launch.take(isActive: true, blocked: false) != nil)
    }

    @Test func cancelledAccountRequestCannotStartLater() {
        let launch = TalkToPipLaunch()
        launch.request()
        launch.cancel()
        #expect(launch.take(isActive: true, blocked: false) == nil)
    }

    @Test func staleLaunchExpiresAndRepeatedRequestsCoalesce() {
        let launch = TalkToPipLaunch()
        let now = Date(timeIntervalSince1970: 100)
        launch.request(now: now)
        launch.request(now: now)
        let latest = launch.requestID
        #expect(launch.take(isActive: true, blocked: false, now: now) == latest)
        #expect(launch.take(isActive: true, blocked: false, now: now) == nil)
        launch.request(now: now)
        #expect(launch.take(isActive: true, blocked: false, now: now.addingTimeInterval(60)) == nil)
        #expect(launch.requestID == nil)
    }
}

@MainActor struct VoiceNavigationTests {
    @Test func directionsUseFixedAppleHostAndEncodeDestination() throws {
        let url = try #require(LiveVoiceStore.drivingURL(["place_id": "id&other=bad", "name": "Shell & Cafe"]))
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https")
        #expect(parts.host == "maps.apple.com")
        #expect(parts.queryItems?.first(where: { $0.name == "daddr" })?.value == "Shell & Cafe")
        #expect(parts.queryItems?.first(where: { $0.name == "dirflg" })?.value == "d")
        #expect(parts.queryItems?.contains(where: { $0.name == "origin" }) == false)
    }
    @Test func malformedDestinationDoesNotOpen() {
        #expect(LiveVoiceStore.drivingURL(["place_id": "", "name": "Shell"]) == nil)
        #expect(LiveVoiceStore.drivingURL(["place_id": "id", "name": " "]) == nil)
        #expect(LiveVoiceStore.drivingURL(["url": "https://evil.invalid"]) == nil)
    }
}

struct AppLanguageTests {
    @Test func everyTranslationLanguageHasAnInterfaceLanguage() {
        for translation in TranslationLanguage.all {
            let interfaceCode = translation.code == "zh" ? "zh-Hans" : translation.code
            #expect(AppLanguage(rawValue: interfaceCode) != nil, "Missing interface language: \(translation.code)")
        }
        #expect(AppLanguage.selected("es") == .spanish) // Preserve existing choices.
    }

    @Test func interfaceLanguagesHavePackagedMenuTranslations() {
        for language in AppLanguage.allCases where language != .english {
            for key in ["Trips", "Translate", "Profile", "Settings", "Save & Done", "Pip’s voice", "My travel style", "Delete account"] {
                let value = language.bundle.localizedString(forKey: key, value: "__missing__", table: nil)
                // Some languages use the same loanword (for example Filipino “Profile”).
                #expect(value != "__missing__", "Missing \(language.rawValue) translation: \(key)")
                #expect(!value.isEmpty)
            }
        }
    }

    @Test func selectedLanguageFallbackAndDirection() {
        #expect(AppLanguage.selected("unknown") == .english)
        #expect(AppLanguage.selected("fa").direction == .rightToLeft)
        #expect(AppLanguage.selected("ar").direction == .rightToLeft)
        #expect(AppLanguage.selected("fr").direction == .leftToRight)
    }

    @Test func localizedInterpolationPreservesUserText() {
        let name = "Sara" // User content must not be translated.
        let place = "Kyoto"
        for language in AppLanguage.allCases {
            let value = String(localized: "\(name), let's plan \(place)", bundle: language.bundle, locale: Locale(identifier: language.localizationIdentifier))
            #expect(value.contains(name))
            #expect(value.contains(place))
            #expect(!value.contains("%@"))
        }
    }


    @Test func unsupportedPreferenceFallsBackToEnglish() {
        #expect(AppLanguage.selected("unsupported") == .english)
        #expect(AppLanguage.selected("fa") == .persian)
        #expect(AppLanguage.selected("ja") == .japanese)
        #expect(AppLanguage.selected("es") == .spanish)
        #expect(AppLanguage.selected("fr") == .french)
        #expect(AppLanguage.selected("it") == .italian)
        #expect(AppLanguage.selected("zh-Hans") == .simplifiedChinese)
    }

    @Test(arguments: AppLanguage.allCases.filter { $0 != .english }.map(\.rawValue)) func packagedTranslationsAreAvailable(language: String) throws {
        let path = try #require(Bundle.main.path(forResource: AppLanguage.selected(language).localizationIdentifier, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for key in ["Language", "My Profile", "Trips", "Ask Pip", "Talk to Pip", "Save", "Cancel"] {
            #expect(bundle.localizedString(forKey: key, value: nil, table: "Localizable") != key)
        }
    }
}
