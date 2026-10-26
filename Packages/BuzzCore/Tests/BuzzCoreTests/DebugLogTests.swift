import Foundation
import Testing
@testable import BuzzCore

@Suite("Debug log")
struct DebugLogTests {
    func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("debuglog-\(UUID().uuidString)")
    }

    @Test func disabledWritesNothingAndBuildsNoMessages() {
        let log = DebugLog()
        log.configure(directory: tempDirectory(), enabled: false)
        var built = false
        log.log(.session, { built = true; return "x" }())
        #expect(!built, "messages are only built when logging is on")
        #expect(log.contents().isEmpty)
        #expect(log.sizeInBytes == 0)
    }

    @Test func linesCarryWallClockElapsedAndCategory() throws {
        let log = DebugLog()
        log.configure(directory: tempDirectory(), enabled: true)
        log.log(.transport, "conn p#1 state ready")
        log.log(.session, "host arm #1")
        let lines = log.contents().split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        let first = try #require(lines.first)
        // 2026-10-25T17:42:03.123-04:00 +0.001s [transport] conn p#1 state ready
        #expect(first.range(of: #"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-Z]"#, options: .regularExpression) != nil)
        #expect(first.range(of: #" \+\d+\.\d{3}s \[transport\] conn p#1 state ready$"#, options: .regularExpression) != nil)
        #expect(lines[1].hasSuffix("[session] host arm #1"))
    }

    @Test func turningOffStopsWritingAndOnResumes() {
        let log = DebugLog()
        log.configure(directory: tempDirectory(), enabled: true)
        log.log(.app, "one")
        log.setEnabled(false)
        log.log(.app, "two")
        log.setEnabled(true)
        log.log(.app, "three")
        let text = log.contents()
        #expect(text.contains("one") && !text.contains("two") && text.contains("three"))
    }

    @Test func rotatesAndKeepsThePreviousFile() {
        let log = DebugLog(maxFileBytes: 400)
        let directory = tempDirectory()
        log.configure(directory: directory, enabled: true)
        for i in 0..<20 { log.log(.app, "line \(i) " + String(repeating: "x", count: 40)) }
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("debug.log.1").path))
        let text = log.contents()
        #expect(text.contains("line 19"), "newest lines kept")
        #expect(log.sizeInBytes < 2 * 400 + 200, "at most two files' worth")
    }

    @Test func clearAndExport() throws {
        let log = DebugLog()
        log.configure(directory: tempDirectory(), enabled: true)
        log.log(.session, "player buzz pressed")
        let exported = try #require(log.exportFile(label: "Aadi-iPhone13,2"))
        #expect(exported.lastPathComponent.hasPrefix("buzzlight-Aadi-iPhone132-"))
        #expect(try String(contentsOf: exported, encoding: .utf8).contains("player buzz pressed"))
        log.clear()
        #expect(log.contents().isEmpty)
        #expect(log.exportFile(label: "x") == nil, "nothing to export")
    }

    @Test func messageSummariesAreShort() {
        let ava = PlayerID(rawValue: "ABCDEFGH-1234")
        #expect(GameMessage.hello(playerID: ava, name: "Ava").summary == "hello(Ava, id ABCDEFGH)")
        #expect(GameMessage.buzz(round: RoundID(3)).summary == "buzz(#3)")
        #expect(GameMessage.result(round: RoundID(3), ranking: [BuzzEntry(playerID: ava, position: 1, deltaMilliseconds: 0)]).summary
                == "result(#3: ABCDEFGH+0ms)")
    }
}

/// The sessions' own trace through a real (loopback) game.
@MainActor
/// Every test that reconfigures `DebugLog.shared` lives here so they never run concurrently.
@Suite("Session tracing", .serialized)
struct SessionTracingTests {
    @Test func aRoundLeavesAReadableTrace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trace-\(UUID().uuidString)")
        DebugLog.shared.configure(directory: directory, enabled: true)
        defer { DebugLog.shared.setEnabled(false) }

        let network = LoopbackNetwork()
        let host = HostSession(hostID: PlayerID(rawValue: "host-1"), hostName: "Hana",
                               transport: await network.makeTransport(name: "Hana"), flushDelay: .zero)
        await host.start()
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat-1"), name: "Pat",
                                transport: await network.makeTransport(name: "Pat"))
        await pat.start()
        #expect(await eventually { !pat.hosts.isEmpty })
        await pat.join(try #require(pat.hosts.first))
        #expect(await eventually { pat.engine.status == .waiting })
        await host.arm()
        #expect(await eventually { pat.engine.status == .ready })
        pat.buzz()
        #expect(await eventually { host.engine.round.ranking.count == 1 })
        await host.end()
        #expect(await eventually { pat.phase == .ended(.hostEnded) })

        let trace = DebugLog.shared.contents()
        for expected in [
            "host start \"Hana's game\"",
            "player phase browsing → connecting",
            "host ← message hello(Pat, id pat-1)",
            "host arm #1",
            "player buzz pressed: status ready → buzzed",
            "player → buzz(#1)",
            "host buzz #1 from Pat",
            "host → result(#1: pat-1+0ms) → all",
            "player phase joined",
            "host end",
        ] {
            #expect(trace.contains(expected), "missing: \(expected)")
        }
    }

    @Test func roundTripTimesAreLogged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rtt-\(UUID().uuidString)")
        DebugLog.shared.configure(directory: directory, enabled: true)
        defer { DebugLog.shared.setEnabled(false) }

        let network = LoopbackNetwork()
        let host = HostSession(hostID: PlayerID(rawValue: "host"), hostName: "Hana",
                               transport: await network.makeTransport(name: "Hana"), flushDelay: .zero,
                               heartbeatInterval: .milliseconds(10))
        await host.start()
        let pat = PlayerSession(playerID: PlayerID(rawValue: "pat"), name: "Pat",
                                transport: await network.makeTransport(name: "Pat"))
        await pat.start()
        #expect(await eventually { !pat.hosts.isEmpty })
        await pat.join(try #require(pat.hosts.first))
        #expect(await eventually(timeout: .seconds(3)) { DebugLog.shared.contents().contains("host rtt Pat: min ") })
        #expect(!DebugLog.shared.contents().contains("ping("), "heartbeats themselves stay out of the log")
        await host.end()
    }
}
