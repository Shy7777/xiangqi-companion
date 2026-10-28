import Foundation

@main
struct EngineConfigurationTests {
    static func main() throws {
        let suite = "xiangqi-engine-config-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message); checks += 1
        }
        let absent = EngineConfiguration.resolve(environment: [:], defaults: defaults)
        check(!absent.isConfigured && absent.binary == EngineConfiguration.unconfiguredBinary,
              "No automatic engine discovery or personal path fallback")
        let binary = URL(fileURLWithPath: "/example/pikafish"), network = URL(fileURLWithPath: "/example/network.nnue")
        EngineConfiguration.save(binary: binary, network: network, defaults: defaults)
        check(EngineConfiguration.resolve(environment: [:], defaults: defaults) == .init(binary: binary, network: network),
              "Explicit user configuration survives reload")
        let explicit = EngineConfiguration.resolve(environment: ["XQ_ENGINE_PATH": "/configured/engine", "XQ_ENGINE_NETWORK": "/configured/network"], defaults: defaults)
        check(explicit.binary.path == "/configured/engine" && explicit.network.path == "/configured/network",
              "Environment pair takes precedence over saved paths")
        let directory = EngineConfiguration.resolve(environment: ["XQ_ENGINE_DIR": "/configured"], defaults: defaults)
        check(directory.binary.path == "/configured/pikafish-apple-silicon" && directory.network.path == "/configured/pikafish.nnue",
              "Explicit directory uses documented filenames")
        let partial = EngineConfiguration.resolve(environment: ["XQ_ENGINE_PATH": "/configured/engine"], defaults: defaults)
        check(!partial.isConfigured && partial.network == EngineConfiguration.unconfiguredNetwork,
              "A partial environment configuration never silently mixes with saved preferences")
        let relative = EngineConfiguration.resolve(environment: ["XQ_ENGINE_PATH": "relative/engine", "XQ_ENGINE_NETWORK": "/safe/network"], defaults: defaults)
        check(!relative.isConfigured, "Relative executable paths are rejected")
        let control = EngineConfiguration.resolve(environment: ["XQ_ENGINE_PATH": "/bad/engine\nquit", "XQ_ENGINE_NETWORK": "/safe/network"], defaults: defaults)
        check(!control.isConfigured, "Control characters cannot reach a process configuration")
        let offline = EngineConfiguration.resolve(environment: ["XQ_TEST_TEMP_DIR": "/test", "XQ_ENGINE_PATH": binary.path, "XQ_ENGINE_NETWORK": network.path], defaults: defaults)
        check(!offline.isConfigured, "Offline verification ignores both environment and saved real engines")
        let live = EngineConfiguration.resolve(environment: ["XQ_TEST_TEMP_DIR": "/test", "XQ_RUN_ENGINE_TESTS": "1", "XQ_ENGINE_PATH": binary.path, "XQ_ENGINE_NETWORK": network.path], defaults: defaults)
        check(live.isConfigured, "Explicit live test opt-in resolves configured files")
        EngineConfiguration.clear(defaults: defaults)
        check(!EngineConfiguration.resolve(environment: [:], defaults: defaults).isConfigured,
              "Clear removes only saved settings")
        print("PASS \(checks) external engine configuration checks; no engine executed")
    }
}
