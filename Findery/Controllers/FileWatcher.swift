import Foundation
import CoreServices

final class FileWatcher {

    private var stream: FSEventStreamRef?
    private(set) var watchedURL: URL?
    private(set) var isPaused = false

    var onChange: (() -> Void)?

    func pause() {
        isPaused = true
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        // Deliver one synthetic change so any edits made while paused are picked up
        DispatchQueue.main.async { [weak self] in
            self?.onChange?()
        }
    }

    func watch(directory url: URL) {
        stop()
        watchedURL = url

        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, _, _ in
            guard let info = clientInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async {
                guard !watcher.isPaused else { return }
                watcher.onChange?()
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let paths = [url.path] as CFArray
        stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        watchedURL = nil
    }

    deinit {
        stop()
    }
}
