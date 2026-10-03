//
//  Joining.swift
//  Derivation
//

/// How a password's entries are joined. The raw values are the recipe's `separator` field.
public enum Separator: String, CaseIterable, Sendable {
    case hyphen = "-"
    case space = " "
    case period = "."
    case comma = ","
    case underscore = "_"
    case empty = ""
    /// One digit between each pair of entries, drawn from the entries' own blocks.
    case digits = "digits"
}

/// How a password is written from its entries.
public enum Joining: Sendable, Equatable {
    /// The reference form: the decimal entry count, then a hyphen and an entry each, with
    /// the first entry's first letter uppercased.
    case reference
    /// No count; entries joined by the separator, all lowercase, except one whole entry
    /// uppercased when `capitalize` is set.
    case modern(separator: Separator, capitalize: Bool)
}
