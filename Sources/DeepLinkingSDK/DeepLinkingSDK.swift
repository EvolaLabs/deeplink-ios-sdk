import Foundation
import UIKit

/// Deep Linking SDK for iOS
/// Compatible with iOS 13.0+ and latest Xcode versions
@available(iOS 13.0, *)
@objc public class DeepLinkingSDK: NSObject {
    
    // MARK: - Properties
    
    /// Shared instance for singleton access
    @objc public static let shared = DeepLinkingSDK()
    
    /// Base URL for the deep linking service
    private var baseURL: String = ""
    
    /// API key for authentication (if required)
    private var apiKey: String?
    
    /// Completion handlers for deferred deep links
    private var deferredLinkHandlers: [(DeepLinkData?) -> Void] = []
    
    /// Timeout for network requests (in seconds)
    private let requestTimeout: TimeInterval = 10.0
    
    // MARK: - Initialization
    
    private init() {}
    
    /// Configure the SDK with your deep linking service details
    /// - Parameters:
    ///   - baseURL: The base URL of your deep linking service (e.g., "https://your-domain.com")
    ///   - apiKey: API key for authentication (required for link creation)
    @objc public func configure(baseURL: String, apiKey: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
    }
    
    /// Configure the SDK with your deep linking service details (Objective-C compatible)
    /// - Parameters:
    ///   - baseURL: The base URL of your deep linking service (e.g., "https://your-domain.com")
    ///   - apiKey: Optional API key for authentication
    @objc public func configureWithBaseURL(_ baseURL: String, apiKey: String?) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
    }
    
    // MARK: - Link Creation
    
    /// Create a deep link with custom parameters
    /// - Parameters:
    ///   - baseURL: The base URL for your app (e.g., "https://invite.yourdomain.com")
    ///   - customParameters: Dictionary of custom parameters to append
    ///   - title: Optional title for the link
    ///   - description: Optional description for the link
    ///   - completion: Completion handler with the created link data or error
    public func createLink(baseURL: String, 
                          customParameters: [String: String] = [:], 
                          title: String? = nil, 
                          description: String? = nil,
                          completion: @escaping (Result<CreatedLinkData, SDKError>) -> Void) {
        
        guard !self.baseURL.isEmpty, let apiKey = self.apiKey else {
            completion(.failure(.notConfigured))
            return
        }
        
        let requestBody: [String: Any] = [
            "baseUrl": baseURL,
            "customParameters": customParameters
        ]
        
        if let title = title { requestBody["title"] = title }
        if let description = description { requestBody["description"] = description }
        
        makeAPIRequest(endpoint: "/api/sdk/links", 
                      method: "POST", 
                      body: requestBody) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(CreateLinkResponse.self, from: data)
                    completion(.success(response.link))
                } catch {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get user's links
    /// - Parameters:
    ///   - page: Page number (default: 1)
    ///   - limit: Items per page (default: 20)
    ///   - completion: Completion handler with links or error
    public func getLinks(page: Int = 1, 
                        limit: Int = 20,
                        completion: @escaping (Result<LinksResponse, SDKError>) -> Void) {
        
        guard !self.baseURL.isEmpty, let apiKey = self.apiKey else {
            completion(.failure(.notConfigured))
            return
        }
        
        let queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        makeAPIRequest(endpoint: "/api/sdk/links", 
                      method: "GET", 
                      queryItems: queryItems) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(LinksResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(.invalidResponse))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Deep Link Handling
    
    /// Handle incoming deep link URL
    /// - Parameters:
    ///   - url: The deep link URL to handle
    ///   - completion: Completion handler with the extracted deep link data
    public func handleDeepLink(_ url: URL, completion: @escaping (DeepLinkData?) -> Void) {
        // Extract short ID from URL
        guard let shortId = extractShortId(from: url) else {
            completion(nil)
            return
        }
        
        // Fetch deep link data
        fetchDeepLinkData(shortId: shortId) { [weak self] data in
            DispatchQueue.main.async {
                completion(data)
            }
        }
    }
    
    /// Check for deferred deep links (call this on app launch)
    /// - Parameter completion: Completion handler with deferred deep link data if available
    public func checkForDeferredDeepLink(completion: @escaping (DeepLinkData?) -> Void) {
        // Store the completion handler
        deferredLinkHandlers.append(completion)
        
        // Check localStorage equivalent (UserDefaults) for deferred link data
        if let deferredData = getDeferredLinkFromStorage() {
            // Validate timestamp (expire after 24 hours)
            let currentTime = Date().timeIntervalSince1970
            let linkTime = deferredData.timestamp / 1000 // Convert from milliseconds
            
            if currentTime - linkTime < 86400 { // 24 hours
                // Clear the stored data to prevent reuse
                clearDeferredLinkFromStorage()
                
                // Execute all pending handlers
                executeDeferredLinkHandlers(with: deferredData)
                return
            } else {
                // Clear expired data
                clearDeferredLinkFromStorage()
            }
        }
        
        // Check for app installation attribution
        checkInstallAttribution { [weak self] shortId in
            guard let self = self, let shortId = shortId else {
                self?.executeDeferredLinkHandlers(with: nil)
                return
            }
            
            // Fetch the deep link data
            self.fetchDeepLinkData(shortId: shortId) { data in
                DispatchQueue.main.async {
                    self.executeDeferredLinkHandlers(with: data)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Extract short ID from deep link URL
    private func extractShortId(from url: URL) -> String? {
        let pathComponents = url.pathComponents
        
        // Look for /r/{shortId} pattern
        if let rIndex = pathComponents.firstIndex(of: "r"),
           rIndex + 1 < pathComponents.count {
            return pathComponents[rIndex + 1]
        }
        
        // Look for shortId in query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if item.name == "shortId" || item.name == "id" {
                    return item.value
                }
            }
        }
        
        return nil
    }
    
    /// Fetch deep link data from server
    private func fetchDeepLinkData(shortId: String, completion: @escaping (DeepLinkData?) -> Void) {
        guard !baseURL.isEmpty else {
            print("DeepLinkingSDK: Base URL not configured")
            completion(nil)
            return
        }
        
        let urlString = "\(baseURL)/api/deferred-link/\(shortId)"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DeepLinkingSDK-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DeepLinkingSDK: Network error - \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                let deepLinkData = try JSONDecoder().decode(DeepLinkData.self, from: data)
                completion(deepLinkData)
            } catch {
                print("DeepLinkingSDK: JSON decode error - \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    /// Check UserDefaults for deferred link data stored by web page
    private func getDeferredLinkFromStorage() -> DeepLinkData? {
        // In iOS, we can't directly access localStorage from web views
        // But we can implement a custom URL scheme to receive the data
        // For now, we'll check UserDefaults for manually stored data
        
        guard let data = UserDefaults.standard.data(forKey: "deferred_deep_link") else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(DeepLinkData.self, from: data)
        } catch {
            print("DeepLinkingSDK: Failed to decode stored deferred link data")
            return nil
        }
    }
    
    /// Clear deferred link data from storage
    private func clearDeferredLinkFromStorage() {
        UserDefaults.standard.removeObject(forKey: "deferred_deep_link")
        UserDefaults.standard.removeObject(forKey: "deferred_deep_link_timestamp")
    }
    
    /// Check for app installation attribution using various methods
    private func checkInstallAttribution(completion: @escaping (String?) -> Void) {
        // Method 1: Check UIPasteboard for deferred link data (if implemented on web side)
        checkPasteboardForDeferredLink { shortId in
            if let shortId = shortId {
                completion(shortId)
                return
            }
            
            // Method 2: Check for custom URL scheme data
            // This would be set by the app delegate when handling custom URLs
            if let shortId = UserDefaults.standard.string(forKey: "pending_deferred_shortId") {
                UserDefaults.standard.removeObject(forKey: "pending_deferred_shortId")
                completion(shortId)
                return
            }
            
            // Method 3: Check for universal link data
            if let shortId = UserDefaults.standard.string(forKey: "universal_link_shortId") {
                UserDefaults.standard.removeObject(forKey: "universal_link_shortId")
                completion(shortId)
                return
            }
            
            completion(nil)
        }
    }
    
    /// Check UIPasteboard for deferred link data
    private func checkPasteboardForDeferredLink(completion: @escaping (String?) -> Void) {
        // Check if pasteboard contains deferred link data
        let pasteboard = UIPasteboard.general
        
        // Look for JSON data in pasteboard
        if let data = pasteboard.data(forPasteboardType: "public.json") {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let shortId = json["shortId"] as? String,
                   let timestamp = json["timestamp"] as? Double {
                    
                    // Check if the data is recent (within last 5 minutes)
                    let currentTime = Date().timeIntervalSince1970 * 1000
                    if currentTime - timestamp < 300000 { // 5 minutes
                        // Clear pasteboard to prevent reuse
                        pasteboard.items = []
                        completion(shortId)
                        return
                    }
                }
            } catch {
                // Ignore JSON parsing errors
            }
        }
        
        completion(nil)
    }
    
    /// Execute all pending deferred link handlers
    private func executeDeferredLinkHandlers(with data: DeepLinkData?) {
        for handler in deferredLinkHandlers {
            handler(data)
        }
        deferredLinkHandlers.removeAll()
    }
    
    /// Make API request to deep linking service
    private func makeAPIRequest(endpoint: String, 
                               method: String, 
                               body: [String: Any]? = nil,
                               queryItems: [URLQueryItem]? = nil,
                               completion: @escaping (Result<Data, SDKError>) -> Void) {
        
        guard let apiKey = apiKey else {
            completion(.failure(.notConfigured))
            return
        }
        
        var urlComponents = URLComponents(string: "\(baseURL)\(endpoint)")!
        if let queryItems = queryItems {
            urlComponents.queryItems = queryItems
        }
        
        guard let url = urlComponents.url else {
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("DeepLinkingSDK-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                completion(.failure(.invalidRequest))
                return
            }
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("DeepLinkingSDK: Network error - \(error.localizedDescription)")
                completion(.failure(.networkError))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(.networkError))
                return
            }
            
            guard let data = data else {
                completion(.failure(.noData))
                return
            }
            
            if httpResponse.statusCode == 401 {
                completion(.failure(.unauthorized))
                return
            } else if httpResponse.statusCode == 429 {
                completion(.failure(.rateLimited))
                return
            } else if httpResponse.statusCode >= 400 {
                completion(.failure(.serverError))
                return
            }
            
            completion(.success(data))
        }.resume()
    }
}

