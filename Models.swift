// Uses ZIPFoundation: https://github.com/weichsel/ZIPFoundation
import SwiftUI
import Foundation
import UniformTypeIdentifiers
import ZIPFoundation
import CoreML
import StableDiffusion
import MLX
import Hub
import UIKit
import Vision
internal import Combine



struct ModelItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let displayName: String
    let path: URL
    let sizeGB: Double
}

// MARK: - ModelsView

@available(iOS 17.0, *)
struct ModelsView: View {
    @EnvironmentObject var fluxnet: FluxnetModel
    @EnvironmentObject var modelStatus: ModelStatusManager
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("selectedModelOption") private var selectedModelOption: String = ""
    @AppStorage("autoLoadModel") private var autoLoadModel: Bool = false
    @AppStorage("disableHotswap") private var disableHotswap: Bool = false
    @State private var modelOptions: [String] = []
    @State private var showImporter: Bool = false
    @State private var downloads: [DownloadItem] = []
    @State private var showDeleteAlert: Bool = false
    @State private var modelToDelete: String? = nil
    @State private var showDownloads: Bool = false
    // --- Removed model picker sheet state ---
    // --- New state for SD 1.0–2.1 / SDXL / SD3+ tabs ---
    @State private var legacyModels: [ModelItem] = []
    @State private var sdxlModels: [ModelItem] = []
    @State private var sd3Models: [ModelItem] = []
    @State private var mlxModels: [ModelItem] = []
    @State private var selectedTab: Int = 0
    @State private var selectedCategory: ModelCategory = .coreml

