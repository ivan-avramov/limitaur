import Foundation
import Darwin

public enum StatisticsOutputFailure: Error, Sendable {
    case invalidPath, unavailable, tooLarge
}

/// Owns a newly created diagnostics file by descriptor. It never opens an
/// existing path for writing, including a symlink or a credential source.
public final class StatisticsOutput {
    private let descriptor: Int32

    public init(path: String, forbiddenPaths: [String]) throws {
        guard path.hasPrefix("/") else { throw StatisticsOutputFailure.invalidPath }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL
        let candidatePaths = Set([candidate.path, candidate.resolvingSymlinksInPath().path])
        let blocked = Set(forbiddenPaths.flatMap { raw -> [String] in
            let url = URL(fileURLWithPath: raw).standardizedFileURL
            return [url.path, url.resolvingSymlinksInPath().path]
        })
        guard candidatePaths.isDisjoint(with: blocked) else { throw StatisticsOutputFailure.invalidPath }
        let opened = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard opened >= 0 else { throw StatisticsOutputFailure.unavailable }
        var info = stat()
        guard fstat(opened, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            close(opened)
            throw StatisticsOutputFailure.unavailable
        }
        descriptor = opened
    }

    deinit { close(descriptor) }

    public func write(_ counts: [String: [String: Int]]) throws {
        let data = try JSONSerialization.data(withJSONObject: counts, options: [.sortedKeys])
        guard data.count <= 1_048_576 else { throw StatisticsOutputFailure.tooLarge }
        guard lseek(descriptor, 0, SEEK_SET) == 0, ftruncate(descriptor, 0) == 0 else {
            throw StatisticsOutputFailure.unavailable
        }
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StatisticsOutputFailure.unavailable }
                offset += count
            }
        }
    }
}
