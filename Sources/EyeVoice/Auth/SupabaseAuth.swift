import Foundation
import Security

enum SupabaseConfig {
    static let projectURL = "https://seexmgivktuycodxrjhs.supabase.co"
    static let publishableKey = "sb_publishable_bPrqO4BMzg1jvFSkJa2mjg_mhEGc15g"
    static let authURL = "\(projectURL)/auth/v1"
}

enum AppLinks {
    static let websiteBaseURL = URL(string: "https://eyevoicetranslate.com")!
    static let privacyURL = websiteBaseURL.appendingPathComponent("privacy")
    static let termsURL = websiteBaseURL.appendingPathComponent("terms")

    static func subscriptionURL(planID: String) -> URL {
        var components = URLComponents(
            url: websiteBaseURL.appendingPathComponent("profile"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "from", value: "app"),
            URLQueryItem(name: "plan", value: planID),
        ]
        return components.url!
    }
}

struct SupabaseUser: Codable, Equatable {
    let id: String
    let email: String?
    let createdAt: String?
    let userMetadata: SupabaseUserMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case userMetadata = "user_metadata"
    }
}

struct SupabaseUserMetadata: Codable, Equatable {
    let plan: String?
}

private struct SupabaseAuthEnvelope: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: SupabaseUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct StoredAuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: SupabaseUser
}

private struct SupabaseErrorPayload: Decodable {
    let message: String?
    let msg: String?
    let errorDescription: String?
    let errorCode: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case message
        case msg
        case errorDescription = "error_description"
        case errorCode = "error_code"
        case code
    }
}

private struct RealtimeClientSecretResponse: Decodable {
    let value: String
}

enum SupabaseAuthError: LocalizedError {
    case server(message: String, code: String?, status: Int)
    case invalidResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .server(let message, _, _): return message
        case .invalidResponse: return "Invalid server response"
        case .network(let message): return message
        }
    }

    var statusCode: Int? {
        guard case .server(_, _, let status) = self else { return nil }
        return status
    }
}

enum SignUpOutcome {
    case signedIn
    case confirmationRequired(email: String)
}

@MainActor
final class SupabaseAuthManager: ObservableObject {
    static let shared = SupabaseAuthManager()

    @Published private(set) var user: SupabaseUser?
    @Published private(set) var isCheckingSession = true
    @Published private(set) var isWorking = false

