import Foundation

extension Bundle {
    func infoPlistString(forKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }

    var appVersion: String {
        infoPlistString(forKey: "CFBundleShortVersionString") ?? "Unknown"
    }

    var buildNumber: String {
        infoPlistString(forKey: "CFBundleVersion") ?? "Unknown"
    }
}

enum AppUpdateRepository {
    static let owner = "hafiezul"
    static let repo = "AlwaysOn"

    static var repositoryURL: URL {
        URL(string: "https://github.com/\(owner)/\(repo)")!
    }

    static var issuesURL: URL {
        repositoryURL.appending(path: "issues")
    }

    static var releasesPageURL: URL {
        repositoryURL.appending(path: "releases/latest")
    }
}

enum AppUpdateMode: String {
    case manual
    case sparkle

    static var current: AppUpdateMode {
        Bundle.main
            .infoPlistString(forKey: "AlwaysOnUpdateMode")
            .flatMap(AppUpdateMode.init(rawValue:)) ?? .manual
    }

    var usesSparkle: Bool {
        self == .sparkle
    }
}

struct AppUpdateInfo {
    let version: String
    let releaseURL: URL
    let releaseNotes: String?
}

enum AppUpdateCheckResult {
    case updateAvailable(AppUpdateInfo)
    case upToDate
    case error(Error)
}

/// Handles checking for app updates from GitHub releases
final class UpdateChecker {
    typealias UpdateInfo = AppUpdateInfo
    typealias UpdateCheckResult = AppUpdateCheckResult

    enum UpdateError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case invalidResponse
        case parseError
        case noReleases
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid GitHub API URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Update server returned an invalid response"
            case .parseError:
                return "Failed to parse release information"
            case .noReleases:
                return "No releases found"
            }
        }
    }
    
    // MARK: - Constants
    
    private enum Constants {
        static let apiURL = "https://api.github.com/repos/\(AppUpdateRepository.owner)/\(AppUpdateRepository.repo)/releases/latest"
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }
    
    // MARK: - Properties

    /// Current app version from bundle
    static var currentVersion: String {
        Bundle.main.appVersion
    }

    static var currentBuildNumber: String {
        Bundle.main.buildNumber
    }

    static var currentMode: AppUpdateMode {
        AppUpdateMode.current
    }

    static var repositoryURL: URL {
        AppUpdateRepository.repositoryURL
    }

    static var issuesURL: URL {
        repositoryURL.appending(path: "issues")
    }

    static var releasesPageURL: URL {
        AppUpdateRepository.releasesPageURL
    }
    
    // MARK: - Public Methods
    
    /// Check for updates asynchronously
    /// - Parameter completion: Called with the result on the main thread
    static func checkForUpdate(completion: @escaping (AppUpdateCheckResult) -> Void) {
        guard let url = URL(string: Constants.apiURL) else {
            DispatchQueue.main.async {
                completion(.error(UpdateError.invalidURL))
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("AlwaysOn/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.error(UpdateError.networkError(error)))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    completion(.error(UpdateError.invalidResponse))
                    return
                }
                
                guard let data = data else {
                    completion(.error(UpdateError.parseError))
                    return
                }
                
                do {
                    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                    guard release.htmlURL.scheme == "https" else {
                        completion(.error(UpdateError.invalidResponse))
                        return
                    }

                    let latestVersion = normalizeVersion(release.tagName)
                    let current = normalizeVersion(currentVersion)
                    
                    if isVersion(latestVersion, newerThan: current) {
                        let info = UpdateInfo(
                            version: latestVersion,
                            releaseURL: release.htmlURL,
                            releaseNotes: release.body
                        )
                        completion(.updateAvailable(info))
                    } else {
                        completion(.upToDate)
                    }
                } catch {
                    completion(.error(UpdateError.parseError))
                }
            }
        }.resume()
    }
    
    /// Check for updates using async/await
    static func checkForUpdate() async -> AppUpdateCheckResult {
        await withCheckedContinuation { continuation in
            checkForUpdate { result in
                continuation.resume(returning: result)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Normalize version string (remove 'v' prefix, trim whitespace)
    private static func normalizeVersion(_ version: String) -> String {
        version
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "v", with: "")
    }
    
    /// Compare two version strings
    /// - Returns: true if version1 is newer than version2
    private static func isVersion(_ version1: String, newerThan version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }
        
        // Pad shorter array with zeros
        let maxLength = max(v1Components.count, v2Components.count)
        let v1Padded = v1Components + Array(repeating: 0, count: maxLength - v1Components.count)
        let v2Padded = v2Components + Array(repeating: 0, count: maxLength - v2Components.count)
        
        for (a, b) in zip(v1Padded, v2Padded) {
            if a > b { return true }
            if a < b { return false }
        }
        
        return false
    }
}
