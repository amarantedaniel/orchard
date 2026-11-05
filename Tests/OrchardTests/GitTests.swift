import Foundation
import Testing
@testable import Orchard

struct GitTests {
    @Test func readsBranchesAndHeadsFromRemote() async throws {
        let origin = try TemporaryDirectory()
        try await git(["init", "--bare", "--initial-branch=main"], in: origin.url)

        let clone = try TemporaryDirectory()
        try await git(["clone", origin.url.path, "."], in: clone.url)
        let main = try await commit("First", in: clone.url)
        try await git(["push", "origin", "HEAD:main"], in: clone.url)
        let feature = try await commit("Second", in: clone.url)
        try await git(["push", "origin", "HEAD:refs/heads/feature/x"], in: clone.url)

        #expect(try await Git.remote(in: clone.url) == "origin")
        #expect(try await Git.branches(in: clone.url) == ["feature/x", "main"])
        #expect(try await Git.headCommit(of: "main", in: clone.url) == main)
        #expect(try await Git.headCommit(of: "feature/x", in: clone.url) == feature)
        #expect(await Git.subject(of: feature, in: clone.url) == "Second")
        await #expect(throws: GitError.self) {
            try await Git.headCommit(of: "missing", in: clone.url)
        }
    }

    @Test func fallsBackToLocalBranchesWithoutRemote() async throws {
        let repo = try TemporaryDirectory()
        try await git(["init", "--initial-branch=main"], in: repo.url)
        let head = try await commit("Only", in: repo.url)
        try await git(["branch", "topic"], in: repo.url)

        #expect(try await Git.remote(in: repo.url) == nil)
        #expect(await Git.isRepository(repo.url))
        #expect(try await Git.branches(in: repo.url) == ["main", "topic"])
        #expect(try await Git.headCommit(of: "topic", in: repo.url) == head)
    }

    @Test func remoteThrowsInsteadOfClaimingLocalOnly() async throws {
        let notARepo = try TemporaryDirectory()
        await #expect(throws: ShellError.self) {
            try await Git.remote(in: notARepo.url)
        }
    }

    @Test func acceptsOnlyFullCommitHashes() throws {
        let sha1 = String(repeating: "a1", count: 20)
        let sha256 = String(repeating: "b2", count: 32)
        #expect(try Git.commitSHA(sha1 + "\n") == sha1)
        #expect(try Git.commitSHA(sha256) == sha256)
        for output in ["", "\n", "8ab7f1a2", "fatal: not a git repository", String(repeating: "g", count: 40)] {
            #expect(throws: GitError.self) { try Git.commitSHA(output) }
        }
    }

    @Test func preparesAndReusesWorktree() async throws {
        let repo = try TemporaryDirectory()
        try await git(["init", "--initial-branch=main"], in: repo.url)
        let first = try await commit("First", in: repo.url)
        let second = try await commit("Second", in: repo.url)

        let scratch = try TemporaryDirectory()
        let worktree = scratch.url.appendingPathComponent("pipeline/checkout")
        try await Git.prepareWorktree(at: worktree, repo: repo.url, branch: "main", commit: first) { _ in }
        #expect(try await git(["rev-parse", "HEAD"], in: worktree) == first)

        try "junk".write(to: worktree.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        try await Git.prepareWorktree(at: worktree, repo: repo.url, branch: "main", commit: second) { _ in }
        #expect(try await git(["rev-parse", "HEAD"], in: worktree) == second)
        #expect(!FileManager.default.fileExists(atPath: worktree.appendingPathComponent("untracked.txt").path))

        await Git.removeWorktree(at: worktree, repo: repo.url)
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
    }

    @Test func listsCommitsSinceLastDeploy() async throws {
        let repo = try TemporaryDirectory()
        try await git(["init", "--initial-branch=main"], in: repo.url)
        let deployed = try await commit("Deployed", in: repo.url)
        let second = try await commit("Second", in: repo.url)
        let third = try await commit("Third: with | separators", in: repo.url)

        let changes = try #require(await Git.changes(from: deployed, to: third, in: repo.url))
        #expect(changes.map(\.sha) == [third, second])
        #expect(changes.map(\.subject) == ["Third: with | separators", "Second"])
        #expect(changes.allSatisfy { $0.author == "Orchard Tests" })

        #expect(await Git.changes(from: third, to: third, in: repo.url) == [])
        #expect(await Git.changes(from: String(repeating: "0", count: 40), to: third, in: repo.url) == nil)
        // Rollback, or a force-push that dropped commits: the list couldn't show what was removed.
        #expect(await Git.changes(from: third, to: second, in: repo.url) == nil)
        try await git(["checkout", "-q", "-b", "rewritten", deployed], in: repo.url)
        let rewritten = try await commit("Rewritten", in: repo.url)
        #expect(await Git.changes(from: third, to: rewritten, in: repo.url) == nil)
    }

    @Test func capsChangesOneAboveTheLimit() async throws {
        let repo = try TemporaryDirectory()
        try await git(["init", "--initial-branch=main"], in: repo.url)
        let base = try await commit("Base", in: repo.url)
        var head = base
        for i in 0..<Git.changesLimit { head = try await commit("Change \(i)", in: repo.url) }
        #expect(await Git.changes(from: base, to: head, in: repo.url)?.count == Git.changesLimit)
        for i in 0..<2 { head = try await commit("More \(i)", in: repo.url) }
        #expect(await Git.changes(from: base, to: head, in: repo.url)?.count == Git.changesLimit + 1)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) async throws -> String {
        let identity = ["-c", "user.name=Orchard Tests", "-c", "user.email=tests@example.com",
                        "-c", "commit.gpgsign=false"]
        return try await Shell.git(identity + arguments, in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ message: String, in repo: URL) async throws -> String {
        try await git(["commit", "--allow-empty", "-m", message], in: repo)
        return try await git(["rev-parse", "HEAD"], in: repo)
    }
}
