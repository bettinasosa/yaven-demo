//
//  YavenOpenCommandResolver.swift
//  leanring-buddy
//

import AppKit
import Foundation

enum YavenOpenTarget: Equatable {
    case application(name: String)
    case url(URL, displayName: String)
}

enum YavenOpenCommandResolver {
    private static let leadingRequestPhrases = [
        "hey yaven ",
        "yaven ",
        "please ",
        "can you ",
        "could you ",
        "would you ",
        "will you ",
        "can u ",
        "could u ",
        "i want you to ",
        "i need you to "
    ]

    private static let targetPrefixes = [
        "navigate to ",
        "take me to ",
        "bring up ",
        "open up ",
        "launch ",
        "start ",
        "open ",
        "go to "
    ]

    private static let trailingRequestPhrases = [
        " for me",
        " please"
    ]

    private static let applicationSuffixes = [
        " application",
        " browser",
        " app"
    ]

    private static let websiteAliases = [
        "google": (url: URL(string: "https://www.google.com")!, displayName: "Google")
    ]

    private static let bundleIdentifierAliases = [
        "arc": "company.thebrowser.Browser",
        "calculator": "com.apple.calculator",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "mail": "com.apple.mail",
        "safari": "com.apple.Safari"
    ]

    static func openTarget(from command: String) -> YavenOpenTarget? {
        guard let rawTarget = rawTarget(from: command) else { return nil }
        let cleanedTarget = cleanTarget(rawTarget)
        guard !cleanedTarget.isEmpty else { return nil }

        if let websiteTarget = websiteTarget(from: cleanedTarget) {
            return websiteTarget
        }

        let applicationName = cleanApplicationName(cleanedTarget)
        guard !applicationName.isEmpty else { return nil }
        return .application(name: applicationName)
    }

    static func runningApplication(matching appName: String) -> NSRunningApplication? {
        let cleanedAppName = cleanApplicationName(appName)
        let normalizedSearchName = normalizedApplicationName(cleanedAppName)
        guard !normalizedSearchName.isEmpty else { return nil }

        let runningApplications = NSWorkspace.shared.runningApplications
        if let exactMatch = runningApplications.first(where: { application in
            guard let localizedName = application.localizedName else { return false }
            return normalizedApplicationName(localizedName) == normalizedSearchName
        }) {
            return exactMatch
        }

        return runningApplications.first { application in
            guard let localizedName = application.localizedName else { return false }
            let candidateName = normalizedApplicationName(localizedName)
            return candidateName.contains(normalizedSearchName)
        }
    }

