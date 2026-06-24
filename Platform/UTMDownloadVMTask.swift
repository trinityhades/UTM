//
// Copyright © 2022 osy. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import Logging
import ZIPFoundation

/// Downloads a VM and creates a pending VM placeholder.
class UTMDownloadVMTask: UTMDownloadTask {
    init(for url: URL) {
        super.init(for: url, named: UTMDownloadVMTask.name(for: url))
    }
    
    static private func name(for url: URL) -> String {
        /// try to detect the filename from the URL
        let filename = url.lastPathComponent
        var nameWithoutZIP = "UTM Virtual Machine"
        /// Try to get the start index of the `.zip` part of the filename
        if let index = filename.range(of: ".zip", options: [])?.lowerBound {
            nameWithoutZIP = String(filename[..<index])
        }
        return nameWithoutZIP
    }
    
    override func processCompletedDownload(at location: URL, response: URLResponse?) async throws -> UTMDownloadTaskResult {
        let tempDir = fileManager.temporaryDirectory
        let originalFilename = url.lastPathComponent
        let downloadedZip = tempDir.appendingPathComponent(originalFilename)
        var fileURL: URL? = nil
        do {
            if fileManager.fileExists(atPath: downloadedZip.path) {
                try fileManager.removeItem(at: downloadedZip)
            }
            try fileManager.moveItem(at: location, to: downloadedZip)
            let utmURL = try partialUnzipOnlyUtmVM(zipFileURL: downloadedZip, destinationFolder: UTMData.defaultStorageUrl, fileManager: fileManager)
            /// set the url so we know, if it fails after this step the UTM in the ZIP is corrupted
            fileURL = utmURL
            /// remove the downloaded ZIP file
            try fileManager.removeItem(at: downloadedZip)
            /// load the downloaded VM into the UI
            let vm = try await VMData(url: utmURL)
            let wrapped = await vm.wrapped!
            return .virtualMachine(wrapped)
        } catch {
            logger.error(Logger.Message(stringLiteral: error.localizedDescription))
            if let fileURL = fileURL {
                /// remove imported UTM, as it is corrupted
                try? fileManager.removeItem(at: fileURL)
            } else {
                /// failed earlier
                try? fileManager.removeItem(at: downloadedZip)
            }
            throw error
        }
    }
    
    static func partialUnzipOnlyUtmVM(zipFileURL: URL, destinationFolder: URL, fileManager: FileManager) throws -> URL {
        do {
            return try unzipAndMoveUtmVM(zipFileURL: zipFileURL, destinationFolder: destinationFolder, fileManager: fileManager)
        } catch {
            logger.warning("Full ZIP extraction failed, falling back to partial extraction: \(error.localizedDescription)")
            return try partialExtractOnlyUtmVM(zipFileURL: zipFileURL, destinationFolder: destinationFolder, fileManager: fileManager)
        }
    }

    private func partialUnzipOnlyUtmVM(zipFileURL: URL, destinationFolder: URL, fileManager: FileManager) throws -> URL {
        try Self.partialUnzipOnlyUtmVM(zipFileURL: zipFileURL, destinationFolder: destinationFolder, fileManager: fileManager)
    }

