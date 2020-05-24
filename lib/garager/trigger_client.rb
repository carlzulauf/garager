class Garager::TriggerClient < OptStruct.new
  option :logger, -> { Logger.new(STDOUT) }
  option :image_interval, 30 # seconds
  attr_reader :control_client, :triggers, :garage

  init do
    @triggers = Queue.new
    @control_client = Garager::ControlClient.new(triggers: @triggers, logger: logger)
    @garage = Garager::Garage.current(triggers: @triggers, logger: logger)
  end

  def run
    @running = true
    @last_image_at = Time.now - image_interval
    start
    while @running
      begin
        name, *params = Timeout.timeout(control_client.pong_interval / 2.0) do
          name, *params = @triggers.pop
        end
        public_send(name, *params)
      rescue Timeout::Error
        if @last_image_at + image_interval < Time.now
          update_camera
        else
          update_presumed_state
        end
      end
    end
  end

  def update_camera
    status_image(:camera, garage.capture)
    @last_image_at = Time.now
  end

  def update_presumed_state
    status(:presumed_state, garage.presumed)
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
    sleep 10
    info "Updating camera to show completed garage action"
    update_camera
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

  def control_connect
    return if @control_thread && @control_thread.alive?
    @control_thread = Thread.new { control_client.start }
  end

  def info(msg)
    logger.info "TriggerClient: #{msg}"
  end
end