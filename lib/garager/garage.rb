module Garager
  class Garage < OptStruct.new
    options(
      pin:            0,
      last:           0.0,
      max_frequency:  3.0, # seconds
      presumed:       :closed,
      logger:         -> { Logger.new(STDOUT) },
      triggers:       -> { [] },
      capture_path:   -> { default_capture_path }
    )

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
      triggers.push([:status, :presumed_state, presumed])
      triggers.push([:status_image, :camera, capture])
    end

    def capture
      logger.info "Garage#capture"
      run capture_cmd
      capture_path
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

    def toggle
      ts = Time.now.to_f
      if ts - last > max_frequency
        to = closed? ? :open : :closed
        logger.info "Garage#toggle. Transitioning from #{presumed} to #{to}"
        run "gpio write #{pin} 0"
        sleep 0.5
        run "gpio write #{pin} 1"
        self.presumed = to
        self.last = ts
      else
        logger.info "Garage#toggle. Throttled."
      end
      presumed
    end

    def self.current(options = {})
      @@current ||= if GARAGER_ENV == "production"
                      Garage.new(options)
                    else
                      FakeGarage.new(options)
                    end
    end
  end

  class FakeGarage < Garage
    def setup
      logger.info "FakeGarage#setup"
      triggers.push([:status, :presumed_state, presumed])
      triggers.push([:status_image, :camera, capture])
    end

    def toggle
      logger.info "FakeGarage#toggle. Presumed #{presumed}"
      self.presumed = closed? ? :open : :closed
    end

    def capture
      logger.info "FakeGarage#capture"
      FileUtils.cp "/home/carl/Pictures/keeper-head.jpg", capture_path
      capture_path
    end
  end
end