// MARK: - Data Models

/// SDK Error types
public enum SDKError: Error, LocalizedError {
    case notConfigured
    case invalidURL
    case invalidRequest
    case invalidResponse
    case networkError
    case unauthorized
    case rateLimited
    case serverError
    case noData
    
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SDK not configured. Call configure() first."
        case .invalidURL:
            return "Invalid URL provided"
        case .invalidRequest:
            return "Invalid request parameters"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network error occurred"
        case .unauthorized:
            return "Invalid API key or unauthorized access"
        case .rateLimited:
            return "API rate limit exceeded"
        case .serverError:
            return "Server error occurred"
        case .noData:
            return "No data received from server"
        }
    }
}

/// Created link data structure
public struct CreatedLinkData: Codable {
    public let linkId: String
    public let shortId: String
    public let shortUrl: String
    public let originalUrl: String
    public let customParameters: [String: String]
}

/// Create link response structure
struct CreateLinkResponse: Codable {
    let success: Bool
    let link: CreatedLinkData
    let usage: UsageInfo
}

/// Links response structure
public struct LinksResponse: Codable {
    public let links: [LinkInfo]
    public let pagination: PaginationInfo
    public let usage: UsageInfo
}

/// Link info structure
public struct LinkInfo: Codable {
    public let linkId: String
    public let shortId: String
    public let shortUrl: String
    public let title: String
    public let description: String?
    public let originalUrl: String
    public let isActive: Bool
    public let clickCount: Int
    public let createdAt: String
    public let customParameters: [CustomParameter]
}

