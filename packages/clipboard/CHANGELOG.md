## 3.0.14

* **Swift Package Manager Support**: Migrated iOS and macOS plugins from CocoaPods to Swift Package Manager (SPM) for better compatibility and future-proofing.
* **Dual Support**: Plugin now supports both CocoaPods (via updated podspec) and Swift Package Manager, ensuring backward compatibility.
* **Modern Package Structure**: Reorganized plugin structure to follow Swift Package Manager conventions with `Package.swift` files.
* **CocoaPods Compatibility**: Updated podspec files to work with new SPM structure while maintaining CocoaPods support.

## 3.0.10

* **Web Rich Text Copy Fix**: Added web implementation for `copyRichText` using ClipboardItem API to properly copy both text and HTML formats.
* **iOS Rich Text Copy Fix**: Fixed iOS HTML clipboard copy to use `setItems` with Data objects for proper HTML preservation.
* **Android Image Copy Fix**: Fixed Android image copy to use MediaStore API instead of FileProvider for better compatibility.
* **Plugin Structure Fix**: Moved all native code from example folder to proper plugin directories for correct plugin registration.
* **iOS AppDelegate Cleanup**: Removed manual plugin registration from example iOS app to prevent crashes.

## 3.0.9

* **Windows Platform Support**: Added complete Windows platform support with native C++ implementation.
* **Windows Clipboard Operations**: Full support for copy/paste of text, rich text (HTML), and images on Windows.
* **Windows Image Support**: Implemented PNG image copy/paste using GDI+ for conversion between PNG and DIB formats.
* **Windows Rich Text**: Added HTML Format clipboard support for rich text operations on Windows.
* **Cross-Platform Coverage**: Package now supports Android, iOS, Web, and Windows platforms with consistent API.

## 3.0.8

* **Code Formatting**: Improved code formatting and readability with better line breaks and consistent formatting.
* **Code Quality**: Removed trailing whitespace and fixed indentation issues for better code maintainability.

## 3.0.7

* **Fixed JSString Type Issues**: Fixed type compatibility issues in web clipboard implementation by properly converting Dart Strings to JSString for type comparisons.
* **Analyzer Fixes**: Resolved all static analysis warnings and errors for pub.dev compliance.
* **Code Cleanup**: Removed unnecessary imports and fixed analysis configuration issues.

## 3.0.6

* **Web Package Migration**: Migrated from `dart:html` and `dart:js_util` to the new `package:web` package for better compatibility and modern JS interop.
* **Conditional Import Update**: Changed conditional import from `dart.library.html` to `dart.library.js` to align with the new web package.
* **JS Interop Improvements**: Updated web clipboard implementation to use modern JS interop APIs (`dart:js_interop`) for better type safety and performance.

## 3.0.5

* **Web Clipboard Fixes**: Added full web support for copy/paste of text, rich text (HTML), and images using the browser Clipboard API with conditional imports.
* **Web Image Copy/Paste**: Implemented web-side image handling with `ClipboardItem`/`navigator.clipboard` for copy and `read`/`getType` for paste.
* **Web Text/Rich Text Paste**: Added `readText` and HTML extraction via `read()` + `getType('text/html')`.
* **Example App**: Updated to avoid early clipboard reads; paste dialogs no longer show on launch.
* **Lint/Build**: Resolved analyzer issues after web additions.

## 3.0.0

* **Major Release**: Complete rewrite with platform channel support for true multi-format clipboard
* **Platform Channels**: Added native Android (Kotlin) and iOS (Objective-C) implementations for enhanced features
* **True Rich Text Support**: HTML clipboard support now works via platform channels, not just in-memory storage
* **Image Support**: Full image copy/paste support for PNG images on Android and iOS
* **Native Clipboard Monitoring**: Real-time clipboard change detection using platform APIs (Android clipboard listeners, iOS notification center)
* **Memory Management**: Fixed listener memory leaks by using Set instead of List and adding cleanup mechanisms
* **Enhanced Error Handling**: Improved error handling with graceful fallbacks to Flutter's Clipboard API
* **Better Listener Management**: `addListener()` now returns a cleanup function, added `removeAllListeners()` method
* **New Methods**: Added `copyImage()` and `pasteImage()` for direct image clipboard operations
* **Production Ready**: Comprehensive fallback mechanisms ensure reliability across all platforms
* **Documentation**: Updated README with accurate feature descriptions, image examples, and platform setup instructions
* **Code Quality**: Improved code structure, better separation of concerns, and comprehensive error handling
* **Breaking Changes**: This is a major version bump due to significant architectural improvements and platform channel integration

