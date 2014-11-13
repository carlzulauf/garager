class Garage
  attr_accessor :pin, :presumed, :logger

  def initialize(options = {})
    self.pin      = options.fetch(:pin, 4)
    self.presumed = options.fetch(:presumed, :closed)
    self.logger   = options.fetch(:logger){ Logger.new(STDOUT) }
  end

  def opened?
    !closed?
  end

  def closed?
    presumed == :closed
  end

  def action
    closed? ? "Open" : "Close"
  end

  def setup
    logger.info "Garage#setup"
    gpio "write #{pin} 1"
    gpio "mode #{pin} out"
    self
  end

  def toggle
    logger.info "Garage#toggle. Presumed #{presumed}"
    gpio "write #{pin} 0"
    sleep 0.5
    gpio "write #{pin} 1"
    self.presumed = presumed == :closed ? :open : :closed
    self
  end

  def gpio(cmd)
    `/usr/local/bin/gpio #{cmd}`
  end

  def self.current
    @@current ||= if defined?(REAL_GARAGE) && REAL_GARAGE
                    Garage.new.setup
                  else
                    FakeGarage.new.setup
                  end
  end
end

class FakeGarage < Garage
  def setup
    logger.info "FakeGarage#setup"
    self
  end

  def toggle
    logger.info "FakeGarage#toggle. Presumed #{presumed}"
    self.presumed = presumed == :closed ? :open : :closed
    self
  end
end
