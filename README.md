# Deep Linking SDK for iOS

A powerful and easy-to-use iOS SDK for handling deep links and deferred deep links in your mobile applications.

## Features

- ✅ Handle incoming deep links (custom schemes and universal links)
- ✅ Deferred deep linking (links work even when app is not installed)
- ✅ Support for UTM parameters and custom parameters
- ✅ iOS 13.0+ compatibility with latest Xcode
- ✅ SwiftUI and UIKit support
- ✅ Lightweight with no external dependencies
- ✅ Thread-safe implementation
- ✅ Comprehensive error handling

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/EvolaLabs/deeplink-ios-sdk.git", from: "1.0.0")
]
```

Or add it through Xcode:
1. File → Add Package Dependencies
2. Enter the repository URL
3. Select version and add to target

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'DeepLinkingSDK', '~> 1.0'
```

### Manual Installation

1. Download the `DeepLinkingSDK.swift` file
2. Drag and drop it into your Xcode project
3. Make sure to add it to your target

## Quick Start

### 1. Configure the SDK

In your `AppDelegate.swift` or `SceneDelegate.swift`:

```swift
import DeepLinkingSDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Configure the SDK with your deep linking service
    DeepLinkingSDK.shared.configure(
        baseURL: "https://your-domain.com",
        apiKey: "your-api-key" // Optional
    )
    
    // Handle app launch from deep link
    DeepLinkingSDK.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    return true
}
```

### 2. Handle Deep Links

#### For UIKit:

```swift
// In your AppDelegate
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return DeepLinkingSDK.shared.application(app, open: url, options: options)
}

func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    return DeepLinkingSDK.shared.application(application, continue: userActivity, restorationHandler: restorationHandler)
}

// In your view controller
override func viewDidLoad() {
    super.viewDidLoad()
    
    // Check for deferred deep links
    DeepLinkingSDK.shared.checkForDeferredDeepLink { [weak self] deepLinkData in
        guard let data = deepLinkData else { return }
        
        // Handle the deep link data
        self?.handleDeepLink(data)
    }
}

private func handleDeepLink(_ data: DeepLinkData) {
    print("Received deep link: \(data.title ?? "Unknown")")
    print("Target URL: \(data.targetUrl)")
    print("UTM Source: \(data.utmTags.source ?? "None")")
    
    // Navigate to the appropriate screen
    // Example: navigate to product detail page
    if let productId = data.getCustomParameter("product_id") {
        navigateToProduct(id: productId)
    }
}
```

#### For SwiftUI:

```swift
import SwiftUI
import DeepLinkingSDK

@main
struct MyApp: App {
    init() {
        // Configure the SDK
        DeepLinkingSDK.shared.configure(
            baseURL: "https://your-domain.com",
            apiKey: "your-api-key"
        )
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onDeepLink { deepLinkData in
                    // Handle incoming deep link
                    handleDeepLink(deepLinkData)
                }
                .onDeferredDeepLink { deepLinkData in
                    // Handle deferred deep link
                    handleDeepLink(deepLinkData)
                }
        }
    }
    
    private func handleDeepLink(_ data: DeepLinkData?) {
        guard let data = data else { return }
        
        // Handle the deep link
        print("Deep link received: \(data.title ?? "Unknown")")
    }
}
```

### 3. Configure URL Schemes

Add your custom URL scheme to your `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.yourapp.deeplink</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>yourapp</string>
        </array>
    </dict>
</array>
```

### 4. Configure Universal Links

Add associated domains to your app's entitlements:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
    <string>applinks:your-domain.com</string>
</array>
```

## API Reference

### DeepLinkingSDK

#### Configuration

```swift
func configure(baseURL: String, apiKey: String? = nil)
```

Configure the SDK with your deep linking service details.

#### Deep Link Handling

```swift
func handleDeepLink(_ url: URL, completion: @escaping (DeepLinkData?) -> Void)
```

Handle an incoming deep link URL.

```swift
func checkForDeferredDeepLink(completion: @escaping (DeepLinkData?) -> Void)
```

Check for deferred deep links (call on app launch).

### DeepLinkData

The `DeepLinkData` struct contains all information about a deep link:

```swift
public struct DeepLinkData {
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
}
```

#### Helper Methods

```swift
// Get custom parameter by key
func getCustomParameter(_ key: String) -> String?

// Get all parameters as dictionary
func getParametersDictionary() -> [String: String]
```

## Advanced Usage

### Custom Parameter Handling

```swift
DeepLinkingSDK.shared.checkForDeferredDeepLink { deepLinkData in
    guard let data = deepLinkData else { return }
    
    // Access UTM parameters
    let utmSource = data.utmTags.source
    let utmCampaign = data.utmTags.campaign
    
    // Access custom parameters
    let productId = data.getCustomParameter("product_id")
    let categoryId = data.getCustomParameter("category_id")
    
    // Get all parameters as dictionary
    let allParams = data.getParametersDictionary()
    
    // Handle navigation based on parameters
    if let productId = productId {
        navigateToProduct(id: productId)
    } else if let categoryId = categoryId {
        navigateToCategory(id: categoryId)
    }
}
```

### Error Handling

The SDK includes comprehensive error handling and logging:

```swift
// Enable debug logging (in development)
#if DEBUG
print("DeepLinkingSDK: Debug mode enabled")
#endif
```

### Thread Safety

All completion handlers are called on the main thread, making it safe to update UI directly:

```swift
DeepLinkingSDK.shared.checkForDeferredDeepLink { deepLinkData in
    // This is called on the main thread
    DispatchQueue.main.async {
        // Update UI here
        self.updateUI(with: deepLinkData)
    }
}
```

## Testing

### Testing Deep Links in Simulator

1. Open Safari in the simulator
2. Navigate to your deep link URL (e.g., `yourapp://product/123`)
3. Tap "Open" when prompted

### Testing Universal Links

1. Send yourself an iMessage or email with the universal link
2. Tap the link to test the universal link flow

### Testing Deferred Deep Links

1. Uninstall your app
2. Click a deep link in Safari
3. Install the app from the App Store
4. Launch the app - it should handle the deferred deep link

## Requirements

- iOS 13.0+
- Xcode 12.0+
- Swift 5.5+

## License

MIT License - see LICENSE file for details.

## Support

For issues and questions, please visit our GitHub repository or contact support.
