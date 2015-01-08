# Garager

Control your garage door (or any other device controlled by a simple relay) safely through your raspberry pi and your public, authenticated ruby app.

### Install server in your rails/sinatra/ruby app

Place the gem in your `Gemfile`

    gem 'garager', github: "carlzulauf/garager"

Create an instance of the garager server and start it. Give it some valid API keys your raspberry pi can use to connect later.

```ruby
MyGarage = Garager::Server.new(keys: ["VALID-API-KEY1"]).start
```

Somewhere in your rails/sinatra/ruby app you should open the garage.

```ruby
class AuthenticatedGarageController < ApplicationController
  def open
    MyGarage.open
  end
end
```

### Install client on Raspberry Pi

    sudo apt-get install git-core
    git clone git@github.com:carlzulauf/garager
    cd garager
    bin/install

This will also install the garager init script if successful. The garager client should auto-start on boot.

You will now need to configure the host and API key your pi will use to connect to your ruby server. A sample configuration file should have been generated in `config/client.yml`. Modify this with your server information.

You will need to restart the garager service after changing the config.

    sudo /etc/init.d/garager_init restart

