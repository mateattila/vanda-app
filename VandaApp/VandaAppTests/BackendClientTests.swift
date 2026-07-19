//
//  BackendClientTests.swift
//  VandaAppTests
//
//  A backend-kliens tesztjei URLProtocol-stubbal — élő backend nélkül.
//

import Foundation
import Testing
@testable import VandaApp

/// Minden kérést elkap, és a `handler`-rel válaszol. A statikus handler csak
/// azért biztonságos, mert a teszteket lentebb egyetlen `@Suite(.serialized)`
/// fogja össze — a Swift Testing alapból *párhuzamosan* futtatja a suite-okat
/// és az egy suite-on belüli teszteket is, úgyhogy enélkül két teszt egyszerre
/// írná/olvasná a `handler`/`lastRequest`/`lastBody` statikus mezőket.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lastRequest = request
        StubURLProtocol.lastBody = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private func makeClient(
    handler: @escaping (URLRequest) throws -> (Int, Data)
) -> BackendClient {
    StubURLProtocol.handler = handler
    StubURLProtocol.lastRequest = nil
    StubURLProtocol.lastBody = nil
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return BackendClient(
        baseURL: URL(string: "https://vanda.test")!,
        session: URLSession(configuration: config)
    )
}

private func json(_ raw: String) -> Data { Data(raw.utf8) }

/// Egyetlen `@Suite(.serialized)` fogja körbe a két alcsoportot. A
/// `StubURLProtocol` statikus állapotát minden teszt megosztva használja, így
/// a tesztek nem futhatnak párhuzamosan — sem egy alcsoporton belül, sem a
/// kettő között. (Ez utóbbi ellen két külön, egyenként `.serialized` struct
/// NEM védene: a Swift Testing a testvér-suite-okat egymással párhuzamosan is
/// elindítja. A `.serialized` trait viszont öröklődik a beágyazott
/// suite-okra, ezért a közös szülőn elég egyszer kiírni.)
@Suite(.serialized)
struct BackendClientTests {

    struct StatusMapping {

        @Test func unknownCodeMapsTo404() async {
            let client = makeClient { _ in (404, json(#"{"error":"unknown code"}"#)) }
            await #expect(throws: BackendError.unknownCode) {
                _ = try await client.redeemPairingCode("123456", deviceName: "Anya")
            }
        }

        @Test func expiredCodeMapsTo410() async {
            let client = makeClient { _ in (410, json(#"{"error":"code expired or used"}"#)) }
            await #expect(throws: BackendError.codeExpiredOrUsed) {
                _ = try await client.redeemPairingCode("123456", deviceName: "Anya")
            }
        }

        @Test func staleTokenMapsTo401() async {
            let client = makeClient { _ in (401, json(#"{"error":"unauthorized"}"#)) }
            await #expect(throws: BackendError.unauthorized) {
                try await client.uploadAPNsToken("abc", token: "regi-token")
            }
        }

        @Test func serverErrorKeepsItsStatus() async {
            let client = makeClient { _ in (503, json("{}")) }
            await #expect(throws: BackendError.server(503)) {
                try await client.uploadAPNsToken("abc", token: "t")
            }
        }

        @Test func transportFailureIsReported() async {
            let client = makeClient { _ in throw URLError(.notConnectedToInternet) }
            await #expect(throws: BackendError.self) {
                try await client.uploadAPNsToken("abc", token: "t")
            }
        }

        @Test func missingHostGivesNotConfigured() async {
            let client = BackendClient(baseURL: nil, session: .shared)
            await #expect(throws: BackendError.notConfigured) {
                _ = try await client.createFamily(deviceName: "Vanda telefonja")
            }
        }
    }

    struct Requests {

        @Test func createFamilyReturnsChildCredentials() async throws {
            let client = makeClient { _ in
                (201, json(#"{"familyId":"f1","deviceId":"d1","token":"tok"}"#))
            }
            let credentials = try await client.createFamily(deviceName: "Vanda telefonja")
            #expect(credentials.familyId == "f1")
            #expect(credentials.deviceId == "d1")
            #expect(credentials.token == "tok")
            #expect(credentials.role == .child)
            #expect(credentials.deviceName == "Vanda telefonja")
        }

        @Test func redeemUsesTheRoleFromTheResponse() async throws {
            let client = makeClient { _ in
                (201, json(#"{"familyId":"f1","deviceId":"d2","token":"tok2","role":"child"}"#))
            }
            let credentials = try await client.redeemPairingCode("654321", deviceName: "Vanda iPadje")
            #expect(credentials.role == .child)
            #expect(credentials.deviceId == "d2")
        }

        @Test func pairingCodeRequestCarriesTheRole() async throws {
            let client = makeClient { _ in
                (201, json(#"{"code":"123456","expiresAt":1000,"role":"child"}"#))
            }
            let code = try await client.createPairingCode(role: .child, token: "tok")
            #expect(code.code == "123456")
            #expect(code.role == .child)
            #expect(code.expiresAt == Date(timeIntervalSince1970: 1))

            let body = try #require(StubURLProtocol.lastBody)
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(sent?["role"] as? String == "child")
        }

        @Test func authenticatedCallsSendBearerToken() async throws {
            let client = makeClient { _ in (204, Data()) }
            try await client.uploadAPNsToken("apns-token", token: "titkos")
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer titkos")
            #expect(request.httpMethod == "PUT")
        }

        @Test func deleteDeviceUsesDeleteMethod() async throws {
            let client = makeClient { _ in (204, Data()) }
            try await client.deleteDevice(token: "titkos")
            let request = try #require(StubURLProtocol.lastRequest)
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/devices/me")
        }

        @Test func codeIsGroupedForReading() {
            let code = PairingCode(code: "123456", expiresAt: .now, role: .parent)
            #expect(code.grouped == "123 456")
        }

        @Test func countdownCountsDownInMinutesAndSeconds() {
            let start = Date(timeIntervalSince1970: 0)
            let code = PairingCode(
                code: "123456", expiresAt: Date(timeIntervalSince1970: 600), role: .parent
            )
            #expect(code.remainingText(at: start) == "10:00")
            #expect(code.remainingText(at: Date(timeIntervalSince1970: 540)) == "1:00")
            #expect(code.remainingText(at: Date(timeIntervalSince1970: 591)) == "0:09")
        }

        @Test func expiredCodeNeverShowsNegativeTime() {
            let code = PairingCode(
                code: "123456", expiresAt: Date(timeIntervalSince1970: 600), role: .parent
            )
            #expect(code.isExpired(at: Date(timeIntervalSince1970: 700)))
            #expect(code.remainingText(at: Date(timeIntervalSince1970: 700)) == "0:00")
        }

        @Test func testPushResultsSeparateDeliveredFromFailed() async throws {
            let client = makeClient { _ in
                (200, json(#"{"results":[{"deviceId":"a","status":200},{"deviceId":"b","status":0}]}"#))
            }
            let results = try await client.sendTestPush(token: "tok")
            #expect(results.count == 2)
            #expect(results[0].delivered)
            #expect(results[1].delivered == false)
        }
    }
}
