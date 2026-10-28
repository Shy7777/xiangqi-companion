import Foundation

/// External engines and networks are supplied by the user, never by this source
/// distribution. Environment variables are an explicit execution opt-in and take
/// precedence over the application-specific preferences saved by the UI.
enum EngineConfiguration {
    struct Paths: Equatable {
        let binary: URL
        let network: URL
        var isConfigured: Bool { binary != EngineConfiguration.unconfiguredBinary && network != EngineConfiguration.unconfiguredNetwork }
    }

    static let binaryKey = "externalEnginePath"
    static let networkKey = "externalEngineNetwork"
    static let unconfiguredBinary = URL(fileURLWithPath: "/dev/null/xiangqi-engine-not-configured")
    static let unconfiguredNetwork = URL(fileURLWithPath: "/dev/null/xiangqi-network-not-configured")

    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        defaults: UserDefaults = .standard) -> Paths {
        // Test runs never discover a developer's saved engine preferences. The
        // live lane explicitly provides both paths; the offline lane runs none.
        if environment["XQ_TEST_TEMP_DIR"] != nil && environment["XQ_RUN_ENGINE_TESTS"] != "1" {
            return Paths(binary: unconfiguredBinary, network: unconfiguredNetwork)
        }
        func absolute(_ value: String?) -> URL? {
            guard let value, !value.isEmpty, (value as NSString).isAbsolutePath,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            return URL(fileURLWithPath: value)
        }
        let hasEnvironment = ["XQ_ENGINE_PATH", "XQ_ENGINE_NETWORK", "XQ_ENGINE_DIR"].contains { environment[$0] != nil }
        if hasEnvironment {
            let directory = absolute(environment["XQ_ENGINE_DIR"])
            return Paths(binary: absolute(environment["XQ_ENGINE_PATH"]) ?? directory?.appendingPathComponent("pikafish-apple-silicon") ?? unconfiguredBinary,
                         network: absolute(environment["XQ_ENGINE_NETWORK"]) ?? directory?.appendingPathComponent("pikafish.nnue") ?? unconfiguredNetwork)
        }
        return Paths(binary: absolute(defaults.string(forKey: binaryKey)) ?? unconfiguredBinary,
                     network: absolute(defaults.string(forKey: networkKey)) ?? unconfiguredNetwork)
    }

    static func save(binary: URL, network: URL, defaults: UserDefaults = .standard) {
        defaults.set(binary.path, forKey: binaryKey)
        defaults.set(network.path, forKey: networkKey)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: binaryKey)
        defaults.removeObject(forKey: networkKey)
    }
}
