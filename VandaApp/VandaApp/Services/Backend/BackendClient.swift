//
//  BackendClient.swift
//  VandaApp
//
//  Vékony async kliens a Vanda-backendhez. Az URLSession injektálható, hogy a
//  tesztek URLProtocol-stubbal, élő backend nélkül futhassanak.
//

import Foundation

struct PairingCode: Equatable {
    var code: String
    var expiresAt: Date
    var role: AppRole

    /// Formázott, hat számjegyű alak: „123 456".
    var grouped: String {
        guard code.count == 6 else { return code }
        let middle = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<middle]) \(code[middle...])"
    }

    func isExpired(at now: Date) -> Bool { expiresAt <= now }

    /// Visszaszámláló „m:ss" alakban. A lejárat utáni negatív időt 0:00-ra
    /// vágjuk, hogy a felület sose mutasson mínuszt.
    func remainingText(at now: Date) -> String {
        let seconds = Int(max(0, expiresAt.timeIntervalSince(now)).rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct TestPushResult: Equatable {
    var deviceId: String
    var status: Int

    /// A backend 0-t ad, ha HTTP-státusz sem született (transzport-hiba).
    var delivered: Bool { (200..<300).contains(status) }
}

final class BackendClient {
    static let shared = BackendClient()

    private let baseURL: URL?
    private let session: URLSession

    init(baseURL: URL? = BackendConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Endpointok

    func createFamily(deviceName: String) async throws -> DeviceCredentials {
        let response: PairingResponse = try await send(
            "/families", method: "POST", body: ["deviceName": deviceName], token: nil
        )
        return DeviceCredentials(
            familyId: response.familyId,
            deviceId: response.deviceId,
            token: response.token,
            role: .child,
            deviceName: deviceName
        )
    }

    func createPairingCode(role: AppRole, token: String) async throws -> PairingCode {
        let response: PairingCodeResponse = try await send(
            "/pairing-codes", method: "POST", body: ["role": role.rawValue], token: token
        )
        return PairingCode(
            code: response.code,
            expiresAt: Date(timeIntervalSince1970: response.expiresAt / 1000),
            role: AppRole(rawValue: response.role ?? role.rawValue) ?? role
        )
    }

    func redeemPairingCode(_ code: String, deviceName: String) async throws -> DeviceCredentials {
        let response: PairingResponse = try await send(
            "/pair", method: "POST", body: ["code": code, "deviceName": deviceName], token: nil
        )
        return DeviceCredentials(
            familyId: response.familyId,
            deviceId: response.deviceId,
            token: response.token,
            role: AppRole(rawValue: response.role ?? "parent") ?? .parent,
            deviceName: deviceName
        )
    }

    func uploadAPNsToken(_ apnsToken: String, token: String) async throws {
        try await sendIgnoringBody(
            "/devices/me/apns-token", method: "PUT", body: ["token": apnsToken], token: token
        )
    }

    func sendTestPush(token: String) async throws -> [TestPushResult] {
        let response: TestPushResponse = try await send(
            "/test-pushes", method: "POST", body: nil, token: token
        )
        return response.results.map { TestPushResult(deviceId: $0.deviceId, status: $0.status) }
    }

    func deleteDevice(token: String) async throws {
        try await sendIgnoringBody("/devices/me", method: "DELETE", body: nil, token: token)
    }

    // MARK: - Belső HTTP-réteg

    private struct PairingResponse: Decodable {
        var familyId: String
        var deviceId: String
        var token: String
        var role: String?
    }

    private struct PairingCodeResponse: Decodable {
        var code: String
        var expiresAt: Double
        var role: String?
    }

    private struct TestPushResponse: Decodable {
        struct Row: Decodable {
            var deviceId: String
            var status: Int
        }
        var results: [Row]
    }

    private func makeRequest(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) throws -> URLRequest {
        guard let baseURL else { throw BackendError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw BackendError.decoding }
        if let error = BackendError.forStatus(http.statusCode) { throw error }
        return data
    }

    private func send<T: Decodable>(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) async throws -> T {
        let data = try await perform(try makeRequest(path, method: method, body: body, token: token))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BackendError.decoding
        }
    }

    private func sendIgnoringBody(
        _ path: String, method: String, body: [String: String]?, token: String?
    ) async throws {
        _ = try await perform(try makeRequest(path, method: method, body: body, token: token))
    }
}
