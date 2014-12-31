require 'bundler/setup'
Bundler.require(:default)

require 'logger'
require 'garager/server'

config = YAML.load_file("../config/server.yml")
MyGarage = Garager::Server.new(config).start