## 2.0.2

* **Major Improvements**: Complete rewrite with platform channel support for true multi-format clipboard
* **Platform Channels**: Added native Android (Kotlin) and iOS (Swift) implementations for enhanced features
* **True Rich Text Support**: HTML clipboard support now works via platform channels, not just in-memory storage
* **Image Support**: Full image copy/paste support for PNG images on Android and iOS
* **Native Clipboard Monitoring**: Real-time clipboard change detection using platform APIs (Android clipboard listeners)
* **Memory Management**: Fixed listener memory leaks by using Set instead of List and adding cleanup mechanisms
* **Enhanced Error Handling**: Improved error handling with graceful fallbacks to Flutter's Clipboard API
* **Better Listener Management**: `addListener()` now returns a cleanup function, added `removeAllListeners()` method
* **New Methods**: Added `copyImage()` and `pasteImage()` for direct image clipboard operations
* **Production Ready**: Comprehensive fallback mechanisms ensure reliability across all platforms
* **Documentation**: Updated README with accurate feature descriptions, image examples, and platform setup instructions
* **Code Quality**: Improved code structure, better separation of concerns, and comprehensive error handling

## 2.0.0

* **Major Release**: Fixed naming conflicts and improved API consistency
* **Class Renaming**: Renamed `ClipboardData` to `EnhancedClipboardData` to avoid conflicts with Flutter's built-in `ClipboardData`
* **API Improvements**: Better separation between Flutter's native clipboard API and enhanced features
* **Bug Fixes**: Fixed all compilation errors and linter issues

## 1.0.0

* **Major Release**: Complete rewrite with enhanced functionality
* **SDK Update**: Updated to Dart SDK >=3.0.0 <4.0.0
* **Rich Text Support**: Added `copyRichText()` and `pasteRichText()` methods
* **Multiple Format Copy**: Added `copyMultiple()` for copying multiple data formats
* **Clipboard Monitoring**: Added real-time clipboard change detection with `addListener()`, `startMonitoring()`, and `stopMonitoring()`
* **Enhanced Error Handling**: Custom `ClipboardException` class with error codes
* **Utility Methods**: Added `hasData()`, `isEmpty()`, `getContentType()`, `getDataSize()`, `isValidInput()`, and `clear()`
* **Callback Support**: Added `copyWithCallback()` with success and error callbacks
* **Debug Information**: Added `getDebugInfo()` for comprehensive debugging
* **Testing Support**: Added `setMockData()` for testing scenarios
* **ClipboardData Class**: New data class with rich information about clipboard content
* **ClipboardContentType Enum**: Enum for identifying clipboard content types
* **Backward Compatibility**: All original methods (`copy`, `paste`, `controlC`, `controlV`) still supported
* **Improved Documentation**: Comprehensive README with examples for all features
* **Enhanced Example App**: Complete demo showcasing all new features

## 0.1.3

* Added null safety

## 0.1.2+8

* Fixed bug in clipboard class
* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+7

* Fixed bug in clipboard class
* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+6

* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+5

* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+4

* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+3

* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+2

* No major changes, edited readme, changelog, pubspec.yaml.

## 0.1.2+1

* No major changes, just a few tweaks in readme, changelog.

## 0.1.2

* No major changes, just a few tweaks in readme, changelog, example director etc.

## 0.1.1

* First release
* User can Copy from clipboard
* User can Paste from cliboard,