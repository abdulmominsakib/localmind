#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint clipboard.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'clipboard'
  s.version          = '3.0.9'
  s.summary          = 'Flutter clipboard with text, Rich Text (HTML), and image support.'
  s.description      = <<-DESC
A super-power clipboard package for Flutter, with text, Rich text (HTML), and image support.
                       DESC
  s.homepage         = 'https://github.com/samuelezedi/flutter_clipboard'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'clipboard/Sources/clipboard/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end

