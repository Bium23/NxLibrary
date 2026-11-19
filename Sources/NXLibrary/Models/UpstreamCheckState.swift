import Foundation
import NXLibraryCore

enum UpstreamCheckState: Equatable {
    case idle
    case checking
    case loaded(UpstreamStatus)
    case failed(String)
}
