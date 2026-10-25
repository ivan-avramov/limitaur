import Foundation
import Darwin

public enum InstanceLock: Equatable, Sendable { case acquired(Int32), held, unavailable }

/// One menu-bar instance per user: an advisory lock on `directory/instance.lock`, released by the kernel at exit.
public func takeInstanceLock(directory: String) -> InstanceLock {
    var st = stat()
    if lstat(directory, &st) != 0 { _ = mkdir(directory, 0o700) }
    guard lstat(directory, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { return .unavailable }
    if st.st_mode & 0o777 != 0o700, chmod(directory, 0o700) != 0 { return .unavailable }
    let fd = open(directory + "/instance.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    if fd < 0 { return .unavailable }
    if flock(fd, LOCK_EX | LOCK_NB) == 0 { return .acquired(fd) }
    let busy = errno == EWOULDBLOCK
    close(fd)
    return busy ? .held : .unavailable
}
