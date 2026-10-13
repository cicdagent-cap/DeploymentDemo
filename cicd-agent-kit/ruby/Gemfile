source "https://rubygems.org"

gem "fastlane"

# Load fastlane plugins (includes fastlane-plugin-firebase_app_distribution)
plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