    @State private var animateGlow: Bool = false
    


    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 20) {
                // Model Status Card
                ModelStatusView()

                // Category Picker in glass card
                VStack(spacing: 10) {
                    Label("Model Category", systemImage: "square.grid.2x2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Picker("Category", selection: $selectedCategory) {
                        Text(ModelCategory.coreml.rawValue).tag(ModelCategory.coreml)
                        Text(ModelCategory.mlx.rawValue).tag(ModelCategory.mlx)
                    }
                    .pickerStyle(.segmented)
                    .onAppear {
                        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(fluxnet.getAccentColor())
                        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black], for: .normal)
                    }
                    .id(fluxnet.appAccentColor)
                }
                .padding(.horizontal)
                .glassCard()
                .padding(.horizontal)



                // Model Type Picker for CoreML
                if selectedCategory == .coreml {
                    VStack(spacing: 8) {
                        Label("Model Type", systemImage: "dial.low")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Model Type", selection: $selectedTab) {
                            Text("SD1.5-2.1").tag(0)
                            Text("SDXL").tag(1)
                            Text("SD3+").tag(2)
                        }
                        .pickerStyle(.segmented)
                        .onAppear {
                            UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(fluxnet.getAccentColor())
                            UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
                        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: colorScheme == .dark ? UIColor.white : UIColor.black], for: .normal)
                        }
                        .id(fluxnet.appAccentColor)
                    }
                    .padding(.horizontal)
                    .glassCard()
                    .padding(.horizontal)
                }

                // Model List Section
                VStack(spacing: 12) {
                    if selectedCategory == .coreml {
                        switch selectedTab {
                        case 0:
                            modelListView(models: legacyModels)
                        case 1:
                            modelListView(models: sdxlModels)
                        case 2:
                            modelListView(models: sd3Models)
                        default:
                            modelListView(models: legacyModels)
                        }
                    } else {
                        modelListView(models: mlxModels)
                    }
                }
                .glassCard()
                .padding(.horizontal)

                // Import/Download/Delete/Reload controls (example, can be extended)
                HStack(spacing: 14) {
                    Button(action: {
                        // Open Files app to Models directory using UIDocumentPickerViewController
                        let fm = FileManager.default
                        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                            let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
                            if !fm.fileExists(atPath: modelsDir.path) {
                                try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
                            }
                            
                            // Use UIDocumentPickerViewController to open Files app
                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootVC = windowScene.windows.first?.rootViewController {
                                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .item], asCopy: false)
                                picker.directoryURL = modelsDir
                                picker.shouldShowFileExtensions = true
                                rootVC.present(picker, animated: true)
                            }
                        }
                    }) {
                        Label("Folder", systemImage: "folder.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(GlassButtonStyle())
                    Button(action: { showDownloads.toggle() }) {
                        Label("Download", systemImage: "arrow.down.circle")
                            .font(.caption2)
                    }
                    .buttonStyle(GlassButtonStyle())

                }
                .padding(.horizontal)

                // --- Downloads Section (only show most recent) ---
                // Filter to only show the most recent active download
                let activeDownloads = downloads.filter { $0.state == .downloading || $0.state == .unzipping || $0.state == .cloning || $0.state == .failed }
                if let latestDownload = activeDownloads.last {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Downloading", systemImage: "arrow.down.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.top, 4)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(latestDownload.name)
                                    .font(.body)
                                    .fontWeight(.regular)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(latestDownload.state == .cloning ? "Downloading" : latestDownload.state.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(latestDownload.state == .failed ? .red : .secondary)
                            }
                            ZStack(alignment: .leading) {
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.1))
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor)
                                        .frame(width: geo.size.width * CGFloat(latestDownload.progress))
                                        .animation(.linear(duration: 0.2), value: latestDownload.progress)
                                }
                                .frame(height: 6)
                            }
                            HStack {
                                Spacer()
                                Text("\(Int(latestDownload.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let error = latestDownload.error {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                    
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            // Retry logic
                                            if let idx = downloads.firstIndex(where: { $0.id == latestDownload.id }) {
                                                downloads.remove(at: idx)
                                            }
                                            if latestDownload.url.pathExtension.lowercased().hasSuffix("zip") {
                                                startDownload(name: latestDownload.name, url: latestDownload.url)
                                            } else {
                                                startGitClone(name: latestDownload.name, url: latestDownload.url, modelsDir: getModelsDirectory())
                                            }
                                        }) {
                                            Label("Retry", systemImage: "arrow.clockwise")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.blue.opacity(0.8))
                                                .cornerRadius(6)
                                        }
                                        
                                        Button(action: {
                                            cancelDownload(id: latestDownload.id)
                                        }) {
                                            Label("Delete", systemImage: "trash.fill")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Color.red.opacity(0.8))
                                                .cornerRadius(6)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .glassCard(corner: 14)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) {
                            // Long press to cancel and delete
                            cancelDownload(id: latestDownload.id)
                            // Provide haptic feedback
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                        }
                    }
                    .padding(.horizontal)
                    .glassCard()
                    .padding(.horizontal)
                }

                // --- Available Downloads Section (external list of downloadable models) ---
                // Filter by category properties
                let filteredChoices = downloadChoices.filter { choice in
                    return choice.type == selectedCategory
                }
                
                // FILTER OUT ALREADY DOWNLOADED MODELS
                // Get all currently installed model names
                let allInstalledModelNames = Set(
                    legacyModels.map { $0.name } +
                    sdxlModels.map { $0.name } +
                    sd3Models.map { $0.name } +
                    mlxModels.map { $0.name }
                )
                
                // Only show models that aren't already downloaded
                // Note: We compare normalized names or raw names.
                // If installed model has "(MLX)" suffix but download choice doesn't, we might mismatch.
                // However, ModelChoice.name from Models.txt usually matches what we install.
                // Logic:
                // MLX models in Models.txt have clean names like "SDXL Turbo (MLX)" (if user typed it) or "SDXL Turbo".
                // If built-in installer logic appends (MLX), we should check that.
                
                let availableDownloads = filteredChoices.filter { choice in
                    !allInstalledModelNames.contains(choice.name)
                }
                
                if showDownloads && !availableDownloads.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Available Downloads", systemImage: "cloud.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.top, 4)
                            .padding(.bottom, 2)
                        ForEach(availableDownloads, id: \.id) { choice in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                                                    Text(choice.name
                                        .replacingOccurrences(of: " (MLX)", with: "", options: .caseInsensitive)
                                        .replacingOccurrences(of: " (CoreML)", with: "", options: .caseInsensitive))
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Text(choice.url.host ?? "")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    startDownload(name: choice.name, url: choice.url)
                                }) {
                                    Text("Download")
                                        .font(.caption2)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(GlassButtonStyle())
                            }
                            .glassCard(corner: 14)
                            .contentShape(Rectangle())
                        }
                    }
                    .padding(.horizontal)
                    .glassCard()
                    .padding(.horizontal)
                } else if showDownloads && availableDownloads.isEmpty {
                     // Empty state - do nothing (or show simple text if desired, but user asked to remove "All Models Downloaded")
                }

                Spacer(minLength: 24)
            }
            .padding(.top, 12)
        }
        .onAppear {
            scanUserModels()
            // Fetch remote models
            ModelsListLoader.shared.fetchRemoteModels()
        }
        .alert("Delete Model?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let name = modelToDelete {
                    deleteModel(name: name)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(modelToDelete ?? "")'? This cannot be undone.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("Fluxnet.ScanModels"))) { _ in
            scanUserModels()
        }
    }

    // MARK: - Helper for model list per tab
    private func modelListView(models: [ModelItem]) -> some View {
        LazyVStack(spacing: 10) {
            if models.isEmpty {
                Label("No models found", systemImage: "shippingbox.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(models) { item in
                    HStack(spacing: 14) {
                        Image(systemName: "shippingbox")
                            .foregroundColor(item.name == selectedModelOption ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName)
                                .font(.body)
                                .fontWeight(item.name == selectedModelOption ? .bold : .regular)
                                .foregroundColor(item.name == selectedModelOption ? .accentColor : .primary)
                            HStack(spacing: 6) {

                            }
                        }
                        Spacer()
                        
                        if item.name == selectedModelOption {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 16))
                        }
                        
                        Text(String(format: "%.2f GB", item.sizeGB))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                    .glassCard(corner: 14)
                    .contentShape(Rectangle())
                    .opacity((disableHotswap && (modelStatus.isLoading || modelStatus.isGenerating) && item.name != selectedModelOption) ? 0.4 : 1.0)
                    .disabled(disableHotswap && (modelStatus.isLoading || modelStatus.isGenerating) && item.name != selectedModelOption)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            print("[ModelsView] Model tapped: \(item.name)")
                            // Update AppStorage first for immediate UI feedback
                            selectedModelOption = item.name
                            UserDefaults.standard.set(item.name, forKey: "lastUsedModel")
                            print("[ModelsView] Calling handleModelSelectionChange with: \(item.name)")
                            // Immediately update FluxnetModel and unload current pipeline
                            self.fluxnet.handleModelSelectionChange(item.name)
                            print("[ModelsView] handleModelSelectionChange completed")
                        }
                    }
                    .contextMenu {
                        if item.name == selectedModelOption {
                            Button {
                                selectedModelOption = ""
                                self.fluxnet.handleModelSelectionChange("")
                            } label: {
                                Label("Unload", systemImage: "eject")
                            }
                        }
                        Button {
                            if selectedModelOption != item.name {
                                selectedModelOption = item.name
                                UserDefaults.standard.set(item.name, forKey: "lastUsedModel")
                                self.fluxnet.handleModelSelectionChange(item.name)
                            } else {
                                fluxnet.reloadTrigger = UUID()
                            }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) {
                            modelToDelete = item.name
                            showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .id(item.id) // Add ID for better diffing
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Start Download
    private func startDownload(name: String, url: URL) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
        try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let modelFolder = modelsDir.appendingPathComponent(name, isDirectory: true)
        // If already present, skip!
        if fm.fileExists(atPath: modelFolder.path) {
            // Already downloaded
            return
        }
        // If already downloading this model, skip
        if downloads.contains(where: { $0.name == name && ($0.state == DownloadItem.State.downloading || $0.state == DownloadItem.State.unzipping || $0.state == DownloadItem.State.cloning) }) {
            return
        }

        // Check if it's a git repo (not a zip)
        if !url.pathExtension.lowercased().hasSuffix("zip") {
            startGitClone(name: name, url: url, modelsDir: modelsDir)
            return
        }

        let zipURL = modelsDir.appendingPathComponent("\(name).zip")
        // Remove any broken/partial data
        if fm.fileExists(atPath: zipURL.path) {
            try? fm.removeItem(at: zipURL)
        }
        if fm.fileExists(atPath: modelFolder.path) {
            try? fm.removeItem(at: modelFolder)
        }
        // Add to downloads
        let item = DownloadItem(name: name, url: url, progress: 0, state: .downloading, error: nil)
        downloads.append(item)

        let delegate = DownloadDelegate(
            itemID: item.id,
            modelName: name,
            modelsDir: modelsDir,
            zipURL: zipURL,
            onProgress: { progress in
                if let i = downloads.firstIndex(where: { $0.id == item.id }) {
                    downloads[i].progress = progress
                    downloads[i].state = .downloading
                    Logger.shared.log("Download progress for \(name): \(Int(progress * 100))%")
                }
            },
            onUnzipProgress: { progress in
                if let i = downloads.firstIndex(where: { $0.id == item.id }) {
                    downloads[i].progress = progress
                    downloads[i].state = .unzipping
                    Logger.shared.log("Unzipping progress for \(name): \(Int(progress * 100))%")
                }
            },
            onFinish: { result in
                if let i = downloads.firstIndex(where: { $0.id == item.id }) {
                    switch result {
                    case .success:
                        Logger.shared.log("Download finished successfully: \(name)")
                    case .failure(let error):
                        Logger.shared.log("Download failed for \(name): \(error.localizedDescription)", level: .error)
                    }
                    switch result {
                    case .success:
                        downloads[i].progress = 1.0
                        downloads[i].state = .finished
                        downloads[i].error = nil
                    case .failure(let error):
                        downloads[i].progress = 0
                        downloads[i].state = .failed
                        downloads[i].error = error.localizedDescription
                    }
                }
                scanUserModels()
                // Remove from downloads after short delay if finished
                if case .success = result {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        downloads.removeAll { $0.id == item.id }
                    }
                }
            },
            onCleanup: {
                ActiveDownloads.shared.remove(id: item.id)
            }
        )
        // Use background configuration for higher throughput and fewer wakeups
        let configuration: URLSessionConfiguration = {
            let config = URLSessionConfiguration.background(withIdentifier: "fluxnet.model.download.\(item.id.uuidString)")
            config.isDiscretionary = false
            config.sessionSendsLaunchEvents = true
            config.allowsCellularAccess = true
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 120
            config.httpMaximumConnectionsPerHost = 4
            config.multipathServiceType = .handover
            return config
        }()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        Logger.shared.log("Started download for \(name)")
        let task = session.downloadTask(with: url)
        ActiveDownloads.shared.add(id: item.id, ref: ActiveDownloads.DownloadRef(session: session, task: task, delegate: delegate))
        task.resume()
    }

    private func startGitClone(name: String, url: URL, modelsDir: URL) {
        let item = DownloadItem(name: name, url: url, progress: 0, state: .cloning, error: nil)
        downloads.append(item)
        
        // Extract repo ID from URL (e.g., https://huggingface.co/stabilityai/sdxl-turbo -> stabilityai/sdxl-turbo)
        let repoId = url.path.trimmingCharacters(in: .init(charactersIn: "/"))
        
        Task {
            do {
                let hub = HubApi()
                let repo = Hub.Repo(id: repoId)
                
                // Download snapshot
                let modelFolder = try await hub.snapshot(from: repo) { progress in
                    DispatchQueue.main.async {
                        if let i = self.downloads.firstIndex(where: { $0.id == item.id }) {
                            self.downloads[i].progress = progress.fractionCompleted
                            Logger.shared.log("Hub download progress: \(Int(progress.fractionCompleted * 100))%")
                        }
                    }
                }
                
                // Move or symlink to Models directory
                // Hub stores in cache. We can symlink it to Documents/Models/name
                let dest = modelsDir.appendingPathComponent(name, isDirectory: true)
                let fm = FileManager.default
                if fm.fileExists(atPath: dest.path) {
                    try? fm.removeItem(at: dest)
                }
                
                // Copy items from cache to dest
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                let contents = try fm.contentsOfDirectory(at: modelFolder, includingPropertiesForKeys: nil)
                for content in contents {
                    let destURL = dest.appendingPathComponent(content.lastPathComponent)
                    try fm.copyItem(at: content, to: destURL)
                }
                
                // CLEANUP: Remove the cached model from Hub to avoid duplication
                // modelFolder is usually .../snapshots/<hash>
                // We want to remove .../models--<org>--<repo>
                let snapshotDir = modelFolder.deletingLastPathComponent() // snapshots
                let repoDir = snapshotDir.deletingLastPathComponent() // models--org--repo
                
                // Verify we are inside a 'models--' directory before deleting to be safe
                if repoDir.lastPathComponent.hasPrefix("models--") {
                    do {
                        try fm.removeItem(at: repoDir)
                        Logger.shared.log("Cleaned up Hub cache for \(name)")
                    } catch {
                        Logger.shared.log("Failed to clean up Hub cache: \(error.localizedDescription)", level: .error)
                    }
                }
                
                // COMPREHENSIVE CLEANUP: Remove ALL Hugging Face cache
                self.cleanupAllHuggingFaceCache()
                
                DispatchQueue.main.async {
                    if let i = self.downloads.firstIndex(where: { $0.id == item.id }) {
                        self.downloads[i].state = .finished
                        self.downloads[i].progress = 1.0
                        Logger.shared.log("Hub download finished: \(name)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.downloads.removeAll { $0.id == item.id }
                        }
                        self.scanUserModels()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if let i = self.downloads.firstIndex(where: { $0.id == item.id }) {
                        self.downloads[i].state = .failed
                        self.downloads[i].error = error.localizedDescription
                    }
                    Logger.shared.log("Hub download failed for \(name): \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    private func cancelDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        
        let downloadItem = downloads[idx]
        let modelName = downloadItem.name
        
        Logger.shared.log("Deleting failed download: \(modelName)")
        
        // Cancel active download task
        ActiveDownloads.shared.cancel(id: id)
        
        // IMMEDIATELY delete partial files from filesystem
        let fm = FileManager.default
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
            let modelFolder = modelsDir.appendingPathComponent(modelName)
            
            // Remove partial/failed download folder
            if fm.fileExists(atPath: modelFolder.path) {
                do {
                    try fm.removeItem(at: modelFolder)
                    Logger.shared.log("Deleted partial download folder: \(modelName)")
                } catch {
                    Logger.shared.log("Failed to delete partial folder: \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        // IMMEDIATELY remove from UI (no delay)
        downloads.removeAll { $0.id == id }
        
        // Refresh model list to ensure clean state
        scanUserModels()
    }
    
    // MARK: - Hugging Face Cache Cleanup
    /// Removes ALL Hugging Face cache to free up storage after downloading models
    private func cleanupAllHuggingFaceCache() {
        let fm = FileManager.default
        
        // Potential cache locations on iOS
        let cachePaths: [URL] = [
            // Primary cache location (Caches directory)
            fm.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("huggingface"),
            // Alternative location (Library directory - sometimes used)
            fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent(".cache/huggingface"),
            // Manual Home Directory .cache (Standard linux/mac CLI tools default)
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".cache/huggingface")
        ].compactMap { $0 }
        
        for cachePath in cachePaths {
            if fm.fileExists(atPath: cachePath.path) {
                do {
                    // Get size before deletion for logging
                    let size = (try? fm.allocatedSizeOfDirectory(at: cachePath)) ?? 0
                    let sizeMB = Double(size) / (1024 * 1024)
                    
                    // Remove entire huggingface cache directory
                    try fm.removeItem(at: cachePath)
                    Logger.shared.log("✅ Deleted Hugging Face cache at \(cachePath.path) (freed \(String(format: "%.1f", sizeMB)) MB)")
                } catch {
                    Logger.shared.log("⚠️ Failed to delete Hugging Face cache at \(cachePath.path): \(error.localizedDescription)", level: .error)
                }
            }
        }
        
        // Also clean up URL cache to be thorough
        URLCache.shared.removeAllCachedResponses()
        Logger.shared.log("🧹 Hugging Face cache cleanup complete")
    }


    // MARK: - Emergency Stop (E-Stop)
    private func eStop() {
        Logger.shared.log("E-Stop invoked - FULL SHUTDOWN")
        
        // 1) Cancel all active downloads & sessions
        ActiveDownloads.shared.cancelAll()
        
        // 2) Disable auto-reload and clear last used selection
        autoLoadModel = false
        UserDefaults.standard.removeObject(forKey: "lastUsedModel")
        NotificationCenter.default.post(name: .init("Fluxnet.EStopTriggered"), object: nil)
        
        // Update Status Manager
        modelStatus.setLoaded(false)
        
        // 3) Unload ALL Pipelines (CoreML & MLX)
        autoreleasepool {
            // CoreML Unload
            ModelLoader.currentPipeline = nil
            ModelLoader.unloadCurrentPipeline()
            
            // MLX Unload (if applicable)
            // Assuming ModelLoader handles MLX pipeline reference too, or we clear it here if exposed
            // Force MLX Cache Clear
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        }
        
        // 4) Mark any in-flight UI items as cancelled and clean up temp artifacts
        let fm = FileManager.default
        let modelsDir = getModelsDirectory()
        for i in downloads.indices {
            downloads[i].state = .cancelled
            downloads[i].progress = 0
            downloads[i].error = nil
            // Remove the zip and temp extract dir used during download/unzip
            let zipURL = modelsDir.appendingPathComponent("\(downloads[i].name).zip")
            if fm.fileExists(atPath: zipURL.path) {
                do { try fm.removeItem(at: zipURL) } catch {
                    print("[E-Stop] Failed to remove zip \(zipURL.lastPathComponent): \(error)")
                }
            }
            let tempExtractDir = modelsDir.appendingPathComponent("_\(downloads[i].name)_extract", isDirectory: true)
            if fm.fileExists(atPath: tempExtractDir.path) {
                do { try fm.removeItem(at: tempExtractDir) } catch {
                    print("[E-Stop] Failed to remove temp dir \(tempExtractDir.lastPathComponent): \(error)")
                }
            }
        }
        
        // Remove cancelled downloads from UI after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            downloads.removeAll()
        }

        // 5) Unselect model (does NOT delete any model files)
        selectedModelOption = ""

        // 6) Clear any residual storage used only during loading
        do {
            let contents = try fm.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for url in contents {
                if url.pathExtension.lowercased() == "zip" {
                    do { try fm.removeItem(at: url) } catch {
                        print("[E-Stop] Failed to remove leftover zip \(url.lastPathComponent): \(error)")
                    }
                } else {
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                        let name = url.lastPathComponent
                        if name.hasPrefix("_") && name.hasSuffix("_extract") {
                            do { try fm.removeItem(at: url) } catch {
                                print("[E-Stop] Failed to remove leftover temp dir \(name): \(error)")
                            }
                        }
                    }
                }
            }
        } catch {
            print("[E-Stop] Models directory scan failed: \(error)")
        }

        // 7) Aggressive Memory Scrub
        DispatchQueue.global(qos: .userInitiated).async {
            zeroMemoryScrub()
            // Additional cleanup
            URLCache.shared.removeAllCachedResponses()
            // Clean up Hugging Face cache
            cleanupAllHuggingFaceCache()
        }
    }

    /// Allocate and overwrite volatile memory with zeros to scrub process RAM.
    /// This is a best-effort scrub and may not fully return pages to the system immediately.
    private func zeroMemoryScrub() {
        print("[E-Stop] Starting memory scrub...")
        // Determine a more aggressive target based on reported total memory
        let totalMB = max(0, Int(modelStatus.memTotalMB))
        // Scrub up to 3/4 of total memory, clamped between 256MB and 2048MB (Increased max)
        let targetMB = min(max((totalMB * 3) / 4, 256), 2048)
        let chunkMB = 64 // Larger chunks
        let chunkSize = chunkMB * 1024 * 1024
        let iterations = max(1, targetMB / chunkMB)

        var buffers: [Data] = []
        buffers.reserveCapacity(iterations)

        // Allocate zero-filled chunks
        for _ in 0..<iterations {
            autoreleasepool {
                let d = Data(count: chunkSize) // zero-filled
                buffers.append(d)
            }
        }

        // Explicitly overwrite each chunk with zeros again to ensure pages are dirtied with 0x00
        for i in 0..<buffers.count {
            autoreleasepool {
                let z = Data(count: chunkSize)
                buffers[i] = z
            }
        }

        // Drop all references and ask system caches to purge
        buffers.removeAll(keepingCapacity: false)
        URLCache.shared.removeAllCachedResponses()
        
        // Force MLX Cache Clear again just in case
        MLX.Memory.clearCache()
        
        Logger.shared.log("E-Stop memory scrub complete")
    }

    // MARK: - Import, Scan
    private func handleImport(result: Result<[URL], Error>) {
        print("[ModelsView] handleImport called with result: \(result)")
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first else { return }
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
            let destURL = modelsDir.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
            let stop = sourceURL.startAccessingSecurityScopedResource()
            defer { if stop { sourceURL.stopAccessingSecurityScopedResource() } }
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Import Model", message: "Do you want to save this model into the app?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Run Only", style: .default, handler: { _ in
                    ModelLoader.unloadCurrentPipeline()
                    ModelLoader.copySelectedModelIntoAppIfNeeded(from: sourceURL)
                    scanUserModels()
                    selectedModelOption = sourceURL.lastPathComponent
                    self.fluxnet.handleModelSelectionChange(sourceURL.lastPathComponent)
                }))
                alert.addAction(UIAlertAction(title: "Save to App", style: .default, handler: { _ in
                    ModelLoader.unloadCurrentPipeline()
                    do {
                        // if !fm.fileExists(atPath: destURL.path) {
                        //     try fm.copyItem(at: sourceURL, to: destURL)
                        // }
                        if !fm.fileExists(atPath: destURL.path) {
                            try fm.copyItem(at: sourceURL, to: destURL)
                        }
                        scanUserModels()
                        selectedModelOption = destURL.lastPathComponent
                        self.fluxnet.handleModelSelectionChange(destURL.lastPathComponent)
                        NotificationCenter.default.post(name: .init("Fluxnet.ModelTapped"), object: nil)
                    } catch {
                        print("[ModelsView] Model import failed: \(error)")
                    }
                }))
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = scene.windows.first,
                   let rootVC = window.rootViewController {
                    rootVC.present(alert, animated: true, completion: nil)
                }
            }
            return
        case .failure(let error):
            print("[ModelsView] Importer error: \(error.localizedDescription)")
        }
    }

    private func deleteModel(name: String) {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
        let modelFolder = modelsDir.appendingPathComponent(name)
        
        do {
            if fm.fileExists(atPath: modelFolder.path) {
                try fm.removeItem(at: modelFolder)
                print("Deleted model: \(name)")
                
                // If we deleted the currently selected model, unload it
                if selectedModelOption == name {
                    ModelLoader.unloadCurrentPipeline()
                    selectedModelOption = ""
                    UserDefaults.standard.removeObject(forKey: "lastUsedModel")
                    self.fluxnet.handleModelSelectionChange("")
                }
                
                // Refresh list
                scanUserModels()
            }
        } catch {
            print("Error deleting model: \(error)")
        }
    }

    private func scanUserModels() {
        // Run entire scan on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
            if !fm.fileExists(atPath: modelsDir.path) {
                try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            }

            guard let contents = try? fm.contentsOfDirectory(
                at: modelsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                DispatchQueue.main.async {
                    self.legacyModels = []
                    self.sdxlModels = []
                    self.sd3Models = []
                    self.mlxModels = []
                }
                return
            }
            
            // Get all top-level items that are directories
            let allDirs = contents.filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
            }

            var sd3: [ModelItem] = []
            var sdxl: [ModelItem] = []
            var legacy: [ModelItem] = []
            var mlx: [ModelItem] = []
            
            // Helper to clean display names
            func cleanDisplayName(_ name: String) -> String {
                return name
                    .replacingOccurrences(of: " (MLX)", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " (CoreML)", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " (Core ML)", with: "", options: .caseInsensitive)
            }

            // Some model repos store the actual model under Resources/ or other nested folders.
            // We'll check the top folder, its Resources/, and one-level subfolders (+ their Resources/) for detection.
            let resourceNames = ["Resources", "resources", "Resource", "resource", "Recources", "recources", "Recource", "recource"]
            func candidateRoots(for folder: URL) -> [URL] {
                var roots: [URL] = [folder]
                for rn in resourceNames {
                    let r = folder.appendingPathComponent(rn, isDirectory: true)
                    if fm.fileExists(atPath: r.path) { roots.append(r) }
                }
                if let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                    for child in children {
                        var isDir: ObjCBool = false
                        guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
                        roots.append(child)
                        for rn in resourceNames {
                            let r = child.appendingPathComponent(rn, isDirectory: true)
                            if fm.fileExists(atPath: r.path) { roots.append(r) }
                        }
                    }
                }
                // Deduplicate (path-based)
                var seen = Set<String>()
                return roots.filter { seen.insert($0.path).inserted }
            }

            for url in allDirs {
                let name = url.lastPathComponent
                let displayName = cleanDisplayName(name)
                
                // OPTIMIZATION: Use cached size initially (instant), calculate real size later
                let cachedSizeGB = UserDefaults.standard.double(forKey: "modelSize_\(name)")
                let sizeGB = cachedSizeGB > 0 ? cachedSizeGB : 0.0 // Show 0 if not cached
                
                // Try multiple possible roots for scattered layouts.
                let roots = candidateRoots(for: url)
                
                // 1) MLX detection (prefer MLX)
                var isMLX = false
                for root in roots {
                    let unetConfig = root.appendingPathComponent("unet").appendingPathComponent("config.json")
                    let textEncoderConfig = root.appendingPathComponent("text_encoder").appendingPathComponent("config.json")
                    let textEncoder2Config = root.appendingPathComponent("text_encoder_2").appendingPathComponent("config.json")
                    if fm.fileExists(atPath: unetConfig.path) && (fm.fileExists(atPath: textEncoderConfig.path) || fm.fileExists(atPath: textEncoder2Config.path)) {
                        isMLX = true
                        break
                    }
                }
                if isMLX {
                    mlx.append(ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB))
                    continue
                }
                
                // 2) SD3 / SDXL detection (CoreML)
                var isSD3 = false
                var isSDXL = false
                for root in roots {
                    if ModelLoader.isSD3ResourcesFolder(root) { isSD3 = true; break }
                }
                if !isSD3 {
                    for root in roots {
                        if ModelLoader.isSDXLResourcesFolder(root) { isSDXL = true; break }
                    }
                }
                if isSD3 {
                    sd3.append(ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB))
                    continue
                }
                if isSDXL {
                    sdxl.append(ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB))
                    continue
                }
                
                // 3) Legacy CoreML detection (heuristic: looks like SD coreml resources)
                var looksLikeCoreML = false
                for root in roots {
                    if ModelLoader.looksLikeStableDiffusionCoreMLResources(root) {
                        looksLikeCoreML = true
                        break
                    }
                    // Keep a quick fallback for older single-file layouts
                    if fm.fileExists(atPath: root.appendingPathComponent("unet.mlmodelc").path) ||
                        fm.fileExists(atPath: root.appendingPathComponent("Unet.mlmodelc").path) ||
                        root.pathExtension.lowercased() == "mlmodelc" {
                        looksLikeCoreML = true
                        break
                    }
                }
                if looksLikeCoreML {
                    legacy.append(ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB))
                    continue
                }
            }

            // Update UI on main thread IMMEDIATELY with cached/zero sizes
            DispatchQueue.main.async {
                self.sd3Models = sd3.sorted { $0.displayName < $1.displayName }
                self.sdxlModels = sdxl.sorted { $0.displayName < $1.displayName }
                self.legacyModels = legacy.sorted { $0.displayName < $1.displayName }
                self.mlxModels = mlx.sorted { $0.displayName < $1.displayName }
                
                var allNames: [String] = []
                allNames.append(contentsOf: self.sd3Models.map { $0.name })
                allNames.append(contentsOf: self.sdxlModels.map { $0.name })
                allNames.append(contentsOf: self.legacyModels.map { $0.name })
                allNames.append(contentsOf: self.mlxModels.map { $0.name })
                self.modelOptions = allNames
                
                if !allNames.contains(self.selectedModelOption) {
                    self.selectedModelOption = ""
                }
                
                DispatchQueue.main.async {
                    self.fluxnet.objectWillChange.send()
                }

                // Disabled auto-restore of last used model to respect "Clean Startup" request
                /*
                if self.autoLoadModel, let lastModel = UserDefaults.standard.string(forKey: "lastUsedModel") {
                    if allNames.contains(lastModel) {
                        self.selectedModelOption = lastModel
                    }
                }
                */
            }
            
            // BACKGROUND: Calculate actual sizes asynchronously and update cache
            DispatchQueue.global(qos: .utility).async {
                for url in allDirs {
                    let name = url.lastPathComponent
                    let displayName = cleanDisplayName(name)
                    
                    // Calculate actual size (expensive operation)
                    let sizeBytes = (try? fm.allocatedSizeOfDirectory(at: url)) ?? 0
                    let sizeGB = Double(sizeBytes) / 1_000_000_000.0
                    
                    // Cache the size
                    UserDefaults.standard.set(sizeGB, forKey: "modelSize_\(name)")
                    
                    // Update the specific model item on main thread
                    DispatchQueue.main.async {
                        if let idx = self.sd3Models.firstIndex(where: { $0.name == name }) {
                            self.sd3Models[idx] = ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB)
                        } else if let idx = self.sdxlModels.firstIndex(where: { $0.name == name }) {
                            self.sdxlModels[idx] = ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB)
                        } else if let idx = self.legacyModels.firstIndex(where: { $0.name == name }) {
                            self.legacyModels[idx] = ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB)
                        } else if let idx = self.mlxModels.firstIndex(where: { $0.name == name }) {
                            self.mlxModels[idx] = ModelItem(name: name, displayName: displayName, path: url, sizeGB: sizeGB)
                        }
                    }
                }
            }
        }
    }
    // System stats logic moved to FluxnetModel (shared)
