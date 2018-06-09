#
# Be sure to run `pod lib lint SwiftyCloudKit.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SwiftyCloudKit'
  s.version          = '0.1.5'
  s.summary          = 'A simple library for adding iCloud support.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
	SwiftyCloudKit is a thin layer above CloudKit which makes it easy to add cloud capabilities to Apple environments. 
                       DESC
  s.swift_version    = '4.2'  
  s.homepage         = 'https://github.com/simengangstad/SwiftyCloudKit'
  # s.screenshots    = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Simen Gangstad' => 'simen.gangstad@me.com' }
  s.source           = { :git => 'https://github.com/simengangstad/SwiftyCloudKit.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'
  # s.tvos.deployment_target = '10.0'
  # s.watchos.deployment_target = '3.0'
  # s.macos.deployment_target = '10.12'

  s.source_files = 'SwiftyCloudKit/Classes/**/*'
  
  # s.resource_bundles = {
  #   'SwiftyCloudKit' => ['SwiftyCloudKit/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit' 
  # s.dependency 'AFNetworking', '~> 2.3'
end
