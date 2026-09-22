import Foundation

public struct CommitSummary: Codable, Sendable, Identifiable {
    public struct Detail: Codable, Sendable {
        public struct Author: Codable, Sendable { public let name: String?; public let date: String? }
        public let message: String
        public let author: Author?
        public let committer: Author?
    }
    public let sha: String
    public let commit: Detail
    public var id: String { sha }
    public var title: String { commit.message.components(separatedBy: .newlines).first ?? sha }
    public var date: Date? {
        guard let value = commit.committer?.date ?? commit.author?.date else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds); return formatter.date(from: value)
    }
}
public struct ChangedFile: Codable, Sendable, Identifiable {
    public let filename: String
    public let status: String
    public let previous_filename: String?
    public var id: String { filename }
}
public struct CommitFiles: Codable, Sendable {
    public let files: [ChangedFile]
    public let truncated: Bool
    public var limitsMayApply: Bool? = nil
}
public struct RecentSnapshot: Codable, Sendable {
    public let commits: [CommitSummary]
    public let etag: String?
    public init(commits: [CommitSummary], etag: String?) { self.commits = commits; self.etag = etag }
}
