import Foundation

/// The program packed from a NUP, its owning application and its independent DLC numbering base.
/// Persist it with the sources so a rebuild cannot silently follow a different default program.
public struct NUPProgramSelection: Codable, Equatable, Hashable {
    public let programID: UInt64
    public let applicationID: UInt64
    public let addOnContentBaseID: UInt64

    public init(programID: UInt64, applicationID: UInt64, addOnContentBaseID: UInt64) {
        self.programID = programID
        self.applicationID = applicationID
        self.addOnContentBaseID = addOnContentBaseID
    }

    public var index: Int { Int(programID & 0xFFF) }
    public var isValid: Bool { programID != 0 && applicationID != 0 && addOnContentBaseID != 0 }
}
