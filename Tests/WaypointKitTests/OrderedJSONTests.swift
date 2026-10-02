import Foundation
import Testing
@testable import WaypointKit

@Suite struct OrderedJSONTests {
    @Test func roundTripsTwoSpaceFilesByteForByte() throws {
        for text in [ClaudeSettingsSample.text(withWaypoint: true), ClaudeSettingsSample.text(withWaypoint: false),
                     "{}", "[]", "{\n  \"a\": [],\n  \"b\": {},\n  \"c\": null,\n  \"d\": -1.5e-3\n}"] {
            let value = try OrderedJSON.parse(text)
            #expect(value.serialized() + (text.hasSuffix("\n") ? "\n" : "") == text)
        }
    }

    @Test func keepsKeyOrderAndEscapesLikePython() throws {
        let value = try OrderedJSON.parse(#"{"z": 1, "a": "\u0001\t\"\\/é😀", "m": [true, false, null]}"#)
        #expect(value.objectPairs?.map(\.0) == ["z", "a", "m"])
        #expect(value.serialized() == "{\n  \"z\": 1,\n  \"a\": \"\\u0001\\t\\\"\\\\/é😀\",\n  \"m\": [\n    true,\n    false,\n    null\n  ]\n}")
        #expect(OrderedJSON.pythonNumber("1E3") == "1000.0")
        #expect(OrderedJSON.pythonNumber("-0") == "0")
        #expect(OrderedJSON.pythonNumber("1.50") == "1.5")
        #expect(OrderedJSON.pythonNumber("1e16") == "1e+16")
        #expect(OrderedJSON.pythonNumber("0.00001") == "1e-05")
    }

    @Test func rejectsBrokenJSON() {
        for text in ["{", "{\"a\" 1}", "[1,]", "01", "\"\u{01}\"", "{} x", "tru"] {
            #expect(throws: OrderedJSON.ParseError.self, "\(text)") { try OrderedJSON.parse(text) }
        }
    }
}
