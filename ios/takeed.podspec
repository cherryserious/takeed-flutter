Pod::Spec.new do |s|
  s.name             = 'takeed'
  s.version          = '1.0.0'
  s.summary          = 'Takeed push notifications for Flutter (APNs directly).'
  s.homepage         = 'https://github.com/cherryserious/takeed-flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Takeed' => 'https://github.com/cherryserious/takeed-flutter' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