// --- PATCH: Post notification on model row tap/selection ---
// This patch assumes the model row tap/selection is handled in a SwiftUI List or similar.
// Look for the assignment: selectedModelOption = ... (for selection, not import)
// Insert notification post immediately after.

}

// MARK: - Helper Extensions

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let enumerator = self.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [], errorHandler: nil)!
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile ?? false {
                size += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        return size
    }
}

// Helper to get models directory, for context menu delete
private func getModelsDirectory() -> URL {
    let fm = FileManager.default
    let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let modelsDir = docs.appendingPathComponent("Models", isDirectory: true)
    if !fm.fileExists(atPath: modelsDir.path) {
        try? fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }
    return modelsDir
}

// MARK: - UI Helpers

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}

#if canImport(Metal)
import Metal
import StableDiffusion
#endif

// MARK: - ModelLoader (Business Logic)

enum ModelLoaderError: Error, LocalizedError {
    case modelFolderNotFound
    var errorDescription: String? {
        switch self {
        case .modelFolderNotFound:
            return "Model folder may not exist. Download or import it, or switch to CPU & GPU, or select a different model if this one fails to load."
        }
    }
}

struct ModelLoader {
    // Track the most recently created pipeline so E-Stop can forcefully unload it.
    static var currentPipeline: (any StableDiffusionPipelineProtocol)?

