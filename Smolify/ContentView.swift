//
//  ContentView.swift
//  Smolify
//
//  Created by Jason Reyes on 12/3/25.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileConversionInfo {
    var originalSize: Int64
    var estimatedWebPSize: Int64?
    var actualWebPSize: Int64?
    var status: ConversionStatus
    
    enum ConversionStatus {
        case pending
        case converted
        case failed
        case skipped
    }
}

struct ContentView: View {
    @State private var isTargeted: Bool = false
    @State private var isConverting: Bool = false
    @State private var lastFileName: String?
    @State private var statusMessage: String = "Drag an image here to convert to WebP."
    @State private var quality: Double = 80
    @State private var selectedPreset: QualityPreset = .custom
    @State private var isUpdatingFromPreset: Bool = false
    @State private var saveNextToOriginal: Bool = true
    @State private var customOutputFolder: URL?
    @State private var queuedFiles: [URL] = []
    @State private var lastScannedFolder: URL?
    @State private var scanSubfolders: Bool = false
    @State private var fileSizes: [URL: Int64] = [:]
    @State private var fileConversionInfo: [URL: FileConversionInfo] = [:]
    @State private var isLossless: Bool = false
    @State private var logMessages: [String] = []
    @State private var skipExistingWebP: Bool = true
    @State private var preserveFolderStructure: Bool = false
    @State private var deleteOriginalAfterConversion: Bool = false
    @State private var autoCreateDestinationSubfolder: Bool = true
    @State private var conversionProgress: Double = 0.0
    @State private var currentFileIndex: Int = 0
    @State private var totalFiles: Int = 0
    
    enum QualityPreset: String, CaseIterable {
        case custom = "Custom"
        case high = "High"
        case medium = "Medium"
        case low = "Low"
        case tiny = "Tiny"
        
        var qualityValue: Double? {
            switch self {
            case .custom: return nil
            case .high: return 90
            case .medium: return 75
            case .low: return 50
            case .tiny: return 30
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Drag a single image file, adjust compression, and we’ll output WebP next to it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.secondary, style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [6]))
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    )

                VStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop image here")
                        .font(.headline)
                    Text("PNG, JPEG, TIFF, GIF, HEIC, BMP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .frame(minWidth: 320, maxWidth: 480, minHeight: 160)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop(providers:))

            // Folder scan (just below drop area)
            HStack {
                Spacer()
                HStack(spacing: 14) {
                    Button("Add images from folder…") {
                        selectSourceFolder()
                    }
                    Toggle("Include subfolders", isOn: $scanSubfolders)
                        .toggleStyle(.checkbox)
                    if let folder = lastScannedFolder {
                        Text("Last folder: \(folder.lastPathComponent)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            
            // Queue
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Queue")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        if !isConverting {
                            queuedFiles.removeAll()
                            fileSizes.removeAll()
                            fileConversionInfo.removeAll()
                        }
                    }
                    .disabled(isConverting || queuedFiles.isEmpty)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.1))
                        )
                    