    private static func unzipAndMoveUtmVM(zipFileURL: URL, destinationFolder: URL, fileManager: FileManager) throws -> URL {
        let extractionRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: extractionRoot)
        }
        try fileManager.unzipItem(at: zipFileURL, to: extractionRoot, skipCRC32: true)
        guard let sourceURL = findUtmBundle(in: extractionRoot, fileManager: fileManager) else {
            throw UnzipNoUTMFileError()
        }
        let destinationURL = uniqueDestination(for: sourceURL, in: destinationFolder, fileManager: fileManager)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private static func findUtmBundle(in rootURL: URL, fileManager: FileManager) -> URL? {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let itemURL as URL in enumerator {
            guard itemURL.pathExtension == "utm" else {
                continue
            }
            guard (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            guard !itemURL.pathComponents.contains("__MACOSX") else {
                continue
            }
            return itemURL
        }
        return nil
    }

    private static func uniqueDestination(for sourceURL: URL, in destinationFolder: URL, fileManager: FileManager) -> URL {
        let originalFileName = sourceURL.lastPathComponent
        let utmFileEnding = ".utm"
        var destinationUtmDirectory = originalFileName
        var duplicateIndex = 2
        while fileManager.fileExists(atPath: destinationFolder.appendingPathComponent(destinationUtmDirectory).path) {
            destinationUtmDirectory = originalFileName.replacingOccurrences(of: utmFileEnding, with: " (\(duplicateIndex))\(utmFileEnding)")
            duplicateIndex += 1
        }
        return destinationFolder.appendingPathComponent(destinationUtmDirectory, isDirectory: true)
    }

    private static func partialExtractOnlyUtmVM(zipFileURL: URL, destinationFolder: URL, fileManager: FileManager) throws -> URL {
        let utmFileEnding = ".utm"
        if let archive = Archive(url: zipFileURL, accessMode: .read),
           /// find the UTM directory and its contents
           let utmFolderInZip = utmDirectoryPath(in: archive) {
            /// get the UTM package filename
            let originalFileName = URL(fileURLWithPath: String(utmFolderInZip.dropLast())).lastPathComponent
            var destinationUtmDirectory = originalFileName
            /// check if the UTM already exists
            var duplicateIndex = 2
            while fileManager.fileExists(atPath: destinationFolder.appendingPathComponent(destinationUtmDirectory).path) {
                destinationUtmDirectory = originalFileName.replacingOccurrences(of: utmFileEnding, with: " (\(duplicateIndex))\(utmFileEnding)")
                duplicateIndex += 1
            }
            /// got destination folder name
            let destinationURL = destinationFolder.appendingPathComponent(destinationUtmDirectory, isDirectory: true)
            /// create the .utm directory
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: false)
            /// get and extract all files contained in the UTM directory, except the `__MACOSX` folder
            let containedFiles = archive.filter({ isZipPath($0.path, containedIn: utmFolderInZip) && $0.path != utmFolderInZip && !containsIgnoredZipPathComponent($0.path) })
            for file in containedFiles {
                let relativePath = String(file.path.dropFirst(utmFolderInZip.count))
                guard isSafeRelativeZipPath(relativePath) else {
                    continue
                }
                let isDirectory = file.path.hasSuffix("/")
                let extractURL = destinationURL.appendingPathComponent(relativePath, isDirectory: isDirectory)
                try fileManager.createDirectory(at: extractURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try archive.extract(file, to: extractURL, skipCRC32: true)
            }
            return destinationURL
        } else {
            throw UnzipNoUTMFileError()
        }
    }

    private static func utmDirectoryPath(in archive: Archive) -> String? {
        let utmFileEnding = ".utm"
        if let explicitDirectory = archive.first(where: { $0.path.hasSuffix("\(utmFileEnding)/") && !containsIgnoredZipPathComponent($0.path) }) {
            return explicitDirectory.path
        }
        for entry in archive where !containsIgnoredZipPathComponent(entry.path) {
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: true)
            if let index = components.firstIndex(where: { $0.hasSuffix(utmFileEnding) }) {
                return components[...index].joined(separator: "/") + "/"
            }
        }
        return nil
    }

    private static func isZipPath(_ path: String, containedIn rootPath: String) -> Bool {
        path.hasPrefix(rootPath)
    }

    private static func containsIgnoredZipPathComponent(_ path: String) -> Bool {
        path.split(separator: "/", omittingEmptySubsequences: true).contains("__MACOSX")
    }

    private static func isSafeRelativeZipPath(_ path: String) -> Bool {
        !path.split(separator: "/", omittingEmptySubsequences: true).contains("..")
    }

    private class UnzipNoUTMFileError: Error {
        var errorDescription: String? {
            NSLocalizedString("There is no UTM file in the downloaded ZIP archive.", comment: "Error shown when importing a ZIP file from web that doesn't contain a UTM Virtual Machine.")
        }
    }
    
    private class CreateUTMFailed: Error {
        var errorDescription: String? {
            NSLocalizedString("Failed to parse the downloaded VM.", comment: "UTMDownloadVMTask")
        }
    }
}

/// Downloads a URL and imports a VM ZIP or stores a boot image for a new VM.
class UTMDownloadWebImportTask: UTMDownloadTask {
    private var downloadedImagesUrl: URL {
        UTMData.defaultStorageUrl.appendingPathComponent("Downloaded Images", isDirectory: true)
    }

