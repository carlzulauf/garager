# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'garager/version'

Gem::Specification.new do |s|
  s.name          = "garager"
  s.version       = Garager::VERSION
  s.authors       = ["Carl Zulauf"]
  s.email         = ["carl@linkleaf.com"]
  s.summary       = %q{Opens your garage door}
  s.description   = %q{Opens your garage door using magic}
  s.homepage      = "http://github.com/carlzulauf/garager"
  s.license       = "MIT"

  s.files         = %w( Gemfile README.md LICENSE.txt garager.gemspec )
  s.files        += Dir.glob("lib/**/*")
  s.files        += Dir.glob("bin/*")
  s.require_paths = ["lib"]

  s.add_development_dependency "bundler", "~> 1.7"
  s.add_development_dependency "pry", "~> 0"
end
