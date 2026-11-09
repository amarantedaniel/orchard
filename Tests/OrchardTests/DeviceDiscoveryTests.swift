import Testing
@testable import Orchard

struct DeviceDiscoveryTests {
    private func device(_ name: String, _ kind: DeviceKind) -> Device {
        let platform: BuildPlatform = switch kind {
        case .thisMac: .macOS
        case .physical: .iOS
        case .simulator: .iOSSimulator
        }
        return Device(id: name, name: name, model: name, kind: kind, platform: platform, osVersion: "27.0")
    }

    private func row(_ name: String, _ kind: DeviceKind, connected: Bool) -> DiscoveredDevice {
        DiscoveredDevice(device: device(name, kind), isConnected: connected)
    }

    @Test func availableDevicesComeFirstThenMissingSelected() {
        let discovered = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("iPhone C", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
        ]
        // "iPhone A" is selected and discovered, so it isn't listed twice.
        let selected = [device("Missing", .physical), device("iPhone A", .physical)]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: selected).map(\.device.name)
        #expect(names == ["Mac", "iPhone A", "Sim A", "iPhone B", "iPhone C", "Missing"])
    }

    @Test func keepsOrderWhenAllAvailable() {
        let discovered = [row("Mac", .thisMac, connected: true), row("Sim B", .simulator, connected: true)]
        #expect(DeviceDiscovery.listRows(discovered: discovered, selected: []).map(\.device.name) == ["Mac", "Sim B"])
    }
}
