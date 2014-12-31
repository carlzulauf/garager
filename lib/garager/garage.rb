module Garager
  class Garage
    attr_accessor :pin, :presumed, :logger, :time_to_close, :time_to_hold

    def initialize(options = {})
      self.pin      = options.fetch(:pin, 4)
      self.presumed = options.fetch(:presumed, :closed)
      self.logger   = options.fetch(:logger){ Logger.new(STDOUT) }
      self.time_to_close = options.fetch(:time_to_close) { 12.0 }
      self.time_to_hold = options.fetch(:time_to_hold) { 0.5 }
    end

    def setup
      logger.info "Garage#setup"
      gpio "write #{pin} 1"
      gpio "mode #{pin} out"
      self
    end

    def toggle
      change_state(presumed)
      gpio "write #{pin} 0"
      sleep time_to_hold
      gpio "write #{pin} 1"
      self
    end

    def change_state(current)
      self.presumed = send(current)
      logger.info "Transitioning from #{current} to #{presumed}"
      self
    end

    def start_timer
      @timer_start = Time.now
      @timer_duration = time_to_close
      @timer_elapsed = 0
      @timer_thread = Thread.new { sleep_and_transition }
    end

    def interrupt_timer
      if @timer_thread.alive?
        @timer_thread.kill
        @timer_elapsed = Time.now - @timer_start
        @timer_duration = time_to_close - @timer_elapsed
      end
    end

    def resume_timer
      @timer_start = @timer_elapsed
      @timer_duration = @timer_elapsed
      @thread_timer = Thread.new { sleep_and_transition }
    end

    def sleep_and_transition
      sleep @timer_duration
      self.presumed = case presumed
      when :opening
        :opened
      when :closing
        :closed
      else
        presumed
      end
    end

    def opened
      start_timer
      :closing
    end

    def closed
      start_timer
      :opening
    end

    def partially_opened
      resume_timer
      :closing
    end

    def partially_closed
      resume_timer
      :opening
    end

    def opening
      interrupt_timer
      :partially_opened
    end

    def closing
      interrupt_timer
      :partially_closed
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
      change_state(presumed)
      self
    end
  end
end
