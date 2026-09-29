//
//  RecipeJsonTests.swift
//  DiceKeysTests
//

import Testing
@testable import DiceKeys

@Suite("Recipe JSON canonical form")
struct RecipeJsonTests {
    @Test("fields sort with purpose first, # last, then UTF-16 code unit order")
    func objectOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "#", value: .int(3)),
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "purpose", value: .text("p")),
            RecipeJsonField(name: "B", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(0))
        ])
        #expect(object.canonicalText == ##"{"purpose":"p","B":2,"a":0,"b":1,"#":3}"##)
    }

    @Test("duplicate names keep their original order")
    func duplicatesAreStable() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "b", value: .int(1)),
            RecipeJsonField(name: "a", value: .int(2)),
            RecipeJsonField(name: "a", value: .int(1))
        ])
        #expect(object.canonicalText == ##"{"a":2,"a":1,"b":1}"##)
    }

    @Test("nested objects and arrays use the same rule at every level")
    func nestedOrder() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "x", value: .object([
                RecipeJsonField(name: "z", value: .int(1)),
                RecipeJsonField(name: "purpose", value: .text("p")),
                RecipeJsonField(name: "#", value: .int(2))
            ])),
            RecipeJsonField(name: "list", value: .array([.bool(true), .null, .number(text: "1.50")]))
        ])
        #expect(object.canonicalText == ##"{"list":[true,null,1.50],"x":{"purpose":"p","z":1,"#":2}}"##)
    }

    @Test("strings built from Swift text are escaped like JSON.stringify")
    func stringEscaping() {
        #expect(RecipeJsonValue.text("say \"hi\" \\ tab\tend").canonicalText == #""say \"hi\" \\ tab\tend""#)
        #expect(RecipeJsonValue.text("\u{01}\u{08}\u{0C}\n\r").canonicalText == #""\u0001\b\f\n\r""#)
        #expect(RecipeJsonValue.text("café/😀").canonicalText == #""café/😀""#)
    }

    @Test("canonically equivalent names still sort by their UTF-16 code units")
    func equivalentNamesSortByCodeUnits() {
        let object = RecipeJsonValue.object([
            RecipeJsonField(name: "\u{E9}", value: .int(1)),
            RecipeJsonField(name: "e\u{301}", value: .int(2))
        ])
        #expect(object.canonicalText == "{\"e\u{301}\":2,\"\u{E9}\":1}")
    }
}
