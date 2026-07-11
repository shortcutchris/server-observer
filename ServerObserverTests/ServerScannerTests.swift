import XCTest
@testable import ServerObserver

final class ServerScannerTests: XCTestCase {
    func testParsesIPv4AndIPv6Listeners() {
        let input = """
        p123
        cnode
        u501
        f12
        n*:3000
        TST=LISTEN
        f13
        n[::1]:3001
        TST=LISTEN
        p456
        cpostgres
        u501
        f14
        n127.0.0.1:5432
        TST=LISTEN
        """

        let endpoints = ServerScanner.parseLsof(input)

        XCTAssertEqual(endpoints.count, 3)
        XCTAssertTrue(endpoints.contains(ListeningEndpoint(pid: 123, processName: "node", ownerUID: 501, host: "*", port: 3000)))
        XCTAssertTrue(endpoints.contains(ListeningEndpoint(pid: 123, processName: "node", ownerUID: 501, host: "::1", port: 3001)))
        XCTAssertTrue(endpoints.contains(ListeningEndpoint(pid: 456, processName: "postgres", ownerUID: 501, host: "127.0.0.1", port: 5432)))
    }

    func testIgnoresMalformedEndpoint() {
        let input = """
        p123
        cnode
        u501
        nnot-an-endpoint
        """

        XCTAssertTrue(ServerScanner.parseLsof(input).isEmpty)
    }
}
