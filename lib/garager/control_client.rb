module Garager
  class ControlClient < OptStruct.new
    def self.config_option(name, config_name: nil, default: nil)
      config_name ||= name.to_s
      option_writer(name)
      define_method(name) do
        options.fetch(name) do
          CONFIG_DATA.fetch(config_name, default)
        end
      end
    end

    config_option :device_id
    config_option :server_uri
    config_option :public_key
    config_option :private_key

    options(
      pong_interval:    15,
      seen_timeout:     -> { pong_interval * 2 },
      flagging_timeout: -> { pong_interval * 3 },
      reconnect_delays: -> { default_reconnect_delays },
      channel:          "DevicesChannel",
      agent:            "garager 2.0.0",
      triggers:         -> { [] },
      logger:           -> { Logger.new(STDOUT) }
    )

    attr_reader :socket

    init do
      log "#init"
      @connected = false
      @status_counter = 0
    end

    def start
      log "#start"
      @running = true
      reconnects = 0
      while @running
        last_started_at = Time.now
        run
        if @running
          if (Time.now - last_started_at) > (flagging_timeout + reconnect_delay(reconnects))
            reconnects = 0
          else
            reconnects += 1
          end
          delay = reconnect_delay(reconnects)
          log "Sleeping for #{delay} seconds before attempting reconnect"
          sleep delay
        end
      end
    end

    def stop
      log "Attempting to disconnect control client", "stop"
      EM.next_tick do
        @running = false
        socket&.close
      end
    end

    def run
      log "#run"
      EM.run do
        @socket = open_websocket_client
        socket.on(:open)    { @connected = true }
        socket.on(:message) { |event| handle_message(event) }
        socket.on(:close)   { |event| close_client(event) }
        socket.on(:error)   { |event| log event.message, "on(:error)"}
      end
    end

    def update_status(name, value)
      EM.next_tick do
        update = { action: "update_status", name: name, value: value }.to_json
        send_message(command: "message", data: update, identifier: channel_id)
      end
    end

    def update_status_image(name, path)
      EM.next_tick do
        data = Base64.encode64(File.read(path))
        update = {
          action: "update_status_image",
          name:   name,
          image:  data,
          ext:    Pathname(path).extname.from(1),
        }.to_json
        send_message(command: "message", data: update, identifier: channel_id)
      end
    end

    private

    def log(msg, context = nil)
      logger.info "ControlClient#{context ? "##{context}" : ""} [#{@connected.inspect}]: #{msg}"
    end

    def server_uri_object
      @server_uri_object ||= URI(server_uri)
    end

    def host
      server_uri_object.host
    end

    def http_scheme
      server_uri_object.scheme == "wss" ? "https" : "http"
    end

    def port
      server_uri_object.port
    end

    def handle_message(event)
      log "Received message: #{event.data}", "handle_message"
      message = JSON.parse(event.data)
      case message["type"]
      when "welcome"
        send_message(subscription_message)
      when "confirm_subscription"
        send_message(registration_message)
        # EM.add_periodic_timer(pong_interval / 2.0) { send_status }
      else
        if message["identifier"] == channel_id && message.key?("message")
          handle_trigger(message["message"])
        end
      end
    end

    def handle_trigger(data)
      case data["type"]
      when "action", "action_with_param"
        trigger_action(data["name"], data["param"])
      end
    end

    def trigger_action(action, param)
      log "Triggering #{action}: #{param.inspect}", "trigger_action"
      triggers.push([action, param].compact)
    end

    def close_client(event)
      log "Connection closed. Code: #{event.code}. Reason: #{event.reason}.", "close_client"
      @connected = false
      @socket = nil
      EM.stop_event_loop
    end

    def open_websocket_client
      origin = "#{http_scheme}://#{host}"
      origin += ":#{port}" if port
      log "connecting to #{server_uri} from #{origin}", "open_websocket_client"
      Faye::WebSocket::Client.new(
        server_uri,
        [],
        headers: {
          "Origin" => origin,
          "Authorization" => "Bearer #{jwt_token}"
        }
      )
    end

    def reconnect_delay(reconnects)
      return reconnect_delays.last if reconnects >= reconnect_delays.count
      reconnect_delays[reconnects]
    end

    def default_reconnect_delays
      [ 0.1, 1, 2, 5, 10, 15, 20, 30 ]
    end

    def channel_id
      @channel_id ||= { channel: channel }.to_json
    end

    def subscription_message
      { command: "subscribe", identifier: channel_id }
    end

    def registration_message
      { command: "message", data: registration_data, identifier: channel_id }
    end

    def registration_data
      {
        action:         "register",
        capabilities:   Capabilities.standard_garage,
        pong_interval:  pong_interval,
        seen_timeout:   seen_timeout
      }.to_json
    end

    def pong_message
      { command: "message", data: pong_data, identifier: channel_id }
    end

    def pong_data
      { action: "pong" }.to_json
    end

    def send_message(data)
      message = data.to_json
      log message.length > 200 ? message.first(200) + " ... " : message, "send_message"
      socket.send message
    end

    def jwt_token
      @jwt_token ||= JWT.encode(jwt_payload, private_key_object, "RS256")
    end

    def jwt_payload
      { sub: device_id, agent: agent }
    end

    def private_key_object
      OpenSSL::PKey::RSA.new(private_key)
    end
  end
end
