module Garager
  class Garage
    attr_accessor :pin, :presumed, :logger, :last

    def initialize(options = {})
      self.pin      = options.fetch(:pin, 4)
      self.presumed = options.fetch(:presumed, :closed)
      self.logger   = options.fetch(:logger){ Logger.new(STDOUT) }
      self.last     = 0.0
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

    def max_frequency
      3.0 # seconds
    end

    def toggle
      ts = Time.now.to_f
      if ts - last > max_frequency
        logger.info "Garage#toggle. Presumed #{presumed}"
        gpio "write #{pin} 0"
        sleep 0.5
        gpio "write #{pin} 1"
        self.presumed = presumed == :closed ? :open : :closed
        self.last = ts
        self
      else
        logger.info "Garage#toggle. Throttled."
      end
    end

    def gpio(cmd)
      `/usr/local/bin/gpio #{cmd}`
    end

    def self.current(options = {})
      @@current ||= if defined?(REAL_GARAGE) && REAL_GARAGE
                      Garage.new(options).setup
                    else
                      FakeGarage.new(options).setup
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
end