/// Pagination info structure
public struct PaginationInfo: Codable {
    public let page: Int
    public let limit: Int
    public let total: Int
    public let pages: Int
}

/// Usage info structure
public struct UsageInfo: Codable {
    public let withinMonthlyLimit: Bool
    public let withinAnnualLimit: Bool
    public let monthlyUsage: Int
    public let monthlyLimit: Int
    public let annualUsage: Int
    public let annualLimit: Int
}

/// Deep link data structure
public struct DeepLinkData: Codable {
    public let linkId: String
    public let shortId: String
    public let title: String?
    public let description: String?
    public let originalUrl: String
    public let targetUrl: String
    public let appUrl: String
    public let platform: String
    public let customParameters: [CustomParameter]
    public let utmTags: UTMTags
    public let timestamp: Double
    
    /// Custom parameter structure
    public struct CustomParameter: Codable {
        public let key: String
        public let value: String
    }
    
    /// UTM tags structure
    public struct UTMTags: Codable {
        public let source: String?
        public let medium: String?
        public let campaign: String?
        public let term: String?
        public let content: String?
    }
    
    /// Get custom parameter value by key
    public func getCustomParameter(_ key: String) -> String? {
        return customParameters.first { $0.key == key }?.value
    }
    
    /// Get all parameters as dictionary
    public func getParametersDictionary() -> [String: String] {
        var params: [String: String] = [:]
        
        // Add UTM parameters
        if let source = utmTags.source { params["utm_source"] = source }
        if let medium = utmTags.medium { params["utm_medium"] = medium }
        if let campaign = utmTags.campaign { params["utm_campaign"] = campaign }
        if let term = utmTags.term { params["utm_term"] = term }
        if let content = utmTags.content { params["utm_content"] = content }
        
        // Add custom parameters
        for param in customParameters {
            params[param.key] = param.value
        }
        
        return params
    }
}

