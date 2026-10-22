import Foundation
import IOBluetooth
import SoundcoreKit

/// A paired Bluetooth device that exposes the Soundcore vendor RFCOMM service.
struct SoundcoreEndpoint: Identifiable, Equatable {
    let address: String
    let name: String
    let channelID: BluetoothRFCOMMChannelID
    /// Last five hex digits of the vendor service UUID, e.g. "1202c" for the R60i NC (D1202C).
    let modelCode: String
    var id: String { address }
}

/// A paired Soundcore device, whether or not it is in range right now.
struct PairedDevice: Identifiable, Equatable {
    let address: String
    let name: String
    let isConnected: Bool
    let endpoint: SoundcoreEndpoint?
    var id: String { address }

    var guessedModel: DeviceModel? { DeviceModel.guess(name: name, serviceCode: endpoint?.modelCode) }
}

/// Finds Soundcore devices through their SDP records. The vendor service class UUID is
/// `0cf12d31-fac3-4553-bd80-d6832e7XXXXX`, where the masked tail encodes the model.
@MainActor
enum DeviceDiscovery {
    private static let vendorPrefix: [UInt8] = [0x0C, 0xF1, 0x2D, 0x31, 0xFA, 0xC3, 0x45, 0x53, 0xBD, 0x80, 0xD6, 0x83, 0x2E]

    static func pairedDevices() -> [PairedDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.compactMap { device in
            let endpoint = endpoint(fromCachedRecordsOf: device)
            let name = device.name ?? ""
            guard endpoint != nil || name.localizedCaseInsensitiveContains("soundcore") else { return nil }
            return PairedDevice(address: device.addressString ?? "", name: name.isEmpty ? "Soundcore" : name,
                                isConnected: device.isConnected(), endpoint: endpoint)
        }
        .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    /// Resolves the vendor channel, refreshing SDP records when the cache has none.
    static func endpoint(for device: IOBluetoothDevice) async -> SoundcoreEndpoint? {
        if let e = endpoint(fromCachedRecordsOf: device) { return e }
        await SDPQuery.run(on: device)
        return endpoint(fromCachedRecordsOf: device)
    }

    static func endpoint(fromCachedRecordsOf device: IOBluetoothDevice) -> SoundcoreEndpoint? {
        for case let record as IOBluetoothSDPServiceRecord in device.services ?? [] {
            var channel: BluetoothRFCOMMChannelID = 0
            guard record.getRFCOMMChannelID(&channel) == kIOReturnSuccess else { continue }
            for uuid in serviceClassUUIDs(record) where uuid.count == 16 {
                if Array(uuid.prefix(13)) == vendorPrefix, uuid[13] >> 4 == 0x7 {
                    let tail = uuid.suffix(3).map { String(format: "%02x", $0) }.joined()
                    return SoundcoreEndpoint(
                        address: device.addressString ?? "",
                        name: device.name ?? "Soundcore",
                        channelID: channel,
                        modelCode: String(format: "%x", uuid[13] & 0x0F) + tail)
                }
            }
        }
        return nil
    }

    private static func serviceClassUUIDs(_ record: IOBluetoothSDPServiceRecord) -> [[UInt8]] {
        guard let list = record.getAttributeDataElement(1) else { return [] }
        let elements = (list.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? [list]
        return elements.compactMap { element in
            guard let uuid = element.getUUIDValue()?.getWithLength(16) else { return nil }
            return Array(UnsafeRawBufferPointer(start: uuid.bytes, count: uuid.length))
        }
    }
}

/// Async wrapper around IOBluetooth's callback based SDP query.
@MainActor
private final class SDPQuery: NSObject {
    private var continuation: CheckedContinuation<Void, Never>?

    static func run(on device: IOBluetoothDevice) async {
        let query = SDPQuery()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            query.continuation = c
            if device.performSDPQuery(query) != kIOReturnSuccess {
                query.finish()
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                query.finish()
            }
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }

    @objc nonisolated func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        MainActor.assumeIsolated { finish() }
    }
}

/// Non-blocking `IOBluetoothDevice.openConnection`, which otherwise stalls the main thread for
/// the whole paging timeout when the device is out of range.
@MainActor
final class BasebandConnector: NSObject {
    private var continuation: CheckedContinuation<Bool, Never>?

    static func open(_ device: IOBluetoothDevice) async -> Bool {
        let connector = BasebandConnector()
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            connector.continuation = c
            if device.openConnection(connector) != kIOReturnSuccess {
                connector.finish(false)
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                connector.finish(device.isConnected())
            }
        }
    }

    func finish(_ ok: Bool) {
        continuation?.resume(returning: ok)
        continuation = nil
    }

    @objc nonisolated func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        MainActor.assumeIsolated { finish(status == kIOReturnSuccess) }
    }
}
