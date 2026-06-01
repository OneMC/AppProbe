Pod::Spec.new do |s|
  s.name          = "AppProbe"
  s.version       = "1.0.0"
  s.platform      = :ios, '14.0'
  s.source_files  = 'Sources/**/*.swift'
  s.swift_version = '5.0'
  s.frameworks    = 'UIKit', 'Network'
  s.libraries     = 'sqlite3'

  s.dependency 'GCDWebServer', '~> 3.5'

  s.preserve_paths = ['skills/**/*', 'scripts/**/*']

  s.test_spec 'Tests' do |test|
    test.source_files = 'Tests/**/*.swift'
    test.requires_app_host = true
    test.frameworks = 'UIKit'
  end

  s.summary       = 'AI debug bridge server for iOS apps'
  s.description   = 'Embedded HTTP server that gives AI agents remote access to app runtime: view hierarchy, screenshots, sandbox files, and SQLite queries.'
  s.homepage      = 'git@github.com:OneMC/PhotoManager.git'
  s.license       = { :type => 'MIT', :file => 'LICENSE' }
  s.authors       = { 'MC' => 'mc' }
  s.source        = { :git => 'git@github.com:OneMC/PhotoManager.git', :tag => s.version.to_s }
end
