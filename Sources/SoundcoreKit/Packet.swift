import Foundation

/// Two-byte command identifier. Requests and their acknowledgements share the same command.
public struct Command: Hashable, Sendable, CustomStringConvertible {
    public let group: UInt8
    public let id: UInt8

    public init(_ group: UInt8, _ id: UInt8) {
        self.group = group
        self.id = id
    }

    public var description: String { String(format: "%02x %02x", group, id) }
}

/// A Soundcore RFCOMM frame:
///
///     [direction: 5][command: 2][total length: u16 LE][body: n][checksum: 1]
///
/// The checksum is the wrapping sum of every preceding byte. The length counts the whole frame.
public struct Packet: Sendable, Equatable, CustomStringConvertible {
    public enum Direction: Sendable {
        case outbound
        case inbound

        public var header: [UInt8] {
            switch self {
            case .outbound: [0x08, 0xEE, 0x00, 0x00, 0x00]
            case .inbound: [0x09, 0xFF, 0x00, 0x00, 0x01]
            }
        }
    }

    public static let overhead = 5 + 2 + 2 + 1

    public var command: Command
    public var body: [UInt8]

    public init(_ command: Command, _ body: [UInt8] = []) {
        self.command = command
        self.body = body
    }

    public func encoded(_ direction: Direction = .outbound) -> [UInt8] {
        let length = UInt16(Self.overhead + body.count)
        var bytes = direction.header
        bytes.reserveCapacity(Int(length))
        bytes += [command.group, command.id, UInt8(length & 0xFF), UInt8(length >> 8)]
        bytes += body
        bytes.append(Self.checksum(bytes))
        return bytes
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, &+)
    }

    public var description: String {
        "[\(command)] " + body.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}

/// Reassembles inbound frames from an RFCOMM byte stream. Resynchronises on the inbound header
/// when garbage or a corrupt frame is encountered instead of discarding the whole buffer.
public struct PacketStreamParser: Sendable {
    private var buffer: [UInt8] = []
    private let header = Packet.Direction.inbound.header

    public init() {}

    public mutating func feed(_ bytes: [UInt8]) -> [Packet] {
        buffer += bytes
        var packets: [Packet] = []
        while true {
            guard let start = headerIndex() else {
                // Keep a possible partial header at the tail.
                buffer = Array(buffer.suffix(header.count - 1))
                break
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 9 else { break }
            let length = Int(buffer[7]) | (Int(buffer[8]) << 8)
            guard length >= Packet.overhead, length <= 4096 else {
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= length else { break }
            let frame = buffer[0..<length]
            if Packet.checksum(frame.dropLast()) == frame.last {
                let command = Command(frame[5], frame[6])
                packets.append(Packet(command, Array(frame[9..<(length - 1)])))
                buffer.removeFirst(length)
            } else {
                buffer.removeFirst()
            }
        }
        return packets
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= header.count else { return nil }
        for i in 0...(buffer.count - header.count) where buffer[i] == header[0] {
            if buffer[i..<(i + header.count)].elementsEqual(header) { return i }
        }
        return nil
    }
}

/// Cursor over a packet body.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }

    mutating func u8() throws -> UInt8 {
        guard remaining >= 1 else { throw ParseError.truncated(at: offset) }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func bool() throws -> Bool { try u8() != 0 }

    mutating func u16le() throws -> UInt16 {
        let b = try take(2)
        return UInt16(b[0]) | (UInt16(b[1]) << 8)
    }

    mutating func take(_ n: Int) throws -> [UInt8] {
        guard remaining >= n else { throw ParseError.truncated(at: offset) }
        defer { offset += n }
        return Array(bytes[offset..<(offset + n)])
    }

    mutating func skip(_ n: Int) throws { _ = try take(n) }

    mutating func string(_ n: Int) throws -> String {
        let raw = try take(n)
        let trimmed = raw.prefix { $0 != 0 }
        return String(decoding: trimmed, as: UTF8.self)
    }
}

public enum ParseError: Error, Equatable {
    case truncated(at: Int)
    case invalid(String)
    case unsupported
}
