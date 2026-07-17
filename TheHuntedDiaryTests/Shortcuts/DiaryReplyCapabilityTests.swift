import Foundation
import Testing
@testable import TheHuntedDiary

struct DiaryReplyCapabilityTests {
    private let requestID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!

    @Test func generationUsesA32ByteRandomCapability() throws {
        let first = try DiaryReplyCapability.generate(requestID: requestID)
        let second = try DiaryReplyCapability.generate(requestID: requestID)

        #expect(first.capability.count == 32)
        #expect(second.capability.count == 32)
        #expect(first.capability != second.capability)
        #expect(first.handle.count == DiaryReplyCapability.maximumHandleLength)
    }

    @Test func base64URLHandleRoundTripsWithoutPadding() throws {
        let capabilityBytes = Data(0..<32)
        let capability = try DiaryReplyCapability(requestID: requestID, capability: capabilityBytes)

        #expect(capability.handle == "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8")
        #expect(!capability.handle.contains("="))

        let parsed = try DiaryReplyCapability(handle: capability.handle)
        #expect(parsed.requestID == requestID)
        #expect(parsed.capability == capabilityBytes)
        #expect(parsed.handle == capability.handle)
    }

    @Test func parsesUppercaseUUIDAndCanonicalizesItToLowercase() throws {
        let handle = "01234567-89AB-CDEF-0123-456789ABCDEF.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"

        let parsed = try DiaryReplyCapability(handle: handle)

        #expect(parsed.requestID == requestID)
        #expect(parsed.handle.hasPrefix("01234567-89ab-cdef-0123-456789abcdef."))
    }

    @Test(arguments: [
        "",
        "01234567-89ab-cdef-0123-456789abcdef",
        "01234567-89ab-cdef-0123-456789abcdef.",
        ".AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
        "not-a-uuid.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8.extra",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh=",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh9",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh+",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh/",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8 ",
        "01234567-89ab-cdef-0123-456789abcdef.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"
    ])
    func rejectsMalformedAndNoncanonicalHandles(_ handle: String) {
        #expect(throws: DiaryReplyCapability.ParseError.self) {
            try DiaryReplyCapability(handle: handle)
        }
    }

    @Test func rejectsOversizedHandleBeforeParsingItsContents() {
        let secretMarker = String(repeating: "S", count: DiaryReplyCapability.maximumHandleLength + 1)

        do {
            _ = try DiaryReplyCapability(handle: secretMarker)
            Issue.record("Expected an oversized handle to be rejected")
        } catch {
            #expect(error is DiaryReplyCapability.ParseError)
            #expect(!String(describing: error).contains(secretMarker))
        }
    }

    @Test func rejectsCapabilitiesThatAreNotExactly32Bytes() {
        #expect(throws: DiaryReplyCapability.ParseError.self) {
            try DiaryReplyCapability(requestID: requestID, capability: Data(repeating: 0xA5, count: 31))
        }
        #expect(throws: DiaryReplyCapability.ParseError.self) {
            try DiaryReplyCapability(requestID: requestID, capability: Data(repeating: 0xA5, count: 33))
        }
    }

    @Test func capabilityDigestIsSHA256() throws {
        let capability = try DiaryReplyCapability(requestID: requestID, capability: Data(0..<32))

        #expect(capability.capabilityDigest.hex == "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd")
        #expect(capability.capabilityDigest.count == 32)
    }

    @Test func constantTimeEqualityHandlesEqualDifferentAndUnequalLengthData() {
        let value = Data(repeating: 0x5A, count: 32)
        var different = value
        different[31] = 0x5B

        #expect(DiaryReplyCapability.constantTimeEqual(value, value))
        #expect(!DiaryReplyCapability.constantTimeEqual(value, different))
        #expect(!DiaryReplyCapability.constantTimeEqual(value, value.dropLast()))
        #expect(!DiaryReplyCapability.constantTimeEqual(Data(), Data([0])))
    }

    @Test func validationComparesTheDigestWithoutExposingTheCapability() throws {
        let capability = try DiaryReplyCapability(requestID: requestID, capability: Data(0..<32))
        var wrongDigest = capability.capabilityDigest
        wrongDigest[0] ^= 0xFF

        #expect(capability.validates(digest: capability.capabilityDigest))
        #expect(!capability.validates(digest: wrongDigest))
    }

    @Test func capabilityValidationIsUsableInsideAnActor() async throws {
        let capability = try DiaryReplyCapability(requestID: requestID, capability: Data(0..<32))
        let validator = CapabilityValidator()

        #expect(await validator.validate(capability, digest: capability.capabilityDigest))
    }

    @Test func descriptionsAndErrorsRedactCapabilityMaterial() throws {
        let capability = try DiaryReplyCapability(requestID: requestID, capability: Data(0..<32))
        let encodedSecret = capability.handle.split(separator: ".")[1]

        #expect(capability.description.contains("01234567"))
        #expect(!capability.description.contains(encodedSecret))
        #expect(!capability.description.contains(capability.handle))
        #expect(!String(reflecting: capability).contains(encodedSecret))
        #expect(!String(reflecting: capability).contains(capability.handle))

        do {
            _ = try DiaryReplyCapability(handle: capability.handle + ".duplicate")
            Issue.record("Expected duplicate handle fields to be rejected")
        } catch {
            let description = String(describing: error)
            #expect(description.count < 96)
            #expect(!description.contains(encodedSecret))
            #expect(!description.contains(capability.handle))
        }
    }

    @Test func reflectionAndDumpExposeOnlyTheBoundedRequestPrefix() throws {
        let capability = try DiaryReplyCapability(requestID: requestID, capability: Data(0..<32))
        let mirror = Mirror(reflecting: capability)
        let mirroredData = mirror.children.compactMap { $0.value as? Data }
        var dumpOutput = ""

        dump(capability, to: &dumpOutput)

        #expect(mirroredData.isEmpty)
        #expect(mirror.children.count == 1)
        #expect(mirror.children.first?.label == "request")
        #expect(mirror.children.first?.value as? String == "01234567…")
        #expect(dumpOutput.contains("01234567…"))
        #expect(!dumpOutput.contains("89ab-cdef-0123-456789abcdef"))
        #expect(!dumpOutput.contains(capability.handle))
        #expect(!dumpOutput.contains(capability.capability.hex))
    }
}

private actor CapabilityValidator {
    func validate(_ capability: DiaryReplyCapability, digest: Data) -> Bool {
        capability.validates(digest: digest)
    }
}

private extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