                    VStack(spacing: 4) {
                        // Header row
                        HStack(spacing: 8) {
                            Text("Name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 60, alignment: .trailing)
                            Text("Est. Savings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 70, alignment: .trailing)
                            Text("Actual Savings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 80, alignment: .trailing)
                            Text("Final Size")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 70, alignment: .trailing)
                            Text("Status")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 60, alignment: .leading)
                            Spacer().frame(width: 24)
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 6)

                        Divider()

                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(queuedFiles, id: \.self) { url in
                                    HStack(spacing: 8) {
                                        Text(url.lastPathComponent)
                                            .font(.footnote)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(formattedSize(for: url))
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .frame(minWidth: 60, alignment: .trailing)
                                        Text(formattedEstimatedSavings(for: url))
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .frame(minWidth: 70, alignment: .trailing)
                                            .foregroundStyle(.secondary)
                                        Text(formattedActualSavings(for: url))
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .frame(minWidth: 80, alignment: .trailing)
                                            .foregroundStyle(actualSavingsColor(for: url))
                                        Text(formattedFinalSize(for: url))
                                            .font(.footnote)
                                            .monospacedDigit()
                                            .frame(minWidth: 70, alignment: .trailing)
                                            .foregroundStyle(.secondary)
                                        Text(statusText(for: url))
                                            .font(.footnote)
                                            .frame(minWidth: 60, alignment: .leading)
                                            .foregroundStyle(statusColor(for: url))
                                        Button {
                                            if !isConverting {
                                                if let index = queuedFiles.firstIndex(of: url) {
                                                    queuedFiles.remove(at: index)
                                                    fileSizes[url] = nil
                                                    fileConversionInfo[url] = nil
                                                }
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.secondary, .clear)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Remove from queue")
                                        .disabled(isConverting)
                                    }
                                    .padding(.horizontal, 6)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 150)
            }
            
            // Output location
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Toggle("Save next to original image", isOn: $saveNextToOriginal)
                    Toggle("Skip .webp files", isOn: $skipExistingWebP)
                        .onChange(of: skipExistingWebP) { _, newValue in
                            updateWebPFilesInQueue(skip: newValue)
                        }
                    Toggle("Preserve folder structure", isOn: $preserveFolderStructure)
                        .disabled(saveNextToOriginal || !scanSubfolders)
                    Spacer()
                }
                Spacer()
                                            .frame(height: 12)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Button("Select destination…") {
                            chooseOutputFolder()
                        }
                        .disabled(saveNextToOriginal)
                        
                        Toggle("Place converted files in Smolify WebP subfolder", isOn: $autoCreateDestinationSubfolder)
                            .toggleStyle(.checkbox)
                            .disabled(saveNextToOriginal)
                            .font(.footnote)
                    }
                }
                Spacer()
                                            .frame(height: 16)
            }
            
            // Compression
            VStack(alignment: .leading, spacing: 20) {
                // Mode picker
                HStack(spacing: 14) {
                    HStack(spacing: 4) {
                        Text("Compression:")
                        Image(systemName: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Lossy: uses the quality setting to reduce file size (best for photos).\nLossless: preserves all details, usually larger files (best for flat graphics, UI, and logos).")
                    }

                    Picker("", selection: $isLossless) {
                        Text("Lossy").tag(false)
                        Text("Lossless").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isLossless) { _, _ in
                        recalculateAllEstimates()
                    }

                    Spacer()
                }

                // Quality controls (only active for lossy mode)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Quality:")
                            Image(systemName: "questionmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("For lossy compression, this controls the trade‑off between size and fidelity.\n0 = lowest quality / smallest files, 100 = highest quality / largest files.")
                        }
                        // Continuous slider (no tick marks). Value is snapped/clamped only when used.
                        Slider(value: $quality, in: 0...100)
                            .disabled(isLossless)
                            .onChange(of: quality) { _, _ in
                                // Only set to Custom if slider is moved manually (not from preset)
                                if !isUpdatingFromPreset {
                                    selectedPreset = .custom
                                }
                                recalculateAllEstimates()
                            }
                        TextField(
                            "",
                            value: $quality,
                            format: .number.precision(.fractionLength(0))
                        )
                        .disabled(isLossless)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .font(.footnote.monospacedDigit())
                    }
                }
                .opacity(isLossless ? 0.5 : 1.0)
            }
            Spacer()
                                        .frame(height: 0)
            
            // Quality Presets
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Text("Quality Preset:")
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Quick quality presets for common use cases")
                }
                
                Picker("", selection: $selectedPreset) {
                    ForEach(QualityPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedPreset) { oldValue, newValue in
                    if let qualityValue = newValue.qualityValue {
                        isUpdatingFromPreset = true
                        quality = qualityValue
                        recalculateAllEstimates()
                        // Reset flag after allowing slider onChange to check it
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                            isUpdatingFromPreset = false
                        }
                    }
                }
                .disabled(isLossless)
                
                Spacer()
            }
            .opacity(isLossless ? 0.5 : 1.0)

            VStack(spacing: 6) {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        Spacer()
                            .frame(height: 12)
                        Toggle("Move originals to Trash", isOn: $deleteOriginalAfterConversion)
                            .disabled(isConverting)
                        Button("Convert \(queuedFiles.count) file(s)") {
                            startBatchConversion()
                        }
                        .disabled(queuedFiles.isEmpty || isConverting)
                    }
                }
                Text(outputDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                
                if !queuedFiles.isEmpty {
                    let isComplete = isBatchComplete()
                    let savings = isComplete ? calculateTotalSavings() : calculateEstimatedSavings()
                    let label = isComplete ? "Total savings:" : "Estimated savings:"
                    
                    if savings > 0 {
                        HStack {
                            Spacer()
                            Text("\(label) \(ByteCountFormatter.string(fromByteCount: savings, countStyle: .file))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if isConverting && totalFiles > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: conversionProgress, total: 1.0)
                        HStack {
                            Text("Converting: \(currentFileIndex) of \(totalFiles)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let name = lastFileName {
                                Text(name)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }

                Text("Log")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.1))
                        )

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logMessages.enumerated()), id: \.offset) { _, message in
                                Text(message)
                                    .font(.footnote.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(minHeight: 80, maxHeight: 100)
            }

            Spacer()
        }
        .padding(24)
    }

    /// Human‑readable description of where output files will be written.
    private var outputDescription: String {
        if saveNextToOriginal {
            return "Output: same folder as original image"
        }
        
        guard let folder = customOutputFolder else {
            return "Output: No folder selected"
        }
        
        // Build a description that matches the actual path logic in `convertToWebP`.
        if autoCreateDestinationSubfolder {
            // We always use a "Smolify WebP" subfolder when this is enabled.
            return "Output: \"Smolify WebP\" subfolder in \(folder.path)"
        } else {
            return "Output: \(folder.path)"
        }
    }

    // MARK: - Drop Handling

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else {
            log("Unsupported drop.")
            return false
        }

        // Support multiple files being dropped at once by iterating all providers.
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    DispatchQueue.main.async {
                        log("Could not read dropped file.")
                    }
                    return
                }

                handleDroppedFile(url)
            }
        }

        return true
    }

    private func handleDroppedFile(_ url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        
        // If the dropped item is a folder, treat it like using "Add images from folder…"
        if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            DispatchQueue.main.async {
                lastScannedFolder = url
                log("Dropped folder: \(url.path) (include subfolders: \(scanSubfolders ? "yes" : "no"))")
            }
            scanFolderForImages(url)
            return
        }
        
        // Otherwise, treat it as a single image file.
        let allowedExtensions = ["png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "bmp", "webp"]
        let ext = url.pathExtension.lowercased()

        guard allowedExtensions.contains(ext) else {
            DispatchQueue.main.async {
                log("Unsupported file type: .\(ext)")
            }
            return
        }

        DispatchQueue.main.async {
            lastFileName = url.lastPathComponent
            if !queuedFiles.contains(url) {
                queuedFiles.append(url)
                loadFileSize(for: url)
            }
            log("Added \(url.lastPathComponent) to queue.")
        }
    }

    // MARK: - Conversion (batch)

    private func startBatchConversion() {
        guard !queuedFiles.isEmpty else {
            log("No files in queue.")
            return
        }

        let filesToConvert = queuedFiles
        DispatchQueue.main.async {
            isConverting = true
            totalFiles = filesToConvert.count
            currentFileIndex = 0
            conversionProgress = 0.0
            log("Converting \(filesToConvert.count) file(s)…")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let semaphore = DispatchSemaphore(value: 4) // Limit to 4 concurrent conversions
            let group = DispatchGroup()
            let progressQueue = DispatchQueue(label: "com.smolify.progress", attributes: .concurrent)
            var completedCount = 0
            var lastError: String?

            for url in filesToConvert {
                group.enter()
                semaphore.wait() // Wait for available slot
                
                DispatchQueue.global(qos: .userInitiated).async {
                    // Update current file being processed
                    DispatchQueue.main.async {
                        lastFileName = url.lastPathComponent
                    }

                    // Perform conversion
                    if let error = convertToWebP(inputURL: url) {
                        lastError = error
                    }

                    // Update progress
                    progressQueue.async(flags: .barrier) {
                        completedCount += 1
                        DispatchQueue.main.async {
                            currentFileIndex = completedCount
                            conversionProgress = Double(completedCount) / Double(filesToConvert.count)
                        }
                    }

                    semaphore.signal() // Release slot
                    group.leave()
                }
            }

            // Wait for all conversions to complete
            group.wait()

            DispatchQueue.main.async {
                isConverting = false
                conversionProgress = 1.0
                if let error = lastError {
                    log("Finished with errors: \(error)")
                } else {
                    log("Finished converting \(filesToConvert.count) file(s).")
                }
            }
        }
    }

    // Convert a single file; returns an error message on failure, or nil on success.
    private func convertToWebP(inputURL: URL) -> String? {
        // If skip is enabled and the input file is already a WebP, skip it
        if skipExistingWebP && inputURL.pathExtension.lowercased() == "webp" {
            let fileManager = FileManager.default
            log("Skipped \(inputURL.lastPathComponent) (already a WebP file).")
            DispatchQueue.main.async {
                if let attrs = try? fileManager.attributesOfItem(atPath: inputURL.path),
                   let sizeNum = attrs[.size] as? NSNumber {
                    self.fileConversionInfo[inputURL]?.actualWebPSize = sizeNum.int64Value
                    self.fileConversionInfo[inputURL]?.status = .skipped
                }
            }
            return nil
        }
        
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let clampedQuality = max(0, min(100, Int(quality.rounded())))
        let outputDirectory: URL
        
        if saveNextToOriginal || customOutputFolder == nil {
            outputDirectory = inputURL.deletingLastPathComponent()
        } else {
            // Determine the root destination folder, optionally with an automatic subfolder.
            let destinationRoot: URL
            if autoCreateDestinationSubfolder {
                destinationRoot = customOutputFolder!.appendingPathComponent("Smolify WebP", isDirectory: true)
            } else {
                destinationRoot = customOutputFolder!
            }
            
            // If preserving folder structure, recreate the subfolder hierarchy in the destination
            if preserveFolderStructure, let scannedFolder = lastScannedFolder {
                let inputPath = inputURL.deletingLastPathComponent().path
                let scannedPath = scannedFolder.path
                
                // Calculate relative path from scanned folder to the file's folder
                if inputPath.hasPrefix(scannedPath) {
                    let relativePath = String(inputPath.dropFirst(scannedPath.count))
                    let cleanRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                    outputDirectory = destinationRoot.appendingPathComponent(cleanRelativePath, isDirectory: true)
                } else {
                    outputDirectory = destinationRoot
                }
            } else {
                outputDirectory = destinationRoot
            }
        }
        
        // Ensure the output directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: outputDirectory.path) {
            try? fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        
        let outputURL = outputDirectory.appendingPathComponent(baseName).appendingPathExtension("webp")

        // Check if we should skip existing WebP files
        if skipExistingWebP && fileManager.fileExists(atPath: outputURL.path) {
            log("Skipped \(inputURL.lastPathComponent) (WebP already exists).")
            DispatchQueue.main.async {
                if let attrs = try? fileManager.attributesOfItem(atPath: outputURL.path),
                   let sizeNum = attrs[.size] as? NSNumber {
                    self.fileConversionInfo[inputURL]?.actualWebPSize = sizeNum.int64Value
                    self.fileConversionInfo[inputURL]?.status = .skipped
                }
            }
            return nil
        }

        // Always use the bundled cwebp binary.

        // Look for a bundled cwebp inside the app (root resources and Tools/).
        var candidatePaths: [String] = []
        if let bundled = Bundle.main.url(forResource: "cwebp", withExtension: nil)?.path {
            candidatePaths.append(bundled)
        }
        if let bundledInTools = Bundle.main.url(forResource: "cwebp", withExtension: nil, subdirectory: "Tools")?.path {
            candidatePaths.append(bundledInTools)
        }

        guard let resolvedCwebpPath = candidatePaths.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return "Bundled cwebp not found or not executable inside the app bundle."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedCwebpPath)

        var args: [String] = [inputURL.path]
        if isLossless {
            args.append("-lossless")
        } else {
            args.append(contentsOf: ["-q", String(clampedQuality)])
        }
        args.append(contentsOf: ["-o", outputURL.path])
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let status = process.terminationStatus
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? ""

            if status == 0 {
                // Get actual output file size
                let actualSize: Int64?
                if let attrs = try? fileManager.attributesOfItem(atPath: outputURL.path),
                   let sizeNum = attrs[.size] as? NSNumber {
                    actualSize = sizeNum.int64Value
                } else {
                    actualSize = nil
                }
                
                // Delete original file if option is enabled
                if deleteOriginalAfterConversion {
                    do {
                        try fileManager.removeItem(at: inputURL)
                        DispatchQueue.main.async {
                            self.log("Deleted original: \(inputURL.lastPathComponent)")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.log("Warning: Could not delete original \(inputURL.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    if let size = actualSize {
                        self.fileConversionInfo[inputURL]?.actualWebPSize = size
                    }
                    self.fileConversionInfo[inputURL]?.status = .converted
                }
                
                log("OK: \(inputURL.lastPathComponent) → \(outputURL.lastPathComponent) (\(isLossless ? "lossless" : "q=\(clampedQuality)"))")
                return nil
            } else {
                DispatchQueue.main.async {
                    self.fileConversionInfo[inputURL]?.status = .failed
                }
                
                if errorText.isEmpty {
                    let msg = "Conversion failed (status \(status)) for \(inputURL.lastPathComponent)."
                    log(msg)
                    return msg
                } else {
                    let trimmed = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    log("Error for \(inputURL.lastPathComponent): \(trimmed)")
                    return trimmed
                }
            }
        } catch {
            let msg = "Failed to run cwebp: \(error.localizedDescription)"
            log(msg)
            return msg
        }
    }

    // MARK: - Folder Picker

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            customOutputFolder = panel.url
        }
    }

    // MARK: - Source Folder Scan (non-recursive)

    private func selectSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"

        if panel.runModal() == .OK, let folderURL = panel.url {
            lastScannedFolder = folderURL
            scanFolderForImages(folderURL)
            log("Scanning folder: \(folderURL.path) (include subfolders: \(scanSubfolders ? "yes" : "no"))")
        }
    }

    private func scanFolderForImages(_ folderURL: URL) {
        let allowedExtensions = ["png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "bmp", "webp"]
        let fm = FileManager.default
        let recursive = scanSubfolders

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let imageFiles: [URL]
                if recursive {
                    // Walk folder tree and include images in subfolders.
                    var collected: [URL] = []
                    if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                        for case let fileURL as URL in enumerator {
                            if allowedExtensions.contains(fileURL.pathExtension.lowercased()) {
                                collected.append(fileURL)
                            }
                        }
                    }
                    imageFiles = collected
                } else {
                    // Flat, non-recursive scan.
                    let contents = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    imageFiles = contents.filter { url in
                        allowedExtensions.contains(url.pathExtension.lowercased())
                    }
                }

                DispatchQueue.main.async {
                    var addedCount = 0
                    for url in imageFiles {
                        if !self.queuedFiles.contains(url) {
                            self.queuedFiles.append(url)
                            self.loadFileSize(for: url)
                            addedCount += 1
                        }
                    }

                    if addedCount > 0 {
                        self.log("Added \(addedCount) file(s) from folder to queue.")
                    } else {
                        self.log("No new image files found in selected folder.")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.log("Failed to read folder: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - File Info Helpers

    private func loadFileSize(for url: URL) {
        let fm = FileManager.default
        DispatchQueue.global(qos: .utility).async {
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let sizeNum = attrs[.size] as? NSNumber {
                let size = sizeNum.int64Value
                DispatchQueue.main.async {
                    self.fileSizes[url] = size
                    let isWebP = url.pathExtension.lowercased() == "webp"
                    
                    // If it's a WebP file and skip is enabled, mark it as skipped
                    if isWebP && self.skipExistingWebP {
                        if self.fileConversionInfo[url] == nil {
                            self.fileConversionInfo[url] = FileConversionInfo(
                                originalSize: size,
                                estimatedWebPSize: nil,
                                actualWebPSize: size,
                                status: .skipped
                            )
                        } else {
                            self.fileConversionInfo[url]?.status = .skipped
                            self.fileConversionInfo[url]?.actualWebPSize = size
                        }
                        self.log("Skipped \(url.lastPathComponent) (already a WebP file).")
                    } else {
                        // Initialize conversion info if not exists
                        if self.fileConversionInfo[url] == nil {
                            self.fileConversionInfo[url] = FileConversionInfo(
                                originalSize: size,
                                estimatedWebPSize: nil,
                                actualWebPSize: nil,
                                status: .pending
                            )
                        } else {
                            // Update original size if changed
                            self.fileConversionInfo[url]?.originalSize = size
                        }
                        // Calculate estimated savings
                        self.updateEstimatedSavings(for: url)
                    }
                }
            }
        }
    }

    private func formattedSize(for url: URL) -> String {
        guard let bytes = fileSizes[url] else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    
    private func updateEstimatedSavings(for url: URL) {
        guard let originalSize = fileSizes[url], originalSize > 0 else { return }
        
        let estimatedWebPSize: Int64
        if isLossless {
            estimatedWebPSize = Int64(Double(originalSize) * 0.75)
        } else {
            let qualityFactor = Double(quality) / 100.0
            let compressionRatio = 0.2 + (qualityFactor * 0.75)
            estimatedWebPSize = Int64(Double(originalSize) * compressionRatio)
        }
        
        fileConversionInfo[url]?.estimatedWebPSize = estimatedWebPSize
    }
    
    private func recalculateAllEstimates() {
        for url in queuedFiles {
            if fileConversionInfo[url]?.status == .pending {
                updateEstimatedSavings(for: url)
            }
        }
    }
    
    private func updateWebPFilesInQueue(skip: Bool) {
        let fileManager = FileManager.default
        for url in queuedFiles {
            let isWebP = url.pathExtension.lowercased() == "webp"
            guard isWebP else { continue }
            
            if skip {
                // Mark as skipped
                let size = fileSizes[url] ?? 0
                if fileConversionInfo[url] == nil {
                    fileConversionInfo[url] = FileConversionInfo(
                        originalSize: size,
                        estimatedWebPSize: nil,
                        actualWebPSize: size,
                        status: .skipped
                    )
                } else {
                    fileConversionInfo[url]?.status = .skipped
                    fileConversionInfo[url]?.actualWebPSize = fileSizes[url]
                }
            } else {
                // Mark as pending if it was skipped only because it's a WebP
                if let info = fileConversionInfo[url],
                   info.status == .skipped,
                   info.actualWebPSize == fileSizes[url] {
                    // This was skipped because it's a WebP, reset to pending
                    fileConversionInfo[url]?.status = .pending
                    fileConversionInfo[url]?.actualWebPSize = nil
                    updateEstimatedSavings(for: url)
                }
            }
        }
    }
    
    private func formattedEstimatedSavings(for url: URL) -> String {
        guard let info = fileConversionInfo[url],
              let estimatedWebP = info.estimatedWebPSize,
              info.status == .pending else {
            return "—"
        }
        let savings = info.originalSize - estimatedWebP
        if savings <= 0 {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: savings, countStyle: .file)
    }
    
    private func formattedActualSavings(for url: URL) -> String {
        guard let info = fileConversionInfo[url],
              let actualWebP = info.actualWebPSize,
              info.status == .converted || info.status == .skipped else {
            return "—"
        }
        
        if info.originalSize <= 0 {
            return "—"
        }
        
        let savings = info.originalSize - actualWebP
        let percentage = Double(savings) / Double(info.originalSize) * 100.0
        
        if savings <= 0 {
            return "0%"
        }
        
        return String(format: "%.1f%%", percentage)
    }
    
    private func formattedFinalSize(for url: URL) -> String {
        guard let info = fileConversionInfo[url],
              let actualWebP = info.actualWebPSize,
              info.status == .converted || info.status == .skipped else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: actualWebP, countStyle: .file)
    }
    
    private func statusText(for url: URL) -> String {
        guard let info = fileConversionInfo[url] else {
            return "Pending"
        }
        switch info.status {
        case .pending:
            return "Pending"
        case .converted:
            return "Converted"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        }
    }
    
    private func statusColor(for url: URL) -> Color {
        guard let info = fileConversionInfo[url] else {
            return .secondary
        }
        switch info.status {
        case .pending:
            return .secondary
        case .converted:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .orange
        }
    }
    
    private func actualSavingsColor(for url: URL) -> Color {
        guard let info = fileConversionInfo[url],
              let actualWebP = info.actualWebPSize,
              info.status == .converted || info.status == .skipped else {
            return .secondary
        }
        
        if info.originalSize <= 0 {
            return .secondary
        }
        
        let savings = info.originalSize - actualWebP
        let percentage = Double(savings) / Double(info.originalSize) * 100.0
        
        if percentage > 50 {
            return .green
        } else if percentage > 20 {
            return .blue
        } else {
            return .secondary
        }
    }

    private func calculateEstimatedSavings() -> Int64 {
        let totalOriginalSize = queuedFiles.compactMap { fileSizes[$0] }.reduce(0, +)
        
        guard totalOriginalSize > 0 else { return 0 }
        
        // Estimate WebP size based on compression mode
        let estimatedWebPSize: Int64
        if isLossless {
            // Lossless typically achieves 20-30% reduction
            estimatedWebPSize = Int64(Double(totalOriginalSize) * 0.75)
        } else {
            // Lossy compression varies with quality
            // Rough estimates: q100 = 95% of original, q80 = 30-50% of original, q0 = 10-20% of original
            let qualityFactor = Double(quality) / 100.0
            let compressionRatio = 0.2 + (qualityFactor * 0.75) // Range from 20% to 95%
            estimatedWebPSize = Int64(Double(totalOriginalSize) * compressionRatio)
        }
        
        return max(0, totalOriginalSize - estimatedWebPSize)
    }
    
    private func calculateTotalSavings() -> Int64 {
        var totalOriginalSize: Int64 = 0
        var totalWebPSize: Int64 = 0
        
        for url in queuedFiles {
            guard let info = fileConversionInfo[url],
                  let originalSize = fileSizes[url],
                  let actualWebP = info.actualWebPSize,
                  info.status == .converted || info.status == .skipped else {
                continue
            }
            totalOriginalSize += originalSize
            totalWebPSize += actualWebP
        }
        
        return max(0, totalOriginalSize - totalWebPSize)
    }
    
    private func isBatchComplete() -> Bool {
        guard !queuedFiles.isEmpty else { return false }
        
        // Check if all files have a status other than pending
        for url in queuedFiles {
            guard let info = fileConversionInfo[url] else {
                return false // Missing info means not complete
            }
            if info.status == .pending {
                return false
            }
        }
        return true
    }

    // MARK: - Logging

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.statusMessage = message
            self.logMessages.append(message)
            if self.logMessages.count > 200 {
                self.logMessages.removeFirst(self.logMessages.count - 200)
            }
        }
    }

}

#Preview {
    ContentView()
}
