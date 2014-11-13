require_relative "environment"

class GarageServer < Sinatra::Application
  set :root, File.expand_path(".")

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

  get '/test' do
    haml "%h1 #{settings.root}"
  end
end
