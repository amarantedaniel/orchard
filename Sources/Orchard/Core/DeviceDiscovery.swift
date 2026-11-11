import Foundation

struct DiscoveredDevice: Identifiable, Hashable, Sendable {
    var device: Device
    var isConnected: Bool
    var id: String { device.id }
}

enum DeviceDiscovery {
    /// This Mac, paired physical devices (via devicectl) and booted simulators (via simctl).
    static func discover() async -> [DiscoveredDevice] {
        async let physical = physicalDevices()
        async let simulators = bootedSimulators()
        return [DiscoveredDevice(device: .thisMac, isConnected: true)] + (await physical) + (await simulators)
    }

    /// Rows for the device list: discovered devices plus selected ones that weren't discovered.
    /// Enabled (selected) devices come first, then the rest; within each, connected/available ones
    /// come first. Stable, so each group keeps its order (this Mac, physical devices, simulators,
    /// then the missing selected devices).
    static func listRows(discovered: [DiscoveredDevice], selected: [Device]) -> [DiscoveredDevice] {
        let missing = selected
            .filter { device in !discovered.contains { $0.id == device.id } }
            .map { DiscoveredDevice(device: $0, isConnected: false) }
        let all = discovered + missing
        let selectedIDs = Set(selected.map(\.id))
        func rank(_ row: DiscoveredDevice) -> Int {
            (selectedIDs.contains(row.id) ? 0 : 2) + (row.isConnected ? 0 : 1)
        }
        return all.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// `devices` with the hardware UDID filled in for physical devices that were saved without
    /// one. Asks devicectl only when one is missing; a device it doesn't know stays as it is.
    static func fillingUDIDs(_ devices: [Device]) async -> [Device] {
        guard devices.contains(where: { $0.kind == .physical && $0.udid == nil }) else { return devices }
        let known = await physicalDevices()
        return devices.map { device in
            guard device.kind == .physical, device.udid == nil else { return device }
            var device = device
            device.udid = known.first { $0.id == device.id }?.device.udid
            return device
        }
    }

    private static func physicalDevices() async -> [DiscoveredDevice] {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("orchard-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: output) }
        guard (try? await Shell.xcrun(["devicectl", "list", "devices", "--quiet", "--json-output", output.path])) != nil,
              let data = try? Data(contentsOf: output)
        else { return [] }
        return physicalDevices(fromDeviceCtl: data)
    }

    /// Paired physical devices in `devicectl list devices` JSON, connected ones first.
    static func physicalDevices(fromDeviceCtl data: Data) -> [DiscoveredDevice] {
        guard let response = try? JSONDecoder().decode(DeviceCtlResponse.self, from: data) else { return [] }
        return response.result.devices.compactMap { entry in
            guard entry.hardwareProperties.reality == "physical",
                  entry.connectionProperties.pairingState == "paired",
                  let platformName = entry.hardwareProperties.platform,
                  let platform = BuildPlatform(devicePlatform: platformName, simulator: false)
            else { return nil }
            let device = Device(
                id: entry.identifier,
                name: entry.deviceProperties.name ?? entry.hardwareProperties.marketingName ?? "Device",
                model: entry.hardwareProperties.marketingName ?? entry.hardwareProperties.deviceType ?? platformName,
                kind: .physical,
                platform: platform,
                osVersion: entry.deviceProperties.osVersionNumber ?? "",
                udid: entry.hardwareProperties.udid
            )
            return DiscoveredDevice(device: device, isConnected: entry.connectionProperties.tunnelState == "connected")
        }
        .sorted { ($0.isConnected ? 0 : 1, $0.device.name) < ($1.isConnected ? 0 : 1, $1.device.name) }
    }

    private static func bootedSimulators() async -> [DiscoveredDevice] {
        guard let output = try? await Shell.xcrun(["simctl", "list", "devices", "booted", "-j"]),
              let response = try? JSONDecoder().decode(SimctlResponse.self, from: Data(output.utf8))
        else { return [] }

        var result: [DiscoveredDevice] = []
        for (runtime, devices) in response.devices {
            // e.g. com.apple.CoreSimulator.SimRuntime.iOS-27-0
            let runtimeName = runtime.split(separator: ".").last.map(String.init) ?? ""
            let parts = runtimeName.split(separator: "-")
            guard let platformName = parts.first,
                  let platform = BuildPlatform(devicePlatform: String(platformName), simulator: true)
            else { continue }
            let version = parts.dropFirst().joined(separator: ".")
            for sim in devices where sim.state == "Booted" {
                let device = Device(
                    id: sim.udid, name: sim.name, model: "\(platform.displayName) \(version)",
                    kind: .simulator, platform: platform, osVersion: version)
                result.append(DiscoveredDevice(device: device, isConnected: true))
            }
        }
        return result.sorted { $0.device.name < $1.device.name }
    }
}

private struct DeviceCtlResponse: Decodable {
    struct Result: Decodable { var devices: [Entry] }
    struct Entry: Decodable {
        struct Connection: Decodable {
            var pairingState: String?
            var tunnelState: String?
        }
        struct Properties: Decodable {
            var name: String?
            var osVersionNumber: String?
        }
        struct Hardware: Decodable {
            var platform: String?
            var reality: String?
            var marketingName: String?
            var deviceType: String?
            var udid: String?
        }
        var identifier: String
        var connectionProperties: Connection
        var deviceProperties: Properties
        var hardwareProperties: Hardware
    }
    var result: Result
}

private struct SimctlResponse: Decodable {
    struct Sim: Decodable {
        var udid: String
        var name: String
        var state: String
    }
    var devices: [String: [Sim]]
}
