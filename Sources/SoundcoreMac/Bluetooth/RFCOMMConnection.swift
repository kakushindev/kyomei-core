import Foundation
import IOBluetooth
import SoundcoreKit
import os

let log = Logger(subsystem: "dev.kakushin.kyomei", category: "bluetooth")

enum TransportError: LocalizedError {
    case openFailed(IOReturn)
    case notOpen
    case writeFailed(IOReturn)
    case timedOut(Command)

    var errorDescription: String? {
        switch self {
        case .openFailed(let r): "Could not open the control channel (0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .notOpen: "The headphones are not connected."
        case .writeFailed(let r): "Bluetooth write failed (0x\(String(UInt32(bitPattern: r), radix: 16)))."
        case .timedOut(let c): "The headphones did not answer command \(c)."
        }
    }
}

/// One RFCOMM control channel to a Soundcore device. Requests are serialised, each waits for an
/// acknowledgement carrying the same command and is retried up to three times, mirroring the
/// timing used by the Soundcore protocol implementations. Everything runs on the main actor,
/// which is also where IOBluetooth delivers its delegate callbacks.
@MainActor
final class RFCOMMConnection: NSObject {
    let device: IOBluetoothDevice
    let channelID: BluetoothRFCOMMChannelID

    /// Packets that were not consumed as a response to a request.
    var onPacket: ((Packet) -> Void)?
    var onClose: (() -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = PacketStreamParser()
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var waiters: [Waiter] = []
    private var queueTail: Task<Void, Never>?
    private var closed = false

    private struct Waiter {
        let id: UUID
        let command: Command
        let continuation: CheckedContinuation<Packet?, Never>
    }

    init(device: IOBluetoothDevice, channelID: BluetoothRFCOMMChannelID) {
        self.device = device
        self.channelID = channelID
    }

    var isOpen: Bool { channel?.isOpen() == true && !closed }

    func open() async throws {
        if !device.isConnected() {
            // Baseband connection first; the earbuds are usually already connected for audio.
            let r = device.openConnection()
            if r != kIOReturnSuccess { throw TransportError.openFailed(r) }
        }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            openContinuation = c
            var ch: IOBluetoothRFCOMMChannel?
            let r = device.openRFCOMMChannelAsync(&ch, withChannelID: channelID, delegate: self)
            if r != kIOReturnSuccess {
                openContinuation = nil
                c.resume(throwing: TransportError.openFailed(r))
            } else {
                channel = ch
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        channel?.setDelegate(nil)
        channel?.close()
        channel = nil
        failAllWaiters()
    }

    // MARK: Requests

    /// Sends a packet and returns the device's response with the same command.
    @discardableResult
    func request(_ packet: Packet) async throws -> Packet {
        try await serialized { [weak self] in
            guard let self else { throw TransportError.notOpen }
            for attempt in 1...3 {
                try self.write(packet)
                if let response = await self.wait(for: packet.command, timeout: 0.5 * Double(attempt)) {
                    return response
                }
                guard self.isOpen else { throw TransportError.notOpen }
                log.debug("retrying \(packet.command.description, privacy: .public) (\(attempt))")
            }
            throw TransportError.timedOut(packet.command)
        }
    }

    /// Sends a packet and collects responses until `isLast` returns true or 2 s pass in silence.
    func requestMany(_ packet: Packet, isLast: @escaping (Packet) -> Bool) async throws -> [Packet] {
        try await serialized { [weak self] in
            guard let self else { throw TransportError.notOpen }
            try self.write(packet)
            var responses: [Packet] = []
            while responses.count < 32, let p = await self.wait(for: packet.command, timeout: 2) {
                responses.append(p)
                if isLast(p) { break }
            }
            if responses.isEmpty { throw TransportError.timedOut(packet.command) }
            return responses
        }
    }

    private func serialized<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = queueTail
        let task = Task { @MainActor () async throws -> T in
            await previous?.value
            return try await operation()
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func write(_ packet: Packet) throws {
        guard let channel, isOpen else { throw TransportError.notOpen }
        let bytes = packet.encoded()
        let mtu = max(Int(channel.getMTU()), 32)
        log.debug("TX \(packet.description, privacy: .public)")
        var offset = 0
        while offset < bytes.count {
            var chunk = Array(bytes[offset..<min(bytes.count, offset + mtu)])
            let r = chunk.withUnsafeMutableBytes { buf in
                channel.writeSync(buf.baseAddress, length: UInt16(buf.count))
            }
            if r != kIOReturnSuccess { throw TransportError.writeFailed(r) }
            offset += chunk.count
        }
    }

    private func wait(for command: Command, timeout: TimeInterval) async -> Packet? {
        await withCheckedContinuation { (c: CheckedContinuation<Packet?, Never>) in
            let id = UUID()
            waiters.append(Waiter(id: id, command: command, continuation: c))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, let i = self.waiters.firstIndex(where: { $0.id == id }) else { return }
                self.waiters.remove(at: i).continuation.resume(returning: nil)
            }
        }
    }

    private func failAllWaiters() {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.continuation.resume(returning: nil) }
    }

    // MARK: Inbound

    fileprivate func received(_ bytes: [UInt8]) {
        for packet in parser.feed(bytes) {
            log.debug("RX \(packet.description, privacy: .public)")
            if let i = waiters.firstIndex(where: { $0.command == packet.command }) {
                waiters.remove(at: i).continuation.resume(returning: packet)
            } else {
                onPacket?(packet)
            }
        }
    }

    fileprivate func openCompleted(_ status: IOReturn) {
        guard let c = openContinuation else { return }
        openContinuation = nil
        if status == kIOReturnSuccess {
            c.resume()
        } else {
            channel = nil
            c.resume(throwing: TransportError.openFailed(status))
        }
    }

    fileprivate func channelClosed() {
        let wasClosed = closed
        closed = true
        channel = nil
        openCompleted(kIOReturnNotOpen)
        failAllWaiters()
        if !wasClosed { onClose?() }
    }
}

extension RFCOMMConnection: IOBluetoothRFCOMMChannelDelegate {
    nonisolated func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        MainActor.assumeIsolated { received(bytes) }
    }

    nonisolated func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        MainActor.assumeIsolated { openCompleted(error) }
    }

    nonisolated func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        MainActor.assumeIsolated { channelClosed() }
    }
}
