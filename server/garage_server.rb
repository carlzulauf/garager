class GarageServer < Sinatra::Application
  set :root, File.expand_path(".")

  helpers do
    def garage
      MyGarage
    end
  end

  get '/' do
    haml :index
  end

  post '/open' do
    garage.open
    redirect to('/')
  end
end
