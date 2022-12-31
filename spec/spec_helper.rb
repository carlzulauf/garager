# stdlib stuff
require "securerandom"
require "logger"
require "yaml"
require "open3"

# o the gems
require "bundler/setup"
Bundler.require(:default)
require "pry"

GARAGER_ENV = "test"
ROOT_DIR    = File.expand_path(File.join(File.dirname(__FILE__), ".."))
CONFIG_DIR  = File.join(ROOT_DIR, "config")
CONFIG_PATH = File.join(CONFIG_DIR, "#{GARAGER_ENV}.yaml")
LIB_DIR     = File.join(ROOT_DIR, "lib")

LOG_DIR = File.join(ROOT_DIR, "log")
FileUtils.mkdir(LOG_DIR) unless File.exist?(LOG_DIR)
LOGGER = Logger.new(File.join(LOG_DIR, "test.log"))

require "garager"

Garager::ConfigBuilder.out(GARAGER_ENV) unless File.exist?(CONFIG_PATH)
CONFIG_DATA = YAML.load_file(CONFIG_PATH)

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
