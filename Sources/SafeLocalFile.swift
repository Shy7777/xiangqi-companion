import Foundation
import Darwin

/// Read user-selected files with a hard allocation limit. Checking the opened
/// descriptor avoids following a final symlink or blocking on a FIFO/device.
enum SafeLocalFile {
    enum Failure: LocalizedError {
        case invalidLimit, notRegular, tooLarge
        var errorDescription: String? {
            switch self {
            case .invalidLimit: return "文件读取上限无效。"
            case .notRegular: return "请选择普通本地文件，不支持目录、符号链接或设备文件。"
            case .tooLarge: return "文件超过允许的大小，尚未读取或导入。"
            }
        }
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0, maximumBytes < Int.max else { throw Failure.invalidLimit }
        guard url.isFileURL else { throw Failure.notRegular }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard metadata.st_mode & S_IFMT == S_IFREG else { throw Failure.notRegular }
        guard metadata.st_size >= 0, metadata.st_size <= maximumBytes else { throw Failure.tooLarge }
        let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        // The file could grow after fstat; a bounded read still prevents an
        // attacker or a concurrent writer from bypassing the memory limit.
        guard bytes.count <= maximumBytes else { throw Failure.tooLarge }
        return bytes
    }
}
