# resolv (used by async) warns that IO::Buffer is experimental
Warning[:experimental] = false

# stdlib stuff
require "securerandom"
require "logger"
require "yaml"
require "open3"

# o the gems
require "bundler/setup"
Bundler.require(:default)

require "active_support/core_ext"

GARAGER_ENV = ENV["GARAGER_ENV"] || "development"
CONFIG_DIR  = ENV["GARAGER_CONFIG_DIR"] || File.expand_path(File.dirname(__FILE__))
CONFIG_PATH = File.join(CONFIG_DIR, "#{GARAGER_ENV}.yaml")
ROOT_DIR    = File.expand_path(File.join(File.dirname(__FILE__), ".."))
LIB_DIR     = File.join(ROOT_DIR, "lib")
STDOUT.sync = true
LOGGER      = Logger.new(STDOUT)
LOGGER.level = :info

$LOAD_PATH.unshift(LIB_DIR) unless $LOAD_PATH.member?(LIB_DIR)
require "garager"

Garager::ConfigBuilder.out(GARAGER_ENV) unless File.exist?(CONFIG_PATH)
CONFIG_DATA = YAML.load_file(CONFIG_PATH)
LOGGER.level = :debug if CONFIG_DATA["debug"] || ENV["GARAGER_DEBUG"]

Dir.chdir(ROOT_DIR) unless Dir.pwd == ROOT_DIR

LOGGER.debug "Starting with config: " + CONFIG_DATA.inspect
