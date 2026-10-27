import Foundation
import NXLibraryCore

public enum UpstreamCheckState: Equatable {
    case idle
    case checking
    case loaded(UpstreamStatus)
    case failed(String)
}