// MARK: - App Delegate Integration

/// Extension to help with AppDelegate integration
public extension DeepLinkingSDK {
    
    /// Call this from application(_:didFinishLaunchingWithOptions:)
    @objc func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        // Check for launch from URL
        if let url = launchOptions?[.url] as? URL {
            UserDefaults.standard.set(extractShortId(from: url), forKey: "pending_deferred_shortId")
        }
        
        // Check for universal link
        if let userActivity = launchOptions?[.userActivityDictionary] as? [String: Any],
           let activity = userActivity["UIApplicationLaunchOptionsUserActivityKey"] as? NSUserActivity,
           activity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = activity.webpageURL {
            UserDefaults.standard.set(extractShortId(from: url), forKey: "universal_link_shortId")
        }
    }
    
    /// Call this from application(_:open:options:)
    @objc func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if let shortId = extractShortId(from: url) {
            UserDefaults.standard.set(shortId, forKey: "pending_deferred_shortId")
            return true
        }
        return false
    }
    
    /// Call this from application(_:continue:restorationHandler:)
    @objc func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = userActivity.webpageURL,
           let shortId = extractShortId(from: url) {
            UserDefaults.standard.set(shortId, forKey: "universal_link_shortId")
            return true
        }
        return false
    }
}

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

@available(iOS 14.0, *)
public extension View {
    /// Handle deep links in SwiftUI
    func onDeepLink(perform action: @escaping (DeepLinkData?) -> Void) -> some View {
        self.onOpenURL { url in
            DeepLinkingSDK.shared.handleDeepLink(url) { data in
                action(data)
            }
        }
    }
    
    /// Check for deferred deep links on appear
    func onDeferredDeepLink(perform action: @escaping (DeepLinkData?) -> Void) -> some View {
        self.onAppear {
            DeepLinkingSDK.shared.checkForDeferredDeepLink { data in
                action(data)
            }
        }
    }
}
#endif

// MARK: - Usage Examples

/*
 
 // Example 1: Create an invite link
 DeepLinkingSDK.shared.createLink(
     baseURL: "https://invite.yourdomain.com",
     customParameters: [
         "url": "8c1596c",
         "redirecturl": "/mining"
     ],
     title: "Mining Invite",
     description: "Join our mining program"
 ) { result in
     switch result {
     case .success(let linkData):
         print("Created link: \(linkData.shortUrl)")
         // Use linkData.shortUrl for sharing
     case .failure(let error):
         print("Error: \(error.localizedDescription)")
     }
 }
 
 // Example 2: Handle deferred deep link after app installation
 DeepLinkingSDK.shared.checkForDeferredDeepLink { deepLinkData in
     guard let data = deepLinkData else { return }
     
     // Extract invite parameters
     let inviteCode = data.getCustomParameter("url")
     let redirectPath = data.getCustomParameter("redirecturl")
     
     // Navigate to the appropriate screen
     if let code = inviteCode, let path = redirectPath {
         navigateToInvite(code: code, redirectTo: path)
     }
 }
 
 */
