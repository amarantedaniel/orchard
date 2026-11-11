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

    @Test func enabledDevicesComeFirstThenAvailable() {
        let discovered = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("iPhone C", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
            row("Sim B", .simulator, connected: true),
        ]
        let selected = [device("Sim B", .simulator), device("Missing", .physical), device("iPhone C", .physical)]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: selected).map(\.device.name)
        #expect(names == ["Sim B", "iPhone C", "Missing", "Mac", "iPhone A", "Sim A", "iPhone B"])
    }

    @Test func availableDevicesComeFirstWhenNoneEnabled() {
        let discovered = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("iPhone C", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
        ]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: []).map(\.device.name)
        #expect(names == ["Mac", "iPhone A", "Sim A", "iPhone B", "iPhone C"])
    }

    @Test func selectedDiscoveredDeviceIsNotListedTwice() {
        let discovered = [row("Mac", .thisMac, connected: true), row("iPhone A", .physical, connected: true)]
        let selected = [device("iPhone A", .physical)]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: selected).map(\.device.name)
        #expect(names == ["iPhone A", "Mac"])
    }

    @Test func keepsOrderWhenAllAvailable() {
        let discovered = [row("Mac", .thisMac, connected: true), row("Sim B", .simulator, connected: true)]
        #expect(DeviceDiscovery.listRows(discovered: discovered, selected: []).map(\.device.name) == ["Mac", "Sim B"])
    }
}
