import Testing
@testable import Orchard

struct DeviceDiscoveryTests {
    private func row(_ name: String, _ kind: DeviceKind, connected: Bool) -> DiscoveredDevice {
        let platform: BuildPlatform = switch kind {
        case .thisMac: .macOS
        case .physical: .iOS
        case .simulator: .iOSSimulator
        }
        let device = Device(id: name, name: name, model: name, kind: kind, platform: platform, osVersion: "27.0")
        return DiscoveredDevice(device: device, isConnected: connected)
    }

    @Test func availableDevicesComeFirst() {
        let input = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
            row("Missing", .physical, connected: false),
        ]
        let names = DeviceDiscovery.availableFirst(input).map(\.device.name)
        #expect(names == ["Mac", "iPhone A", "Sim A", "iPhone B", "Missing"])
    }

    @Test func keepsOrderWhenAllAvailable() {
        let input = [row("Mac", .thisMac, connected: true), row("Sim B", .simulator, connected: true)]
        #expect(DeviceDiscovery.availableFirst(input).map(\.device.name) == ["Mac", "Sim B"])
    }
}
