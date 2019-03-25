$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "clerk_rails/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "clerk_rails"
  spec.version     = ClerkRails::VERSION
  spec.authors     = ["Colin Sidoti", "Braden Sidoti"]
  spec.email       = ["hello@clerk.dev"]
  spec.summary     = "Initializes the Clerk environment for Rails"
  spec.license     = "MIT"

  spec.files = Dir["{app,config,db,lib}/**/*", "LICENSE.txt", "Rakefile", "README.md"]

  spec.add_dependency "rails", "~> 5.2.0"
  spec.add_dependency "bcrypt"
  spec.add_dependency "ngrok-tunnel"
  spec.add_dependency "faraday"
  spec.add_dependency "faraday_middleware"
  spec.add_dependency "rubyzip"
end
