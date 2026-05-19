//
//  GoogleAuthClient.swift
//  leanring-buddy
//
//  Google OAuth sign-in using ASWebAuthenticationSession with PKCE.
//  No client secret — native apps use PKCE per RFC 8252, so the
//  authorization code exchange requires only the code verifier.
//
//  Prerequisites:
//  - The OAuth client in Google Cloud Console must be of type "iOS"
//    (not "Web"), which automatically permits the reverse-client-ID
//    redirect URI used here.
//  - No URL scheme registration is required in Info.plist —
//    ASWebAuthenticationSession intercepts the redirect internally.
//

import AuthenticationServices
import CryptoKit
import Foundation

enum GoogleAuthError: LocalizedError {
    case noPresentationWindow
    case sessionFailedToStart
    case userCancelled
    case noCallbackURL
    case noAuthorizationCode
    case tokenExchangeFailed(String)
    case userInfoFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .noPresentationWindow:
            return "No window available to present Google Sign-In."
        case .sessionFailedToStart:
            return "Google Sign-In session failed to start."
        case .userCancelled:
            return "Sign-in was cancelled."
        case .noCallbackURL:
            return "No callback received from Google."
        case .noAuthorizationCode:
            return "No authorization code in the Google callback."
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        case .userInfoFetchFailed(let detail):
            return "Could not fetch your Google profile: \(detail)"
        }
    }
}

@MainActor
final class GoogleAuthClient: NSObject {

    // MARK: - OAuth Configuration

    private static let googleClientID =
        "908455519788-oh2ais7ocq6tt5it4n5d6h26bn3i2jvc.apps.googleusercontent.com"

    // Reverse of the client ID — the standard redirect scheme for native Google OAuth.
    private static let redirectScheme =
        "com.googleusercontent.apps.908455519788-oh2ais7ocq6tt5it4n5d6h26bn3i2jvc"

    private static let redirectURI =
        "\(redirectScheme):/oauth2redirect/google"

    private static let googleAuthorizationEndpoint =
        "https://accounts.google.com/o/oauth2/v2/auth"

    private static let googleTokenEndpoint =
        "https://oauth2.googleapis.com/token"

    private static let googleUserInfoEndpoint =
        "https://www.googleapis.com/oauth2/v2/userinfo"

    // Held strongly so the session isn't deallocated before the callback fires.
    private var activeAuthSession: ASWebAuthenticationSession?
    // presentationContextProvider is a weak var on ASWebAuthenticationSession,
    // so we must hold a strong reference here or it is deallocated before start().
    private var activeAnchorProvider: WindowAnchorProvider?

    // MARK: - Public Interface

    /// Signs the user in with Google and returns their name and email.
    /// Uses NSApp.keyWindow as the presentation anchor — call this while the panel is open.
    func signIn() async throws -> GoogleProfile {
        guard let presentationAnchor = currentPresentationAnchor() else {
            throw GoogleAuthError.noPresentationWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        presentationAnchor.makeKeyAndOrderFront(nil)

        let codeVerifier = Self.generatePKCECodeVerifier()
        let codeChallenge = Self.generatePKCECodeChallenge(from: codeVerifier)
        let authorizationURL = Self.buildAuthorizationURL(codeChallenge: codeChallenge)

        let callbackURL = try await runAuthSession(
            authorizationURL: authorizationURL,
            presentationAnchor: presentationAnchor
        )

        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let authorizationCode = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleAuthError.noAuthorizationCode
        }

        let accessToken = try await exchangeAuthorizationCodeForAccessToken(
            authorizationCode: authorizationCode,
            codeVerifier: codeVerifier
        )

        return try await fetchGoogleProfile(accessToken: accessToken)
    }

    // MARK: - ASWebAuthenticationSession