    /// Unload and drop the current pipeline, freeing RAM. Uses ResourceManaging if available.
    @MainActor
    static func unloadCurrentPipeline() {
        autoreleasepool {
            if let rm = currentPipeline {
                rm.unloadResources()
            }
            currentPipeline = nil
            URLCache.shared.removeAllCachedResponses()
            MLX.Memory.clearCache()
        }
        NotificationCenter.default.post(name: .init("Fluxnet.ModelUnloaded"), object: nil)
    }
    // Helper: Check if a compiled CoreML model component with name containing 'needle' exists at baseURL (deep scan)
    static func containsCompiledModelComponent(at baseURL: URL, nameContains needle: String) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return false
        }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "mlmodelc" && url.lastPathComponent.localizedCaseInsensitiveContains(needle) {
                return true
            }
        }
        return false
    }

    // Helper: Check only immediate children of baseURL (shallow scan)
    static func containsCompiledModelComponentShallow(at baseURL: URL, nameContains needle: String) -> Bool {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return false
        }
        for child in children {
            if child.pathExtension.lowercased() == "mlmodelc" && child.lastPathComponent.localizedCaseInsensitiveContains(needle) {
                return true
            }
        }
        return false
    }

    /// Heuristic: does this folder look like a Stable Diffusion CoreML resources folder?
    /// We intentionally require multiple key components to avoid accidentally selecting a "safety_checker only" subfolder.
    static func looksLikeStableDiffusionCoreMLResources(_ baseURL: URL) -> Bool {
        // IMPORTANT: shallow checks only — many repos nest the real model under Resources/Resources.
        // Deep scanning would incorrectly mark the parent folder as "the model root".
        let hasVAE = containsCompiledModelComponentShallow(at: baseURL, nameContains: "VAE")
        let hasTextEncoder = containsCompiledModelComponentShallow(at: baseURL, nameContains: "TextEncoder")
        let hasUnet = containsCompiledModelComponentShallow(at: baseURL, nameContains: "Unet")
        // Require at least 2 strong signals
        let signals = [hasVAE, hasTextEncoder, hasUnet].filter { $0 }.count
        return signals >= 2
    }

    /// Find the best "resources root" inside a selected model folder.
    /// Some repos (e.g. certain John Killington CoreML repos) store the actual model under `Resources/` or other nested subfolders.
    static func resolveModelRoot(in folder: URL) -> URL {
        let fm = FileManager.default
        
        func isValidMLXRoot(_ url: URL) -> Bool {
            let unetConfig = url.appendingPathComponent("unet").appendingPathComponent("config.json")
            let textEnc1 = url.appendingPathComponent("text_encoder").appendingPathComponent("config.json")
            let textEnc2 = url.appendingPathComponent("text_encoder_2").appendingPathComponent("config.json")
            return fm.fileExists(atPath: unetConfig.path) && (fm.fileExists(atPath: textEnc1.path) || fm.fileExists(atPath: textEnc2.path))
        }
        
        func isValidCoreMLRoot(_ url: URL) -> Bool {
            if isSD3ResourcesFolder(url) { return true }
            if isSDXLResourcesFolder(url) { return true }
            if looksLikeStableDiffusionCoreMLResources(url) { return true }
            // Legacy quick check: model_index + VAEEncoder/VAEDecoder
            let hasModelIndex = fm.fileExists(atPath: url.appendingPathComponent("model_index.json").path)
            let hasVAEEncoder = fm.fileExists(atPath: url.appendingPathComponent("VAEEncoder.mlmodelc").path)
            let hasVAEDecoder = fm.fileExists(atPath: url.appendingPathComponent("VAEDecoder.mlmodelc").path)
            return hasModelIndex && hasVAEEncoder && hasVAEDecoder
        }
        
        // Candidate roots: folder, common Resources spellings, and one-level subfolders (+ their Resources)
        let resourceNames = ["Resources", "resources", "Resource", "resource", "Recources", "recources", "Recource", "recource"]
        var candidates: [URL] = [folder]
        for rn in resourceNames {
            let r = folder.appendingPathComponent(rn, isDirectory: true)
            if fm.fileExists(atPath: r.path) { candidates.append(r) }
        }
        
        if let children = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for child in children {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue else { continue }
                candidates.append(child)
                for rn in resourceNames {
                    let r = child.appendingPathComponent(rn, isDirectory: true)
                    if fm.fileExists(atPath: r.path) { candidates.append(r) }
                }
            }
        }
        
        // Prefer MLX roots first
        if let mlx = candidates.first(where: isValidMLXRoot) { return mlx }

        // CoreML roots: prefer the folder that actually contains merges/vocab at that level,
        // since Stable Diffusion CoreML expects those files next to the mlmodelc components.
        func coreMLScore(_ url: URL) -> Int {
            var score = 0
            if fm.fileExists(atPath: url.appendingPathComponent("merges.txt").path) { score += 50 }
            if fm.fileExists(atPath: url.appendingPathComponent("vocab.json").path) { score += 50 }
            if containsCompiledModelComponentShallow(at: url, nameContains: "TextEncoder") { score += 10 }
            if containsCompiledModelComponentShallow(at: url, nameContains: "Unet") { score += 10 }
            if containsCompiledModelComponentShallow(at: url, nameContains: "VAE") { score += 10 }
            // Don't pick "safety only" folders
            if containsCompiledModelComponentShallow(at: url, nameContains: "Safety") { score -= 5 }
            return score
        }

        let coremlCandidates = candidates.filter { isValidCoreMLRoot($0) }
        if let best = coremlCandidates.max(by: { coreMLScore($0) < coreMLScore($1) }),
           coreMLScore(best) > 0 {
            return best
        }
        
        return folder
    }

    // Helper: Heuristic for SD3 resources folder
     static func isSD3ResourcesFolder(_ baseURL: URL) -> Bool {
        // Heuristic: SD3 exports include a compiled model named "MultiModalDiffusionTransformer*.mlmodelc"
        return containsCompiledModelComponent(at: baseURL, nameContains: "MultiModalDiffusionTransformer")
    }

    // Public entry point: builds and returns a loaded StableDiffusionPipeline
    func loadPipeline(
        selectedModelOption: String,
        computeUnits: MLComputeUnits,
        allowNSFW: Bool,
        reducedMemory: Bool,
        quantization: String = "4bit"
    ) throws -> any StableDiffusionPipelineProtocol {
        // Always unload any existing pipeline before loading a new one (model/backend switch safety)
        if Thread.isMainThread {
            ModelLoader.unloadCurrentPipeline()
        } else {
            DispatchQueue.main.sync {
                ModelLoader.unloadCurrentPipeline()
            }
        }
        // MLX model branch: detect by suffix or content
        let isMLXSuffix = selectedModelOption.contains("(MLX)")
        var isMLXContent = false
        
        // Resolve URL first to check content
        let resolvedURL = ModelLoader.currentModelsURL(selectedModelOption: selectedModelOption)
        
        print("[ModelLoader] Resolved URL for '\(selectedModelOption)': \(resolvedURL?.path ?? "nil")")
        
        if let modelsURL = resolvedURL {
            // Check multiple possible MLX indicators
            let unetConfig = modelsURL.appendingPathComponent("unet").appendingPathComponent("config.json")
            let unetWeights = modelsURL.appendingPathComponent("unet").appendingPathComponent("diffusion_pytorch_model.safetensors")
            let textEncoderConfig = modelsURL.appendingPathComponent("text_encoder").appendingPathComponent("config.json")
            
            let hasUnetConfig = FileManager.default.fileExists(atPath: unetConfig.path)
            let hasUnetWeights = FileManager.default.fileExists(atPath: unetWeights.path)
            let hasTextEncoder = FileManager.default.fileExists(atPath: textEncoderConfig.path)
            
            print("[ModelLoader] MLX checks - unet/config: \(hasUnetConfig), unet/weights: \(hasUnetWeights), text_encoder/config: \(hasTextEncoder)")
            
            // MLX models have unet/config.json structure (diffusers format)
            if hasUnetConfig || (hasUnetWeights && hasTextEncoder) {
                isMLXContent = true
                print("[ModelLoader] Detected MLX model by content")
            }
        }
        
        if isMLXSuffix || isMLXContent {
            guard let modelsURL = resolvedURL else {
                let errorMsg = "Model folder not found for: \(selectedModelOption). Please check that the model is in the Models directory."
                print("[ModelLoader] ERROR: \(errorMsg)")
                throw ModelLoaderError.modelFolderNotFound
            }
            print("[ModelLoader] Loading MLX pipeline for: \(selectedModelOption) at \(modelsURL.path)")
            NotificationCenter.default.post(name: .init("Fluxnet.ModelBackendChanged"), object: "MLX")
            
            do {
            let mlxPipeline = StableDiffusionMLXPipeline(
                modelDirectory: modelsURL,
                allowNSFW: allowNSFW,
                reducedMemory: reducedMemory,
                quantization: quantization
            )
            ModelLoader.currentPipeline = mlxPipeline
                print("[ModelLoader] Calling mlxPipeline.loadResources()...")
            try mlxPipeline.loadResources()
                print("[ModelLoader] MLX pipeline loaded successfully")
            return mlxPipeline
            } catch {
                print("[ModelLoader] ERROR loading MLX pipeline: \(error)")
                ModelLoader.currentPipeline = nil
                throw error
            }
        }

        guard let modelsURL = ModelLoader.currentModelsURL(selectedModelOption: selectedModelOption) else {
            let errorMsg = "Model folder not found for: \(selectedModelOption). Please check that the model is in the Models directory."
            print("[ModelLoader] ERROR: \(errorMsg)")
            print("[ModelLoader] Attempted to resolve: \(selectedModelOption)")
            if let modelsDir = try? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Models") {
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsDir.path) {
                    print("[ModelLoader] Available models in directory: \(contents)")
                }
            }
            throw ModelLoaderError.modelFolderNotFound
        }
        
        print("[ModelLoader] Loading CoreML pipeline for: \(selectedModelOption) at \(modelsURL.path)")

        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = computeUnits
        if #available(iOS 16.0, macOS 13.0, *) {
            mlConfig.allowLowPrecisionAccumulationOnGPU = true
        }
        #if canImport(Metal)
        if let device = ModelLoader.preferredMetal4Device() {
            mlConfig.preferredMetalDevice = device
        }
        #endif

        // Build the correct pipeline variant inside an autoreleasepool to limit transient memory.
        let builtPipeline: any StableDiffusionPipelineProtocol
        do {
            builtPipeline = try autoreleasepool { () -> any StableDiffusionPipelineProtocol in
                // --- SD3+ heuristic: check for MultiModalDiffusionTransformer.mlmodelc ---
                let mmPath = modelsURL.appendingPathComponent("text_encoder_2/model/MultiModalDiffusionTransformer.mlmodelc")
                if FileManager.default.fileExists(atPath: mmPath.path) {
                    print("[ModelLoader] Loading SD3+ pipeline")
                    return try StableDiffusion3Pipeline(
                        resourcesAt: modelsURL,
                        configuration: mlConfig,
                        reduceMemory: reducedMemory
                    )
                } else if ModelLoader.isSD3ResourcesFolder(modelsURL) {
                    return try StableDiffusion3Pipeline(
                        resourcesAt: modelsURL,
                        configuration: mlConfig,
                        reduceMemory: reducedMemory
                    )
                } else if FileManager.default.fileExists(atPath: modelsURL.appendingPathComponent("TextEncoder2.mlmodelc").path) {
                    // If TextEncoder2 exists in the folder, treat as SDXL
                    return try StableDiffusionXLPipeline(
                        resourcesAt: modelsURL,
                        configuration: mlConfig,
                        reduceMemory: reducedMemory
                    )
                } else {
                    // Default: SD 1.x / 2.1 pipeline
                    return try StableDiffusionPipeline(
                        resourcesAt: modelsURL,
                        controlNet: [],
                        configuration: mlConfig,
                        disableSafety: allowNSFW,
                        reduceMemory: reducedMemory
                    )
                }
            }
        } catch {
            throw error
        }

        do {
            print("[ModelLoader] Built CoreML pipeline, loading resources...")
            NotificationCenter.default.post(name: .init("Fluxnet.ModelBackendChanged"), object: "CoreML")
            ModelLoader.currentPipeline = builtPipeline
            try builtPipeline.loadResources()
            print("[ModelLoader] CoreML pipeline loaded successfully")
        } catch {
            // On failure, drop the reference so unload calls don't hit a half-initialized object.
            print("[ModelLoader] ERROR loading CoreML pipeline resources: \(error)")
            ModelLoader.currentPipeline = nil
            throw error
        }

        return builtPipeline
    }


    // Resolve current model resources folder from selection stored in app sandbox
    static func currentModelsURL(selectedModelOption: String) -> URL? {
        guard !selectedModelOption.isEmpty else { return nil }
        return modelResourcesURLFromSelection(selectedModelOption: selectedModelOption)
    }

    // Looks up a valid model folder or .mlmodelc inside the app sandbox Models directory
    static func modelResourcesURLFromSelection(selectedModelOption: String) -> URL? {
        print("[ModelLoader] Resolving URL for model: \(selectedModelOption)")
        let fm = FileManager.default
        let modelsDir = getModelsDirectory()
        
        // 1. Try exact match first (in case folder has (MLX) in name)
        let exactPath = modelsDir.appendingPathComponent(selectedModelOption, isDirectory: true)
        if fm.fileExists(atPath: exactPath.path) {
             print("[ModelLoader] Found exact match: \(exactPath.path)")
             return resolveModelRoot(in: exactPath)
        }

        // 2. Fallback: Strip suffixes if exact match fails (legacy behavior)
        let rawName = selectedModelOption
            .replacingOccurrences(of: " (Core ML)", with: "")
            .replacingOccurrences(of: " (SD3+)", with: "")
            .replacingOccurrences(of: " (SD-SDXL)", with: "")
            .replacingOccurrences(of: " (MLX)", with: "")
        
        let chosen = modelsDir.appendingPathComponent(rawName, isDirectory: true)
        print("[ModelLoader] Checking path (stripped): \(chosen.path)")
        
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: chosen.path, isDirectory: &isDir), isDir.boolValue {
            // Resolve nested layouts (e.g. model stored under Resources/ or one-level subfolders)
            let resolved = resolveModelRoot(in: chosen)
            if resolved != chosen {
                print("[ModelLoader] Resolved nested model root: \(resolved.path)")
            }
            
            // Check for CoreML / Diffusers standard files
            let hasModelIndex = fm.fileExists(atPath: resolved.appendingPathComponent("model_index.json").path)
            let hasUnetConfig = fm.fileExists(atPath: resolved.appendingPathComponent("unet").appendingPathComponent("config.json").path)
            let hasTextEncoderConfig = fm.fileExists(atPath: resolved.appendingPathComponent("text_encoder").appendingPathComponent("config.json").path)
            let hasTextEncoder2Config = fm.fileExists(atPath: resolved.appendingPathComponent("text_encoder_2").appendingPathComponent("config.json").path)
            
            // CoreML specific checks
            let vaeEncoderPath = resolved.appendingPathComponent("VAEEncoder.mlmodelc")
            let vaeDecoderPath = resolved.appendingPathComponent("VAEDecoder.mlmodelc")
            let hasVAEEncoder = fm.fileExists(atPath: vaeEncoderPath.path)
            let hasVAEDecoder = fm.fileExists(atPath: vaeDecoderPath.path)
            let hasVAE = hasVAEEncoder && hasVAEDecoder
            
            print("[ModelLoader] Files found - model_index: \(hasModelIndex), unet/config: \(hasUnetConfig), text_encoder/config: \(hasTextEncoderConfig), VAE: \(hasVAE)")

            // 1. Valid CoreML Model (needs model_index + VAE binaries)
            if hasModelIndex && hasVAE {
                print("[ModelLoader] Identified as valid CoreML model.")
                return resolved
            }

            // 2. Valid MLX / Diffusers Model
            // MLX needs unet/config.json AND (text_encoder/config.json OR text_encoder_2/config.json)
            // It does NOT strictly require model_index.json (though usually present)
            if hasUnetConfig && (hasTextEncoderConfig || hasTextEncoder2Config) {
                print("[ModelLoader] Identified as valid MLX/Diffusers model.")
                return resolved
            }
            
            // 3. Compiled CoreML Model (.mlmodelc folder)
            if resolved.pathExtension.lowercased() == "mlmodelc" {
                print("[ModelLoader] Identified as .mlmodelc folder.")
                return resolved
            }
            
            // 4. Subfolder check for .mlmodelc
            let deep = (try? fm.subpathsOfDirectory(atPath: resolved.path)) ?? []
            if deep.contains(where: { $0.hasSuffix(".mlmodelc") }) {
                print("[ModelLoader] Found .mlmodelc in subpaths.")
                return resolved
            }
            
            print("[ModelLoader] Validation failed. Missing required files.")
        } else {
            print("[ModelLoader] Path does not exist or is not a directory: \(chosen.path)")
            // Debug: List contents of Models directory to see what's actually there
            if let contents = try? fm.contentsOfDirectory(atPath: modelsDir.path) {
                print("[ModelLoader] Contents of Models directory: \(contents)")
            } else {
                print("[ModelLoader] Could not list Models directory.")
            }
        }
        return nil
    }

    static func isSDXLResourcesFolder(_ baseURL: URL) -> Bool {
        let fm = FileManager.default
        
        // PRIMARY CHECK: TextEncoder2 (definitive for SDXL)
        // SDXL has dual text encoders (CLIP-L + OpenCLIP-G), SD 1.x/2.x only have one
        if fm.fileExists(atPath: baseURL.appendingPathComponent("TextEncoder2.mlmodelc").path) {
            return true
        }
        
        // SECONDARY CHECK: Look deeper for TextEncoder2 in subdirectories
        // Some model packages nest files one level deep
        guard let enumerator = fm.enumerator(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return false
        }
        
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if url.pathExtension.lowercased() == "mlmodelc" {
                // TextEncoder2 is the definitive SDXL marker
                if name == "textencoder2.mlmodelc" {
                    return true
                }
                
                // NOTE: UnetChunk*.mlmodelc is NOT checked here because
                // Legacy SD 1.x/2.x models can also have split chunks on iOS
                // Only TextEncoder2 uniquely identifies SDXL
            }
        }
        return false
    }


    static func displaySuffixForModel(at baseURL: URL) -> String {
        if isSD3ResourcesFolder(baseURL) {
            return " (SD3+)"
        }
        if isSDXLResourcesFolder(baseURL) {
            return " (SD-SDXL)"
        }
        return " (Core ML)"
    }

    // Copy an externally-selected model folder into app sandbox if missing
    static func copySelectedModelIntoAppIfNeeded(from externalURL: URL) {
        let fm = FileManager.default
        let dst = getModelsDirectory().appendingPathComponent(externalURL.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: dst.path) { return }
        let stop = externalURL.startAccessingSecurityScopedResource()
        defer { if stop { externalURL.stopAccessingSecurityScopedResource() } }
        do {
            try fm.copyItem(at: externalURL, to: dst)
        } catch {
            // Surface errors to caller via thrown error in loadPipeline; here we silently ignore
        }
    }

    #if canImport(Metal)
    static func preferredMetal4Device() -> MTLDevice? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        if #available(iOS 26.0, *) {
            _ = device.supportsFamily(.metal3)
        } else {
            _ = device.supportsFamily(.metal3)
        }
        return device
    }
    #endif

    static func preallocateModelMemory(pipeline p: StableDiffusionPipeline) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var cfg = StableDiffusionPipeline.Configuration(prompt: "warmup")
                cfg.imageCount = 1
                cfg.stepCount = 2
                cfg.guidanceScale = 1
                cfg.seed = 0
                cfg.useDenoisedIntermediates = true
                _ = try? p.generateImages(configuration: cfg) { _ in false }
            }
        }
    }

    static func preallocateModelMemoryXL(pipeline p: StableDiffusionXLPipeline) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var cfg = StableDiffusionXLPipeline.Configuration(prompt: "warmup")
                cfg.imageCount = 1
                cfg.stepCount = 2
                cfg.guidanceScale = 1
                cfg.seed = 0
                cfg.useDenoisedIntermediates = true
                _ = try? p.generateImages(configuration: cfg) { _ in false }
            }
        }
    }

    static func preallocateModelMemorySD3(pipeline p: StableDiffusion3Pipeline) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                var cfg = StableDiffusion3Pipeline.Configuration(prompt: "warmup")
                cfg.imageCount = 1
                cfg.stepCount = 2
                cfg.guidanceScale = 1
                cfg.seed = 0
                cfg.useDenoisedIntermediates = true
                _ = try? p.generateImages(configuration: cfg) { _ in false }
            }
        }
    }
}




