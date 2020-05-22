require "bundler/setup"
require "pry"
require "garager"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