    private func runAuthSession(
        authorizationURL: URL,
        presentationAnchor: NSWindow
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let continuationGate = AuthSessionContinuation(continuation)
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: Self.redirectScheme
            ) { [weak self] callbackURL, error in
                self?.activeAuthSession = nil
                self?.activeAnchorProvider = nil

                if let sessionError = error as? ASWebAuthenticationSessionError,
                   sessionError.code == .canceledLogin {
                    continuationGate.resume(throwing: GoogleAuthError.userCancelled)
                } else if let error = error {
                    continuationGate.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    continuationGate.resume(returning: callbackURL)
                } else {
                    continuationGate.resume(throwing: GoogleAuthError.noCallbackURL)
                }
            }

            let anchorProvider = WindowAnchorProvider(window: presentationAnchor)
            activeAnchorProvider = anchorProvider
            session.presentationContextProvider = anchorProvider
            // Allow the system browser to share an existing Google session so the
            // user doesn't have to log in again if already signed into Google.
            session.prefersEphemeralWebBrowserSession = false
            activeAuthSession = session

            let sessionStarted = session.start()
            if !sessionStarted {
                activeAuthSession = nil
                continuationGate.resume(throwing: GoogleAuthError.sessionFailedToStart)
            }
        }
    }

    private func currentPresentationAnchor() -> NSWindow? {
        if let keyWindow = NSApp.keyWindow {
            return keyWindow
        }

        if let mainWindow = NSApp.mainWindow {
            return mainWindow
        }

        return NSApp.windows.first { window in
            window.isVisible && window.canBecomeKey
        }
    }

    // MARK: - PKCE

    private static func generatePKCECodeVerifier() -> String {
        var randomBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        return Data(randomBytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func generatePKCECodeChallenge(from codeVerifier: String) -> String {
        let verifierData = Data(codeVerifier.utf8)
        let challengeData = Data(SHA256.hash(data: verifierData))
        return challengeData
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func buildAuthorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: googleAuthorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id",             value: googleClientID),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "https://www.googleapis.com/auth/userinfo.profile https://www.googleapis.com/auth/userinfo.email"),
            URLQueryItem(name: "code_challenge",        value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type",           value: "online"),
        ]
        return components.url!
    }

    // MARK: - Token Exchange

    private func exchangeAuthorizationCodeForAccessToken(
        authorizationCode: String,
        codeVerifier: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: Self.googleTokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyFields: [String: String] = [
            "client_id":    Self.googleClientID,
            "code":         authorizationCode,
            "code_verifier": codeVerifier,
            "grant_type":   "authorization_code",
            "redirect_uri": Self.redirectURI,
        ]
        request.httpBody = bodyFields
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)

        guard let urlResponse = httpResponse as? HTTPURLResponse, urlResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "unknown error"
            throw GoogleAuthError.tokenExchangeFailed(errorBody)
        }

        guard
            let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let accessToken = responseJSON["access_token"] as? String
        else {
            throw GoogleAuthError.tokenExchangeFailed("Could not parse access token from response")
        }

        return accessToken
    }

    // MARK: - User Info

    private func fetchGoogleProfile(accessToken: String) async throws -> GoogleProfile {
        var request = URLRequest(url: URL(string: Self.googleUserInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (responseData, httpResponse) = try await URLSession.shared.data(for: request)

        guard let urlResponse = httpResponse as? HTTPURLResponse, urlResponse.statusCode == 200 else {
            let errorBody = String(data: responseData, encoding: .utf8) ?? "unknown error"
            throw GoogleAuthError.userInfoFetchFailed(errorBody)
        }

        guard
            let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let name = responseJSON["name"] as? String,
            let email = responseJSON["email"] as? String
        else {
            throw GoogleAuthError.userInfoFetchFailed("Missing name or email in Google user info response")
        }

        return GoogleProfile(name: name, email: email)
    }
}

// MARK: - Presentation Context Provider

private final class WindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return window
    }
}

private final class AuthSessionContinuation {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<URL, Error>

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        guard markAsResumed() else { return }
        continuation.resume(returning: url)
    }

    func resume(throwing error: Error) {
        guard markAsResumed() else { return }
        continuation.resume(throwing: error)
    }

    private func markAsResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}
