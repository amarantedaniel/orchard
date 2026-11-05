import Foundation
import Testing
@testable import Orchard

struct DeployOutcomeTests {
    private let phone = Device(id: "phone", name: "iPhone", model: "iPhone", kind: .physical,
                               platform: .iOS, osVersion: "26.0")
    private let pad = Device(id: "pad", name: "iPad", model: "iPad", kind: .physical,
                             platform: .iOS, osVersion: "26.0")

    private func run(_ outcomes: [String: DeployOutcome]) -> RunRecord {
        var run = RunRecord(commit: String(repeating: "a", count: 40))
        run.deviceOutcomes = outcomes
        return run
    }

    @Test func installedButNotLaunchedIsAWarningNotAFailure() {
        #expect(run([phone.id: .succeeded, pad.id: .succeeded]).finalOutcome(devices: [phone, pad]) == .succeeded)
        #expect(run([phone.id: .warning("locked"), pad.id: .succeeded]).finalOutcome(devices: [phone, pad])
            == .warning("Installed, but failed to launch on iPhone"))
        #expect(run([phone.id: .warning("locked"), pad.id: .warning("locked")]).finalOutcome(devices: [phone, pad])
            == .warning("Installed, but failed to launch on iPhone, iPad"))
        #expect(run([phone.id: .warning("locked"), pad.id: .failed("Build failed")]).finalOutcome(devices: [phone, pad])
            == .failed("1 of 2 device(s) failed"))
    }

    @Test func explainsALockedDevice() {
        // devicectl's output when the phone is locked (trimmed).
        let locked = """
            ERROR: The application failed to launch. (com.apple.dt.CoreDeviceError error 10002 (0x2712))
                   BundleIdentifier = com.example.app
                       The operation couldn’t be completed. Unable to launch com.example.app because the device was not, or could not be, unlocked. (FBSOpenApplicationErrorDomain error 7 (0x07))
                       BSErrorCodeDescription = Locked
                       NSLocalizedFailureReason = Unable to launch com.example.app because the device was not, or could not be, unlocked.

            """
        #expect(Deployer.launchFailureReason(locked) == "the device was locked")
        #expect(Deployer.launchFailureReason("first\n  Something else went wrong  \n\n") == "Something else went wrong")
        #expect(DeployError.launchFailed("the device was locked").localizedDescription
            == "Installed, but failed to launch: the device was locked")
    }
}
