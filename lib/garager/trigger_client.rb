class Garager::TriggerClient < OptStruct.new
  option :logger, -> { Logger.new(STDOUT) }
  option :image_interval, 30 # seconds
  option :status_interval, 30 # seconds
  attr_reader :control_client, :triggers, :garage, :timer

  init do
    @triggers = Queue.new
    @control_client = Garager::ControlClient.new(triggers: @triggers, logger: logger)
    @garage = Garager::Garage.current(triggers: @triggers, logger: logger)
  end

  def run
    @running = true
    @last_image_at = Time.now - image_interval
    @last_status_at = Time.now - status_interval
    start
    while @running
      begin
        name, *params = Timeout.timeout(1.0) do
          name, *params = @triggers.pop
        end
        public_send(name, *params)
      rescue Timeout::Error
        update_camera if @last_image_at + image_interval < Time.now
        update_presumed_state if @last_status_at + status_interval < Time.now
      end
    end
  end

  def update_camera
    return if @last_image_at && garage.test_image?
    status_image(:camera, garage.capture)
    @last_image_at = Time.now
  end

  def update_presumed_state
    status(:presumed_state, garage.presumed)
    @last_status_at = Time.now
  end

  def trigger_stop
    @triggers.push([:stop])
  end

  def status(name, value)
    control_client.update_status(name, value)
  end

  def status_image(name, path)
    control_client.update_status_image(name, path)
  end

  def toggle
    status(:presumed_state, garage.toggle)
    info "Updating camera for start of garage action"
    update_camera
    unless @camera_timer and @camera_timer.alive?
      @camera_timer = Thread.new do
        sleep 10
        if Time.now - @last_image_at > 10
          info "Updating camera to show completed garage action"
          update_camera
        end
      end
    end
  end

  def stop
    @running = false
    control_client&.stop
    @control_thread&.join
  end

  def start
    control_connect
    sleep 2
    garage.setup
  end

  def air_out
    toggle
    trigger_toggle_in(300)
  end

  def delayed_toggle(minutes_str)
    minutes = minutes_str.to_f
    trigger_toggle_in(minutes * 60) if minutes.positive?
  end

  private

  def trigger_toggle_in(seconds)
    if @timer && @timer.alive?
      info "Unable to schedule toggle. Timer already running."
    else
      info "Triggering toggle in #{seconds} seconds"
      @timer = Thread.new do
        sleep seconds
        @triggers.push([:toggle])
      end
    end
  end

  def control_connect
    return if @control_thread && @control_thread.alive?
    @control_thread = Thread.new { control_client.start }
  end

  def info(msg)
    logger.info "TriggerClient: #{msg}"
  end
end
