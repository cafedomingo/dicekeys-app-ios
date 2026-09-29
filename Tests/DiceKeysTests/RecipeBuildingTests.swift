//
//  RecipeBuildingTests.swift
//  DiceKeysTests
//

import Testing
@testable import DiceKeys

@Suite("Building recipes from the app's fields")
struct RecipeBuildingTests {
    @Test("a purpose recipe escapes the purpose and orders the optional fields")
    func purposeRecipe() {
        #expect(getRecipeJson(purpose: #"say "hi""#) == #"{"purpose":"say \"hi\""}"#)
        #expect(getRecipeJson(purpose: "x", sequenceNumber: 2, lengthInChars: 20) == ##"{"purpose":"x","lengthInChars":20,"#":2}"##)
        #expect(getRecipeJson(purpose: "x", sequenceNumber: 1, lengthInChars: 0, lengthInBytes: 64) == #"{"purpose":"x","lengthInBytes":64}"#)
    }

    @Test("a hosts recipe sorts the hosts")
    func hostsRecipe() {
        #expect(getRecipeJson(hosts: ["b.example", "a.example"]) == #"{"allow":["a.example","b.example"]}"#)
    }

    @Test("rebuilding from a template keeps every other field, nested objects included")
    func templateRebuild() throws {
        let apple = try #require(derivationRecipeTemplates.first { $0.name == "Apple" })
        let rebuilt = DerivationRecipe(template: apple, sequenceNumber: 3, lengthInChars: 20)
        #expect(rebuilt.recipe == ##"{"allow":[{"host":"*.apple.com"},{"host":"*.icloud.com"}],"lengthInChars":20,"#":3}"##)
        #expect(rebuilt.name == "Apple Password (3)")
        let unchanged = DerivationRecipe(template: apple, sequenceNumber: 1, lengthInChars: apple.lengthInChars())
        #expect(unchanged.recipe == apple.recipe)
    }

    @Test("every template is already in canonical form and parses")
    func templatesAreCanonical() throws {
        for template in derivationRecipeTemplates {
            #expect(try template.recipe.canonicalizedRecipe() == template.recipe)
        }
    }

    @Test("accessors read the parsed recipe and return nil for anything but the expected type")
    func accessors() {
        let recipe = DerivationRecipe(type: .Password, name: "n", recipe: #"{"purpose":"café","lengthInChars":32,"lengthInBytes":32.5}"#)
        #expect(recipe.purpose() == "café")
        #expect(recipe.lengthInChars() == 32)
        #expect(recipe.lengthInBytes() == nil)
        let odd = DerivationRecipe(type: .Password, name: "n", recipe: #"{"purpose":1,"lengthInChars":true}"#)
        #expect(odd.purpose() == nil)
        #expect(odd.lengthInChars() == nil)
    }

    @Test("a stored recipe that is not JSON still loads; only the accessors are empty")
    func storedGarbageStillLoads() {
        let stored = DerivationRecipe(type: .Password, name: "old", recipe: "{not json")
        #expect(stored.recipe == "{not json")
        #expect(stored.purpose() == nil)
        #expect(stored.fields.isEmpty)
    }

    @Test("raw JSON that is not an object is reported, not passed through")
    @MainActor
    func rawJsonErrors() {
        let model = CustomRecipeModel(type: .Password)
        model.buildType = .rawJson
        model.rawJsonString = "[]"
        #expect(model.progress == .error(RecipeJsonError.notAnObject.message))
        model.rawJsonString = #"{"purpose":"x",}"#
        #expect(model.progress == .error(RecipeJsonError.invalid(offset: 15).message))
        model.rawJsonString = "   "
        #expect(model.progress == .incomplete)
        model.rawJsonString = ##"{ "#":2, "purpose":"x" }"##
        #expect(model.progress.recipe?.recipe == ##"{"purpose":"x","#":2}"##)
    }
}
