$LOAD_PATH.unshift File.join(File.expand_path(File.dirname(__FILE__)), "lib")

require 'bundler/setup'
Bundler.require(:default)

REAL_GARAGE = !!(`uname -a` =~ /raspberrypi/)

require 'logger'
require 'garage'

class GarageServer < Sinatra::Application
  helpers do
    def current_garage
      @current_garage ||= Garage.current.tap { |g| g.logger = logger }
    end

    def escape_html(text)
      Rack::Utils.escape_html(text)
    end
  end

  get '/' do
    haml :index
  end

  post '/open' do
    current_garage.toggle
    redirect to('/')
  end
end
