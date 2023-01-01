module Garager
  class Garage < OptStruct.new
    options(
      pin:            0,
      last:           0.0,
      max_frequency:  5.0, # seconds
      presumed:       :closed,
      logger:         -> { Logger.new(STDOUT) },
      triggers:       -> { [] },
      command:        "bin/garage_toggle",
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
      stdout, status = Open3.capture2e(cmd)
      return true if status.success?

      logger.warn " -> Non-zero exit. STDOUT/STDERR: #{stdout.inspect}"
      false
    end

    def setup
      logger.info "Garage#setup"
      triggers.push([:status, :presumed_state, presumed])
      triggers.push([:status_image, :camera, capture])
    end

    def capture
      path = CONFIG_DATA["capture_path"]
      path && File.exist?(path) ? path : File.join(ROOT_DIR, "doc", "test.jpg")
    end

    def toggle
      ts = Time.now.to_f
      if ts - last > max_frequency
        to = closed? ? :open : :closed
        logger.info "Garage#toggle. Transitioning from #{presumed} to #{to}"
        run command
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
    option :command, default: "bin/fake_garage_toggle"

    def setup
      logger.info "FakeGarage#setup"
      triggers.push([:status, :presumed_state, presumed])
      triggers.push([:status_image, :camera, capture])
    end

    def toggle
      logger.info "FakeGarage#toggle. Presumed #{presumed}"
      run command
      self.presumed = closed? ? :open : :closed
      self.last = Time.now.to_f
    end
  end
end
