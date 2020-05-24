module Garager
  class Garage < OptStruct.new
    option :pin, 0
    option :presumed, :closed
    option :logger, -> { Logger.new(STDOUT) }
    option :last, 0.0
    option :triggers, -> { [] }
    option :capture_path, -> { default_capture_path } 

    def opened?
      !closed?
    end

    def closed?
      presumed == :closed
    end

    def action
      closed? ? "Open" : "Close"
    end
    
    def run(cmd)
      logger.info " $ #{cmd}"
      system cmd
    end

    def setup
      logger.info "Garage#setup"
      run "gpio write #{pin} 1"
      run "gpio mode #{pin} output"
      self
    end
    
    def capture
      logger.info "Garage#capture"
      run capture_cmd
      triggers.push([:status_image, :camera, capture_path])
    end
    
    def capture_cmd
      [
        "raspistill",
        "--width 640",
        "--height 480",
        "--nopreview",
        "--timeout 2000",
        "--quality 95",
        "--output #{capture_path}",
      ].join(" ")
    end
    
    def default_capture_path
      File.join(ROOT_DIR, "capture.jpg")
    end

    def max_frequency
      3.0 # seconds
    end

    def toggle
      ts = Time.now.to_f
      if ts - last > max_frequency
        logger.info "Garage#toggle. Presumed #{presumed}"
        run "gpio write #{pin} 0"
        sleep 0.5
        run "gpio write #{pin} 1"
        self.presumed = closed? ? :open : :closed
        self.last = ts
        self
      else
        logger.info "Garage#toggle. Throttled."
      end
    end

    def self.current(options = {})
      @@current ||= if GARAGER_ENV == "production"
                      Garage.new(options).setup
                    else
                      FakeGarage.new(options).setup
                    end
    end
  end

  class FakeGarage < Garage
    def setup
      logger.info "FakeGarage#setup"
      triggers.push([:status, :presumed_state, presumed])
      self
    end

    def toggle
      logger.info "FakeGarage#toggle. Presumed #{presumed}"
      self.presumed = presumed == :closed ? :open : :closed
      triggers.push([:status, :presumed_state, presumed])
      self
    end
  end
end
