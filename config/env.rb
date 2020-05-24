# stdlib stuff
require "securerandom"
require "logger"
require "yaml"

# o the gems
require "bundler/setup"
Bundler.require(:default)

require "active_support/core_ext"

GARAGER_ENV = ENV["GARAGER_ENV"] || "development"
CONFIG_DIR  = File.expand_path(File.dirname(__FILE__))
CONFIG_PATH = File.join(CONFIG_DIR, "#{GARAGER_ENV}.yaml")
ROOT_DIR    = File.expand_path(File.join(CONFIG_DIR, ".."))
LIB_DIR     = File.join(ROOT_DIR, "lib")
LOGGER      = Logger.new(STDOUT)

$LOAD_PATH.unshift LIB_DIR
require "garager"

Garager::ConfigBuilder.out(GARAGER_ENV) unless File.exist?(CONFIG_PATH)
CONFIG_DATA = YAML.load_file(CONFIG_PATH)

LOGGER.info "Starting with config: " + CONFIG_DATA.inspect
