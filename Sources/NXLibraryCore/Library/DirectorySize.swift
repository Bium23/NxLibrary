import Foundation

/// The bytes of a folder's regular files, hidden files and folders skipped. Walks with fts, one lstat per entry
/// as `du` does: a large game app on a USB drive has hundreds of thousands of files, and asking each URL for its
/// resource values took minutes there (issue #2).
public enum DirectorySize {
    public static func bytes(at url: URL) -> Int64 {
        var total: Int64 = 0
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let root = strdup(path) else { return }
            defer { free(root) }
            var roots: [UnsafeMutablePointer<CChar>?] = [root, nil]
            guard let fts = fts_open(&roots, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
            defer { fts_close(fts) }
            while let entry = fts_read(fts) {
                let info = Int32(entry.pointee.fts_info)
                if entry.pointee.fts_level > 0, entry.pointee.fts_name == CChar(UInt8(ascii: ".")) {
                    if info == FTS_D { fts_set(fts, entry, FTS_SKIP) }
                    continue
                }
                if info == FTS_F, let stat = entry.pointee.fts_statp {
                    total += Int64(stat.pointee.st_size)
                }
            }
        }
        return total
    }
}
