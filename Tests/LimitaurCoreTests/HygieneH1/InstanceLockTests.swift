import Darwin
import Foundation
import Testing
@testable import LimitaurCore

private final class H1Descriptors {
    var held: [Int32] = []
    func take(_ path: String) -> String {
        switch takeInstanceLock(directory: path) {
        case .acquired(let fd): held.append(fd); return "acquired"
        case .held: return "held"
        case .unavailable: return "unavailable"
        }
    }
    func release() { for fd in held { _ = Darwin.close(fd) }; held = [] }
    deinit { release() }
}
@Suite struct HygieneH1InstanceLockTests {
    // AC3: new behaviour, free/held/reacquired, secure creation and correction, no unlink/replacement.
    @Test(arguments: [false, true]) func acquisitionAndPermissions(_ existing0755: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hygiene-h1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("guard").path, handles = H1Descriptors()
        defer { handles.release() }
        if existing0755 { try #require(mkdir(path, 0o755) == 0); try #require(chmod(path, 0o755) == 0) }
        try #require(handles.take(path) == "acquired"); let fd = try #require(handles.held.first)
        var directory = stat(), file = stat(); try #require(lstat(path, &directory) == 0); try #require(fstat(fd, &file) == 0)
        #expect(directory.st_mode & 0o777 == 0o700); #expect(file.st_mode & 0o777 == 0o600); #expect(fcntl(fd, F_GETFD) & FD_CLOEXEC != 0)
        #expect(handles.take(path) == "held"); handles.release()
        // A concurrently spawned child may briefly retain a duplicate of the closed descriptor.
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        var reacquired = handles.take(path)
        while reacquired == "held", ContinuousClock.now < deadline {
            Thread.sleep(forTimeInterval: 0.001); reacquired = handles.take(path)
        }
        try #require(reacquired == "acquired")
        var reopened = stat(); try #require(fstat(try #require(handles.held.first), &reopened) == 0); #expect(reopened.st_ino == file.st_ino)
    }
    // AC3: new behaviour, only disposable temporary paths; rejected symlinks/regular paths survive unchanged.
    @Test(arguments: ["symlinkFile", "symlinkDirectory", "regularPath"]) func unsafePathsUnavailable(_ kind: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hygiene-h1-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("guard").path, target = root.appendingPathComponent("target").path, handles = H1Descriptors()
        defer { handles.release() }
        if kind == "symlinkDirectory" { try #require(mkdir(target, 0o755) == 0); try #require(symlink(target, path) == 0) }
        else if kind == "regularPath" { try Data("sentinel".utf8).write(to: URL(fileURLWithPath: path)) }
        else { try #require(mkdir(path, 0o700) == 0); try Data("sentinel".utf8).write(to: URL(fileURLWithPath: target)); try #require(symlink(target, path + "/instance.lock") == 0) }
        var before = stat(); let inspected = kind == "symlinkFile" ? path + "/instance.lock" : path
        try #require(lstat(inspected, &before) == 0); #expect(handles.take(path) == "unavailable")
        var after = stat(); try #require(lstat(inspected, &after) == 0); #expect(after.st_ino == before.st_ino && after.st_mode == before.st_mode)
        if kind == "symlinkDirectory" { #expect(!FileManager.default.fileExists(atPath: target + "/instance.lock")) }
        else { #expect(try Data(contentsOf: URL(fileURLWithPath: kind == "regularPath" ? path : target)) == Data("sentinel".utf8)) }
    }
}
