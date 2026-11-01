import Foundation
import NXLibraryCore

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: install_built_app <staged.app> <destination.app>\n".utf8))
    exit(2)
}
do {
    try BuildOutputInstaller.install(
        tempApp: URL(fileURLWithPath: CommandLine.arguments[1]),
        finalApp: URL(fileURLWithPath: CommandLine.arguments[2]))
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
