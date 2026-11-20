Pod::Spec.new do |s|
  s.name             = 'Akwelo'
  s.version          = '0.1.0'
  s.summary          = 'Akwelo identity verification: hosted selfie capture in a WKWebView.'
  s.homepage         = 'https://github.com/akwelo/akwelo-sdks'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Akwelo' => 'dev@akwelo.com' }
  s.source           = { :git => 'https://github.com/akwelo/akwelo-sdks.git', :tag => "ios-v#{s.version}" }
  s.ios.deployment_target = '14.0'
  s.swift_version    = '5.9'
  s.source_files     = 'ios/Sources/Akwelo/**/*.swift'
  s.frameworks       = 'WebKit', 'AVFoundation', 'DeviceCheck', 'CryptoKit'
end
