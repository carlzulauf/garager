class GarageServer < Sinatra::Application
  set :root, File.expand_path(".")

  helpers do
    def current_garage
      @current_garage ||= Garager::Garage.current(logger: logger)
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