    private var session: StoredAuthSession?
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        Task { await restoreSession() }
    }

    var isAuthenticated: Bool { user != nil && session != nil }

    func signIn(email: String, password: String) async throws {
        isWorking = true
        defer { isWorking = false }

        let data = try await request(
            "token?grant_type=password",
            body: ["email": normalizedEmail(email), "password": password]
        )
        let envelope = try decodeEnvelope(data)
        let newSession = try makeSession(from: envelope)
        try persist(newSession)
        session = newSession
        user = newSession.user
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        isWorking = true
        defer { isWorking = false }

        let cleanEmail = normalizedEmail(email)
        let data = try await request(
            "signup",
            body: ["email": cleanEmail, "password": password, "data": [:] as [String: String]]
        )
        let envelope = try decodeEnvelope(data)

        if envelope.accessToken != nil, envelope.refreshToken != nil, envelope.user != nil {
            let newSession = try makeSession(from: envelope)
            try persist(newSession)
            session = newSession
            user = newSession.user
            return .signedIn
        }

        return .confirmationRequired(email: cleanEmail)
    }

    func verifySignupOTP(email: String, code: String) async throws {
        isWorking = true
        defer { isWorking = false }

        let data = try await request(
            "verify",
            body: [
                "email": normalizedEmail(email),
                "token": normalizedOTP(code),
                "type": "email",
            ]
        )
        let newSession = try makeSession(from: decodeEnvelope(data))
        try persist(newSession)
        session = newSession
        user = newSession.user
    }

    func resendSignupOTP(email: String) async throws {
        isWorking = true
        defer { isWorking = false }

        _ = try await request(
            "resend",
            body: [
                "email": normalizedEmail(email),
                "type": "signup",
            ]
        )
    }

    func signOut() async {
        isWorking = true
        defer { isWorking = false }

        if let accessToken = session?.accessToken {
            _ = try? await request(
                "logout?scope=local",
                body: nil,
                bearer: accessToken
            )
        }
        clearSession()
    }

    func refreshCurrentUser() async {
        guard !isWorking, var current = session else { return }

        do {
            if current.expiresAt.timeIntervalSinceNow < 60 {
                current = try await refresh(using: current.refreshToken)
            }

            do {
                current.user = try await fetchUser(accessToken: current.accessToken)
            } catch let error as SupabaseAuthError where error.statusCode == 401 {
                current = try await refresh(using: current.refreshToken)
                current.user = try await fetchUser(accessToken: current.accessToken)
            }

            try persist(current)
            session = current
            user = current.user
        } catch {
            // Keep the current session available when the website or network is unavailable.
        }
    }

    func realtimeClientSecret(
        mode: TranslationMode,
        targetLanguage: String,
        voice: String
    ) async throws -> String {
        guard var current = session else {
            throw SupabaseAuthError.server(
                message: "Sign in to start translation",
                code: "not_authenticated",
                status: 401
            )
        }

        if current.expiresAt.timeIntervalSinceNow < 60 {
            current = try await refresh(using: current.refreshToken)
            try persist(current)
            session = current
            user = current.user
        }

        do {
            return try await requestRealtimeClientSecret(
                mode: mode,
                targetLanguage: targetLanguage,
                voice: voice,
                using: current
            )
        } catch let error as SupabaseAuthError where error.statusCode == 401 {
            current = try await refresh(using: current.refreshToken)
            try persist(current)
            session = current
            user = current.user
            return try await requestRealtimeClientSecret(
                mode: mode,
                targetLanguage: targetLanguage,
                voice: voice,
                using: current
            )
        }
    }

    func uploadTranslationSessions(_ records: [TranslationSessionRecord]) async throws {
        guard !records.isEmpty, var current = session else { return }

        if current.expiresAt.timeIntervalSinceNow < 60 {
            current = try await refresh(using: current.refreshToken)
            try persist(current)
            session = current
            user = current.user
        }

        do {
            try await insertTranslationSessions(records, using: current)
        } catch let error as SupabaseAuthError where error.statusCode == 401 {
            current = try await refresh(using: current.refreshToken)
            try persist(current)
            session = current
            user = current.user
            try await insertTranslationSessions(records, using: current)
        }
    }

    private func restoreSession() async {
        defer { isCheckingSession = false }

        guard let stored = try? loadStoredSession() else {
            clearSession()
            return
        }

        do {
            var current = stored
            if current.expiresAt.timeIntervalSinceNow < 60 {
                current = try await refresh(using: current.refreshToken)
            }

            do {
                current.user = try await fetchUser(accessToken: current.accessToken)
            } catch let error as SupabaseAuthError where error.statusCode == 401 {
                current = try await refresh(using: current.refreshToken)
                current.user = try await fetchUser(accessToken: current.accessToken)
            } catch SupabaseAuthError.network {
                // Keep a still-valid cached session available while offline.
            }

            try persist(current)
            session = current
            user = current.user
        } catch {
            clearSession()
        }
    }

    private func refresh(using refreshToken: String) async throws -> StoredAuthSession {
        let data = try await request(
            "token?grant_type=refresh_token",
            body: ["refresh_token": refreshToken]
        )
        return try makeSession(from: decodeEnvelope(data))
    }

    private func fetchUser(accessToken: String) async throws -> SupabaseUser {
        let data = try await request("user", method: "GET", body: nil, bearer: accessToken)
        do {
            return try decoder.decode(SupabaseUser.self, from: data)
        } catch {
            throw SupabaseAuthError.invalidResponse
        }
    }

    private func insertTranslationSessions(
        _ records: [TranslationSessionRecord],
        using session: StoredAuthSession
    ) async throws {
        guard let url = URL(
            string: "\(SupabaseConfig.projectURL)/rest/v1/translation_sessions?on_conflict=id"
        ) else {
            throw SupabaseAuthError.invalidResponse
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload: [[String: Any]] = records.map { record in
            [
                "id": record.id.uuidString.lowercased(),
                "user_id": session.user.id,
                "started_at": dateFormatter.string(from: record.startedAt),
                "ended_at": dateFormatter.string(from: record.endedAt),
                "duration_seconds": record.duration,
                "source_id": record.sourceID,
                "source_name": record.sourceName,
                "source_language": record.sourceLanguage,
                "target_language": record.targetLanguage,
            ]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "resolution=ignore-duplicates,return=minimal",
            forHTTPHeaderField: "Prefer"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseAuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorPayload = try? decoder.decode(SupabaseErrorPayload.self, from: data)
            let message = errorPayload?.message
                ?? errorPayload?.msg
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseAuthError.server(
                message: message,
                code: errorPayload?.errorCode ?? errorPayload?.code,
                status: http.statusCode
            )
        }
    }

    private func requestRealtimeClientSecret(
        mode: TranslationMode,
        targetLanguage: String,
        voice: String,
        using session: StoredAuthSession
    ) async throws -> String {
        guard let url = URL(
            string: "\(SupabaseConfig.projectURL)/functions/v1/realtime-token"
        ) else {
            throw SupabaseAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "mode": mode.rawValue,
            "target_language": targetLanguage,
            "voice": voice,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseAuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error"] as? String
                ?? payload?["message"] as? String
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseAuthError.server(
                message: message,
                code: payload?["code"] as? String,
                status: http.statusCode
            )
        }

        guard let secret = try? decoder.decode(RealtimeClientSecretResponse.self, from: data),
              !secret.value.isEmpty else {
            throw SupabaseAuthError.invalidResponse
        }
        return secret.value
    }

    private func request(
        _ path: String,
        method: String = "POST",
        body: [String: Any]?,
        bearer: String? = nil
    ) async throws -> Data {
        guard let url = URL(string: "\(SupabaseConfig.authURL)/\(path)") else {
            throw SupabaseAuthError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(bearer ?? SupabaseConfig.publishableKey)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("2024-01-01", forHTTPHeaderField: "X-Supabase-Api-Version")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseAuthError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SupabaseAuthError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(SupabaseErrorPayload.self, from: data)
            let message = payload?.message
                ?? payload?.msg
                ?? payload?.errorDescription
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw SupabaseAuthError.server(
                message: message,
                code: payload?.errorCode ?? payload?.code,
                status: http.statusCode
            )
        }
        return data
    }

    private func decodeEnvelope(_ data: Data) throws -> SupabaseAuthEnvelope {
        do {
            return try decoder.decode(SupabaseAuthEnvelope.self, from: data)
        } catch {
            throw SupabaseAuthError.invalidResponse
        }
    }

    private func makeSession(from envelope: SupabaseAuthEnvelope) throws -> StoredAuthSession {
        guard let accessToken = envelope.accessToken,
              let refreshToken = envelope.refreshToken,
              let user = envelope.user else {
            throw SupabaseAuthError.invalidResponse
        }
        let expiry = envelope.expiresAt.map(Date.init(timeIntervalSince1970:))
            ?? Date().addingTimeInterval(TimeInterval(envelope.expiresIn ?? 3600))
        return StoredAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            user: user
        )
    }

    private func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedOTP(_ code: String) -> String {
        String(code.filter(\.isNumber).prefix(6))
    }

    private func persist(_ session: StoredAuthSession) throws {
        try AuthKeychain.save(encoder.encode(session))
    }

    private func loadStoredSession() throws -> StoredAuthSession? {
        guard let data = try AuthKeychain.load() else { return nil }
        return try decoder.decode(StoredAuthSession.self, from: data)
    }

    private func clearSession() {
        session = nil
        user = nil
        try? AuthKeychain.delete()
    }
}

private enum AuthKeychain {
    private static let service = "com.aleksey.eyevoice.supabase-auth"
    private static let account = "session"

    static func save(_ data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    static func load() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        return result as? Data
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private enum KeychainError: Error {
        case status(OSStatus)
    }
}