    override func processCompletedDownload(at location: URL, response: URLResponse?) async throws -> UTMDownloadTaskResult {
        let tempUrl = fileManager.temporaryDirectory.appendingPathComponent(filename(for: response))
        if fileManager.fileExists(atPath: tempUrl.path) {
            try fileManager.removeItem(at: tempUrl)
        }
        try fileManager.moveItem(at: location, to: tempUrl)
        defer {
            try? fileManager.removeItem(at: tempUrl)
        }
        if isZip(url: tempUrl, response: response) {
            if let vm = try? await importUTMFromZip(tempUrl) {
                return .virtualMachine(vm)
            }
            if let imageUrl = try extractFirstISO(from: tempUrl) {
                return .file(imageUrl)
            }
            throw UTMDownloadWebImportTaskError.noSupportedFileInZip
        } else {
            let imageUrl = try saveDownloadedImage(from: tempUrl)
            return .file(imageUrl)
        }
    }

    private func filename(for response: URLResponse?) -> String {
        let filename = response?.suggestedFilename ?? url.lastPathComponent
        if filename.isEmpty {
            return UUID().uuidString
        }
        return filename
    }

    private func isZip(url: URL, response: URLResponse?) -> Bool {
        let mimeType = response?.mimeType?.lowercased()
        return url.pathExtension.lowercased() == "zip" ||
        mimeType == "application/zip" ||
        mimeType == "application/x-zip-compressed"
    }

    @MainActor private func importUTMFromZip(_ zipUrl: URL) async throws -> any UTMVirtualMachine {
        let utmUrl = try UTMDownloadVMTask.partialUnzipOnlyUtmVM(zipFileURL: zipUrl, destinationFolder: UTMData.defaultStorageUrl, fileManager: fileManager)
        let vm = try await VMData(url: utmUrl)
        return vm.wrapped!
    }

    private func extractFirstISO(from zipUrl: URL) throws -> URL? {
        do {
            if let url = try extractFirstISOByUnzipping(from: zipUrl) {
                return url
            }
        } catch {
            logger.warning("Full ZIP extraction failed while looking for an ISO, falling back to partial extraction: \(error.localizedDescription)")
        }
        guard let archive = Archive(url: zipUrl, accessMode: .read) else {
            return nil
        }
        guard let entry = archive.first(where: { entry in
            URL(fileURLWithPath: entry.path).pathExtension.lowercased() == "iso" && !entry.path.hasSuffix("/")
        }) else {
            return nil
        }
        try createDownloadedImagesDirectoryIfNeeded()
        let sourceUrl = URL(fileURLWithPath: entry.path)
        let destinationUrl = UTMData.newImage(from: sourceUrl, to: downloadedImagesUrl)
        _ = try archive.extract(entry, to: destinationUrl, skipCRC32: true)
        return destinationUrl
    }

    private func extractFirstISOByUnzipping(from zipUrl: URL) throws -> URL? {
        let extractionRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: extractionRoot)
        }
        try fileManager.unzipItem(at: zipUrl, to: extractionRoot, skipCRC32: true)
        guard let sourceUrl = findFirstDownloadedISO(in: extractionRoot) else {
            return nil
        }
        try createDownloadedImagesDirectoryIfNeeded()
        let destinationUrl = UTMData.newImage(from: sourceUrl, to: downloadedImagesUrl)
        try fileManager.moveItem(at: sourceUrl, to: destinationUrl)
        return destinationUrl
    }

    private func findFirstDownloadedISO(in rootURL: URL) -> URL? {
        guard let enumerator = fileManager.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        for case let itemURL as URL in enumerator {
            guard itemURL.pathExtension.lowercased() == "iso" else {
                continue
            }
            guard (try? itemURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            guard !itemURL.pathComponents.contains("__MACOSX") else {
                continue
            }
            return itemURL
        }
        return nil
    }

    private func saveDownloadedImage(from sourceUrl: URL) throws -> URL {
        try createDownloadedImagesDirectoryIfNeeded()
        let destinationUrl = UTMData.newImage(from: sourceUrl, to: downloadedImagesUrl)
        if fileManager.fileExists(atPath: destinationUrl.path) {
            try fileManager.removeItem(at: destinationUrl)
        }
        try fileManager.moveItem(at: sourceUrl, to: destinationUrl)
        return destinationUrl
    }

    private func createDownloadedImagesDirectoryIfNeeded() throws {
        if !fileManager.fileExists(atPath: downloadedImagesUrl.path) {
            try fileManager.createDirectory(at: downloadedImagesUrl, withIntermediateDirectories: true)
        }
    }
}

enum UTMDownloadWebImportTaskError: Error {
    case noSupportedFileInZip
}

extension UTMDownloadWebImportTaskError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noSupportedFileInZip:
            return NSLocalizedString("The downloaded ZIP does not contain a UTM virtual machine or ISO image.", comment: "UTMDownloadWebImportTaskError")
        }
    }
}
