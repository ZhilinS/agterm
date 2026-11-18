import Foundation
import Testing
@testable import agtermCore

struct PortableSHA256Tests {
    @Test(arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        ("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
    ])
    func matchesTheStandardVectors(input: String, digest: String) {
        #expect(PortableSHA256.hex(Data(input.utf8)) == digest)
    }

    @Test func aMultiBlockInputMatchesItsDigest() {
        #expect(PortableSHA256.hex(Data(String(repeating: "a", count: 1000).utf8))
            == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }
}
