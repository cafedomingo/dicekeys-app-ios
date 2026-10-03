//
//  RawJsonRecipeModelTests.swift
//  DiceKeysTests
//

import Derivation
import Testing

@testable import DiceKeys

@MainActor
@Suite("The raw JSON sheet's model")
struct RawJsonRecipeModelTests {
    @Test("starts on Password with the risk alert up and the empty object as its recipe")
    func start() {
        let model = RawJsonRecipeModel()
        #expect(model.type == .password)
        #expect(model.showRiskAlert)
        #expect(model.progress.recipe?.recipe == "{}")
        #expect(model.declaredType == nil)
    }

    @Test("canonicalizes and names the recipe")
    func canonical() {
        let model = RawJsonRecipeModel()
        model.showRiskAlert = false
        model.name = "n"
        model.json = ##"{ "#":2, "purpose":"x" }"##
        let recipe = model.progress.recipe
        #expect(recipe?.recipe == ##"{"purpose":"x","#":2}"##)
        #expect(recipe?.name == "n")
        #expect(recipe?.type == .password)
    }

    @Test("errors are reported, not passed through")
    func errors() {
        let model = RawJsonRecipeModel()
        model.json = "[]"
        #expect(model.progress == .error(RecipeJsonError.notAnObject.message))
        model.json = #"{"purpose":"x",}"#
        #expect(model.progress == .error(RecipeJsonError.invalid(offset: 15).message))
        model.json = "   "
        #expect(model.progress == .incomplete)
    }

    @Test("a declared type the app knows drives the menu; an unknown one does not")
    func followsDeclaredType() {
        let model = RawJsonRecipeModel()
        model.json = #"{"type":"Secret","lengthInBytes":16}"#
        #expect(model.declaredType == .secret)
        #expect(model.type == .secret)
        #expect(model.progress.recipe?.type == .secret)
        model.json = #"{"type":"Bogus"}"#
        #expect(model.declaredType == nil)
        #expect(model.type == .secret)  // the menu keeps its last value
        #expect(
            model.progress
                == .error(DerivationError.typeMismatch(recipe: "Bogus", requested: .secret).localizedDescription))
        model.json = "{}"
        model.type = .signingKey
        #expect(model.declaredType == nil)
        #expect(model.progress.recipe?.type == .signingKey)
    }

    @Test("a recipe the parser rejects is reported in the sheet, not on the derive screen")
    func parserErrors() {
        let model = RawJsonRecipeModel()
        model.json = #"{"type":"password","purpose":"x"}"#
        #expect(
            model.progress
                == .error(DerivationError.typeMismatch(recipe: "password", requested: .password).localizedDescription))
        model.json = #"{"wordList":"nonsense"}"#
        #expect(model.progress == .error(DerivationError.unknownWordList("nonsense").localizedDescription))
    }
}
