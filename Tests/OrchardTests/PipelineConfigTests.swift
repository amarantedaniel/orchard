import Foundation
import Testing
@testable import Orchard

struct PipelineConfigTests {
    @Test func reportsFirstMissingSetupStep() {
        var config = PipelineConfig()
        #expect(config.missingSetup == "Choose a repository")
        config.repoPath = "/tmp/repo"
        #expect(config.missingSetup == "Choose a branch")
        config.branch = "main"
        #expect(config.missingSetup == "Choose a scheme")
        config.scheme = "App"
        #expect(config.missingSetup == "Choose at least one device")
        config.devices = [Device(id: "sim", name: "iPhone", model: "iPhone", kind: .simulator,
                                 platform: .iOSSimulator, osVersion: "18.0")]
        #expect(config.missingSetup == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        var config = PipelineConfig()
        config.repoPath = "/tmp/repo"
        config.branch = "main"
        config.containerPath = "App.xcworkspace"
        config.devices = [.thisMac]
        config.lastDeployedCommit = "0123456789abcdef"

        let decoded = try JSONDecoder().decode(PipelineConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }

    /// Devices saved before `udid` existed must still decode, or every pipeline is lost.
    @Test func decodesADeviceSavedWithoutUDID() throws {
        let json = #"""
        {"id":"A1","name":"iPhone","model":"iPhone 17","kind":"physical","platform":"iOS","osVersion":"27.0"}
        """#
        let device = try JSONDecoder().decode(Device.self, from: Data(json.utf8))
        #expect(device.id == "A1")
        #expect(device.udid == nil)
    }

    @Test func shortSHA() {
        #expect("0123456789abcdef".shortSHA == "01234567")
        #expect("abc".shortSHA == "abc")
    }
}
