import Foundation
import Combine

/// Real resumable downloader for Hugging Face files built on URLSession background tasks.
@MainActor
final class DownloadManager: NSObject, ObservableObject {

    static let shared = DownloadManager()

    @Published private(set) var downloads: [String: DownloadTaskInfo] = [:]
    /// Called when a file finished downloading so the library can register it.
    var onCompleted: ((DownloadTaskInfo, URL) -> Void)?

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "app.aiagenthub.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = UserDefaults.standard.object(forKey: "allowCellularDownloads") as? Bool ?? false
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    var active: [DownloadTaskInfo] {
        downloads.values
            .filter { $0.state == .downloading || $0.state == .queued || $0.state == .paused }
            .sorted { $0.startedAt < $1.startedAt }
    }

    func warmUp() { _ = session }

    // MARK: - Control

    func start(repoId: String, revision: String, file: String, expectedSize: Int64) {
        let info = DownloadTaskInfo(repoId: repoId, revision: revision, fileName: file,
                                    totalBytes: expectedSize, state: .downloading)
        guard tasks[info.id] == nil else { return }
        downloads[info.id] = info

        let url = HuggingFaceAPI.resolveURL(repoId: repoId, revision: revision, file: file)
        let request = HuggingFaceAPI.shared.authorizedRequest(url: url)
        let task = session.downloadTask(with: request)
        task.taskDescription = info.id
        tasks[info.id] = task
        task.resume()
    }

    func pause(_ id: String) {
        guard let task = tasks[id] else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.resumeData[id] = data }
                self.tasks[id] = nil
                self.downloads[id]?.state = .paused
            }
        })
    }

    func resume(_ id: String) {
        guard tasks[id] == nil, var info = downloads[id] else { return }
        let task: URLSessionDownloadTask
        if let data = resumeData[id] {
            task = session.downloadTask(withResumeData: data)
            resumeData[id] = nil
        } else {
            let url = HuggingFaceAPI.resolveURL(repoId: info.repoId, revision: info.revision, file: info.fileName)
            task = session.downloadTask(with: HuggingFaceAPI.shared.authorizedRequest(url: url))
        }
        task.taskDescription = id
        tasks[id] = task
        info.state = .downloading
        info.errorMessage = nil
        downloads[id] = info
        task.resume()
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        resumeData[id] = nil
        downloads[id]?.state = .cancelled
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            if self.downloads[id]?.state == .cancelled { self.downloads.removeValue(forKey: id) }
        }
    }

    func clearFinished() {
        downloads = downloads.filter { $0.value.state != .completed && $0.value.state != .cancelled }
    }

    fileprivate func update(_ id: String, _ mutate: (inout DownloadTaskInfo) -> Void) {
        guard var info = downloads[id] else { return }
        mutate(&info)
        downloads[id] = info
    }
}

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            self.update(id) { info in
                info.receivedBytes = totalBytesWritten
                if totalBytesExpectedToWrite > 0 { info.totalBytes = totalBytesExpectedToWrite }
                info.state = .downloading
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // Must move the file synchronously before this method returns.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.moveItem(at: location, to: tmp)
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200

        Task { @MainActor in
            guard var info = self.downloads[id] else { try? FileManager.default.removeItem(at: tmp); return }
            guard (200..<300).contains(statusCode) else {
                try? FileManager.default.removeItem(at: tmp)
                info.state = .failed
                info.errorMessage = statusCode == 401 || statusCode == 403
                    ? "Access denied (HTTP \(statusCode)). This repo may be gated — connect your Hugging Face account and accept the license."
                    : "Server returned HTTP \(statusCode)."
                self.downloads[id] = info
                self.tasks[id] = nil
                return
            }
            let dest = ModelStorage.location(repoId: info.repoId, revision: info.revision, file: info.fileName)
            do {
                try ModelStorage.ensureParent(dest)
                if ModelStorage.exists(dest) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.moveItem(at: tmp, to: dest)
                info.state = .completed
                info.receivedBytes = ModelStorage.size(of: dest)
                info.totalBytes = info.receivedBytes
                self.downloads[id] = info
                self.onCompleted?(info, dest)
            } catch {
                info.state = .failed
                info.errorMessage = error.localizedDescription
                self.downloads[id] = info
            }
            self.tasks[id] = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let nsError = error as NSError
        let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor in
            if let resume { self.resumeData[id] = resume }
            self.tasks[id] = nil
            guard let current = self.downloads[id], current.state != .completed else { return }
            if nsError.code == NSURLErrorCancelled {
                if resume != nil { self.update(id) { $0.state = .paused } }
                return
            }
            self.update(id) {
                $0.state = .failed
                $0.errorMessage = error.localizedDescription
            }
        }
    }
}
