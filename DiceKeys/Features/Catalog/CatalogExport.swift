//
//  CatalogExport.swift
//  DiceKeys
//

import CoreTransferable
import UniformTypeIdentifiers

/// The whole catalog as a readable JSON file, to keep anywhere without iCloud.
struct CatalogExport: Transferable {
    static let filename = "\(AppInfo.name) catalog"

    let file: CatalogFile

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { try $0.file.json() }
            .suggestedFileName { _ in filename }
    }
}
