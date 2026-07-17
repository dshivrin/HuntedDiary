import CryptoKit
import Foundation
import Security

nonisolated struct DiaryReplyCapability: Sendable, CustomStringConvertible, CustomReflectable {
    static let capabilityByteCount = 32
    static let encodedCapabilityLength = 43
    static let maximumHandleLength = 36 + 1 + encodedCapabilityLength

    let requestID: UUID
    let capability: Data

    init(requestID: UUID, capability: Data) throws {
        guard capability.count == Self.capabilityByteCount else {
            throw ParseError.invalidCapabilityLength
        }

        self.requestID = requestID
        self.capability = capability
    }

    init(handle: String) throws {
        guard handle.utf8.count <= Self.maximumHandleLength else {
            throw ParseError.handleTooLong
        }

        let fields = handle.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 2 else {
            throw ParseError.malformedHandle(requestPrefix: Self.requestPrefix(in: handle))
        }

        let idField = String(fields[0])
        guard idField.utf8.count == 36, let requestID = UUID(uuidString: idField) else {
            throw ParseError.malformedHandle(requestPrefix: nil)
        }

        let capabilityField = String(fields[1])
        guard capabilityField.utf8.count == Self.encodedCapabilityLength,
              capabilityField.utf8.allSatisfy(Self.isBase64URLCharacter),
              let capability = Self.decodeBase64URL(capabilityField),
              capability.count == Self.capabilityByteCount,
              Self.encodeBase64URL(capability) == capabilityField else {
            throw ParseError.malformedHandle(requestPrefix: Self.prefix(for: requestID))
        }

        self.requestID = requestID
        self.capability = capability
    }

    static func generate(requestID: UUID = UUID()) throws -> Self {
        var bytes = [UInt8](repeating: 0, count: capabilityByteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, capabilityByteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw ParseError.secureRandomGenerationFailed
        }

        return try Self(requestID: requestID, capability: Data(bytes))
    }

    var handle: String {
        "\(requestID.uuidString.lowercased()).\(Self.encodeBase64URL(capability))"
    }

    var capabilityDigest: Data {
        Data(SHA256.hash(data: capability))
    }

    func validates(digest expectedDigest: Data) -> Bool {
        Self.constantTimeEqual(capabilityDigest, expectedDigest)
    }

    static func constantTimeEqual<LHS: Collection, RHS: Collection>(
        _ lhs: LHS,
        _ rhs: RHS
    ) -> Bool where LHS.Element == UInt8, RHS.Element == UInt8 {
        let left = Array(lhs)
        let right = Array(rhs)
        let comparisonCount = max(left.count, right.count)
        var difference = left.count ^ right.count

        for index in 0..<comparisonCount {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= Int(leftByte ^ rightByte)
        }

        return difference == 0
    }

    var description: String {
        "DiaryReplyCapability(request: \(Self.prefix(for: requestID))…)"
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["request": "\(Self.prefix(for: requestID))…"],
            displayStyle: .struct
        )
    }

    enum ParseError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case handleTooLong
        case malformedHandle(requestPrefix: String?)
        case invalidCapabilityLength
        case secureRandomGenerationFailed

        var description: String {
            switch self {
            case .handleTooLong:
                return "Diary reply request handle is too long."
            case let .malformedHandle(requestPrefix):
                if let requestPrefix {
                    return "Diary reply request \(requestPrefix)… has a malformed capability."
                }
                return "Diary reply request handle is malformed."
            case .invalidCapabilityLength:
                return "Diary reply capability must contain exactly 32 bytes."
            case .secureRandomGenerationFailed:
                return "Diary reply capability generation failed."
            }
        }

        var errorDescription: String? { description }
    }
}

private extension DiaryReplyCapability {
    static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4))
        return Data(base64Encoded: base64)
    }

    static func isBase64URLCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case 45, 48...57, 65...90, 95, 97...122:
            return true
        default:
            return false
        }
    }

    nonisolated static func prefix(for requestID: UUID) -> String {
        String(requestID.uuidString.lowercased().prefix(8))
    }

    static func requestPrefix(in handle: String) -> String? {
        let candidate = String(handle.prefix(36))
        guard let requestID = UUID(uuidString: candidate) else { return nil }
        return prefix(for: requestID)
    }
}
