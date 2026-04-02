import Foundation

final class FileWatcher {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private(set) var watchedURL: URL?

    var onChange: (() -> Void)?

    func watch(directory url: URL) {
        stop()
        watchedURL = url

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange?()
        }

        source?.setCancelHandler { [weak self] in
            guard let fd = self?.fileDescriptor, fd >= 0 else { return }
            close(fd)
            self?.fileDescriptor = -1
        }

        source?.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        watchedURL = nil
    }

    deinit {
        stop()
    }
}
