import Foundation

/// Handles checking for app updates from GitHub releases
final class UpdateChecker {
    
    // MARK: - Types
    
    struct UpdateInfo {
        let version: String
        let releaseURL: URL
        let releaseNotes: String?
    }
    
    enum UpdateCheckResult {
        case updateAvailable(UpdateInfo)
        case upToDate
        case error(Error)
    }
    
    enum UpdateError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case parseError
        case noReleases
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid GitHub API URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .parseError:
                return "Failed to parse release information"
            case .noReleases:
                return "No releases found"
            }
        }
    }
    
    // MARK: - Constants
    
    private enum Constants {
        static let owner = "hafiezul"
        static let repo = "AlwaysOn"
        static let apiURL = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
    }
    
    // MARK: - Properties
    
    /// Current app version from bundle
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    // MARK: - Public Methods
    
    /// Check for updates asynchronously
    /// - Parameter completion: Called with the result on the main thread
    static func checkForUpdate(completion: @escaping (UpdateCheckResult) -> Void) {
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
                
                guard let data = data else {
                    completion(.error(UpdateError.parseError))
                    return
                }
                
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        completion(.error(UpdateError.parseError))
                        return
                    }
                    
                    guard let tagName = json["tag_name"] as? String,
                          let htmlURLString = json["html_url"] as? String,
                          let releaseURL = URL(string: htmlURLString) else {
                        completion(.error(UpdateError.noReleases))
                        return
                    }
                    
                    let releaseNotes = json["body"] as? String
                    let latestVersion = normalizeVersion(tagName)
                    let current = normalizeVersion(currentVersion)
                    
                    if isVersion(latestVersion, newerThan: current) {
                        let info = UpdateInfo(
                            version: latestVersion,
                            releaseURL: releaseURL,
                            releaseNotes: releaseNotes
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
    @available(macOS 12.0, *)
    static func checkForUpdate() async -> UpdateCheckResult {
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
