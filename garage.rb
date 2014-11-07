require 'pry'

class Garage
  attr_accessor :pin
  
  def initialize
    self.pin = 4
  end

  def setup
    `gpio write #{pin} 1`
    `gpio mode #{pin} out`
  end

  def open
    `gpio write #{pin} 0`
    sleep 0.5
    `gpio write #{pin} 1`
  end
end

garage = Garage.new
garage.setup
garage.open
sleep 2
garage.open

binding.pry

