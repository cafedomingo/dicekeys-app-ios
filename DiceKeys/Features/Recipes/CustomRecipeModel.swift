//
//  CustomRecipeModel.swift
//  DiceKeys
//
//  Created by Stuart Schechter on 2020/12/11.
//

import Foundation
import Observation

enum RecipeBuildType {
    case hosts
    case purpose
    case rawJson
}

/// Builds a custom recipe from a web address, a purpose string, or raw JSON.
/// Every edit recomputes `progress`.
@MainActor @Observable
final class CustomRecipeModel: Identifiable {
    let type: SeededCryptoRecipeType

    private(set) var progress: RecipeBuilderProgress = .incomplete

    var buildType: RecipeBuildType = .hosts {
        didSet {
            update()
            if buildType == .rawJson {
                showRawJsonAlert = true
            }
        }
    }
    var urlString: String = "" { didSet { update() } }
    var purposeString: String = "" { didSet { update() } }
    var rawJsonString: String = "{}" { didSet { update() } }
    var nameString: String = "" { didSet { update() } }
    var sequenceNumber: Int = 1 { didSet { update() } }
    var lengthInChars: Int = 0 { didSet { update() } }
    var lengthInBytes: Int = 0 { didSet { update() } }

    var showRawJsonAlert: Bool = false

    /// Text-field view of `lengthInChars`: empty means "no limit"; values
    /// outside 8...999 are ignored.
    var lengthInCharsEntry: Int? {
        get { lengthInChars == 0 ? nil : lengthInChars }
        set {
            guard let newValue else { lengthInChars = 0; return }
            if (8...999).contains(newValue) { lengthInChars = newValue }
        }
    }

    /// Text-field view of `lengthInBytes`: empty means the default (32);
    /// values outside 16...999 are ignored.
    var lengthInBytesEntry: Int? {
        get { lengthInBytes == 0 ? nil : lengthInBytes }
        set {
            guard let newValue else { lengthInBytes = 0; return }
            if (16...999).contains(newValue) { lengthInBytes = newValue }
        }
    }

    var hosts: [String]? {
        if let host = URL(string: urlString)?.host {
            // The field contains a valid URL from which to take a host
            return [host]
        } else if urlString.contains("/") || urlString.contains(":") {
            // The field was an invalid URL and not a list of URLs
            return nil
        } else {
            // Assume the field was meant to be a URL or list of URLs
            return urlString
                .split(whereSeparator: { $0 == "/" || $0 == " " })
                .map {
                    // Use built-in URL parser to parse domain name, returning empty string if it fails
                    URL(string: "https://\($0.trimmingCharacters(in: .whitespacesAndNewlines))")?.host ?? ""
                }
                .filter { !$0.isEmpty }
        }
    }

    var name: String {
        switch buildType {
        case .hosts: return hosts?.joined(separator: ", ") ?? ""
        case .purpose: return purposeString
        case .rawJson: return nameString
        }
    }

    init(type: SeededCryptoRecipeType) {
        self.type = type
        update()
    }

    private func update() {
        switch buildType {
        case .hosts:
            guard let hosts else {
                progress = .error("Field does not contain a valid URL or domain list")
                return
            }
            guard hosts.contains(where: { $0 != "example.com" }) else {
                progress = .incomplete
                return
            }
        case .purpose:
            guard !purposeString.isBlank else {
                progress = .incomplete
                return
            }
        case .rawJson:
            guard !rawJsonString.isBlank else {
                progress = .incomplete
                return
            }
        }

        let recipe: String
        let lengthInChars = type == .Password ? lengthInChars : 0
        let lengthInBytes = type == .Secret ? lengthInBytes : 0

        switch buildType {
        case .hosts:
            recipe = getRecipeJson(hosts: hosts ?? [""], sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
        case .purpose:
            recipe = getRecipeJson(purpose: purposeString.trim(), sequenceNumber: sequenceNumber, lengthInChars: lengthInChars, lengthInBytes: lengthInBytes)
        case .rawJson:
            recipe = rawJsonString.canonicalizeRecipeJson()
        }

        progress = .ready(DerivationRecipe(type: type, name: name, recipe: recipe))
    }
}