    /// Launches the app using the system `open` command, which is more reliable than NSWorkspace
    /// for apps that may not yet be running. Returns the display name on success, nil on failure.
    static func launch(appName: String) -> String? {
        let cleanedAppName = cleanApplicationName(appName)
        let normalizedSearchName = normalizedApplicationName(cleanedAppName)
        guard !normalizedSearchName.isEmpty else { return nil }

        if let bundleIdentifier = bundleIdentifierAliases[normalizedSearchName] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleIdentifier]
            do {
                try process.run()
                return cleanedAppName.prefix(1).uppercased() + cleanedAppName.dropFirst()
            } catch {
                return nil
            }
        }

        guard let applicationURL = applicationURL(for: appName) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [applicationURL.path]
        do {
            try process.run()
            return applicationURL.deletingPathExtension().lastPathComponent
        } catch {
            return nil
        }
    }

    /// Launches the app by bundle identifier using the system `open` command.
    static func launch(bundleIdentifier: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-b", bundleIdentifier]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    static func applicationURL(for appName: String) -> URL? {
        let cleanedAppName = cleanApplicationName(appName)
        let normalizedSearchName = normalizedApplicationName(cleanedAppName)
        guard !normalizedSearchName.isEmpty else { return nil }

        if let bundleIdentifier = bundleIdentifierAliases[normalizedSearchName],
           let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return applicationURL
        }

        let candidateDirectories = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true)
        ]

        if let exactApplicationURL = exactApplicationURL(for: cleanedAppName, in: candidateDirectories) {
            return exactApplicationURL
        }

        let applicationURLs = candidateDirectories.flatMap { candidateApplicationURLs(in: $0) }
        if let exactMatch = applicationURLs.first(where: { url in
            normalizedApplicationName(url.deletingPathExtension().lastPathComponent) == normalizedSearchName
        }) {
            return exactMatch
        }

        return applicationURLs.first { url in
            let candidateName = normalizedApplicationName(url.deletingPathExtension().lastPathComponent)
            return candidateName.contains(normalizedSearchName)
        }
    }

    private static func rawTarget(from command: String) -> String? {
        var normalizedCommand = normalizeWhitespace(command)
        guard !normalizedCommand.isEmpty else { return nil }

        var didStripPrefix = true
        while didStripPrefix {
            didStripPrefix = false
            let lowercasedCommand = normalizedCommand.lowercased()
            if let leadingPhrase = leadingRequestPhrases.first(where: { lowercasedCommand.hasPrefix($0) }) {
                normalizedCommand = String(normalizedCommand.dropFirst(leadingPhrase.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStripPrefix = true
            }
        }

        let lowercasedCommand = normalizedCommand.lowercased()
        guard let matchedPrefix = targetPrefixes.first(where: { lowercasedCommand.hasPrefix($0) }) else {
            return nil
        }

        return String(normalizedCommand.dropFirst(matchedPrefix.count))
    }

    private static func cleanTarget(_ target: String) -> String {
        var cleanedTarget = normalizeWhitespace(target)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .?!\"'`"))

        if cleanedTarget.lowercased().hasPrefix("the ") {
            cleanedTarget = String(cleanedTarget.dropFirst(4))
        }

        var didStripSuffix = true
        while didStripSuffix {
            didStripSuffix = false
            let lowercasedTarget = cleanedTarget.lowercased()
            if let trailingPhrase = trailingRequestPhrases.first(where: { lowercasedTarget.hasSuffix($0) }) {
                cleanedTarget = String(cleanedTarget.dropLast(trailingPhrase.count))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .?!\"'`"))
                didStripSuffix = true
            }
        }

        return cleanedTarget
    }

    private static func cleanApplicationName(_ appName: String) -> String {
        var cleanedName = normalizeWhitespace(appName)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .?!\"'`"))
        let lowercasedName = cleanedName.lowercased()
        if lowercasedName.hasPrefix("the ") {
            cleanedName = String(cleanedName.dropFirst(4))
        }

        var didStripSuffix = true
        while didStripSuffix {
            didStripSuffix = false
            for suffix in applicationSuffixes where cleanedName.lowercased().hasSuffix(suffix) {
                cleanedName = String(cleanedName.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStripSuffix = true
                break
            }
        }

        return cleanedName
    }

    private static func websiteTarget(from target: String) -> YavenOpenTarget? {
        let normalizedTarget = target.lowercased()
        if let websiteAlias = websiteAliases[normalizedTarget] {
            return .url(websiteAlias.url, displayName: websiteAlias.displayName)
        }

        if let explicitURL = URL(string: target),
           let scheme = explicitURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           explicitURL.host != nil {
            return .url(explicitURL, displayName: displayName(for: explicitURL))
        }

        guard normalizedTarget.range(
            of: #"^[a-z0-9-]+(\.[a-z0-9-]+)+(/[^\s]*)?$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }

        guard let url = URL(string: "https://\(normalizedTarget)") else { return nil }
        return .url(url, displayName: displayName(for: url))
    }

    private static func displayName(for url: URL) -> String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func exactApplicationURL(for appName: String, in directories: [URL]) -> URL? {
        let normalizedName = appName.hasSuffix(".app") ? appName : "\(appName).app"
        for directory in directories {
            let candidateURL = directory.appendingPathComponent(normalizedName, isDirectory: true)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
        }
        return nil
    }

    private static func candidateApplicationURLs(in directory: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path),
              let enumerator = FileManager.default.enumerator(
                  at: directory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else {
            return []
        }

        var applicationURLs: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "app" else { continue }
            applicationURLs.append(url)
            enumerator.skipDescendants()
        }
        return applicationURLs
    }

    private static func normalizedApplicationName(_ appName: String) -> String {
        appName
            .replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
