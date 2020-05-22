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

    config_option :id, config_name: "device_id"
    config_option :websocket_scheme, default: "ws"
    config_option :http_scheme, default: "http"
    config_option :host, config_name: "websocket_host"
    config_option :path, config_name: "websocket_path"

    options(
      private_key:      -> { config_private_key },
      pong_interval:    10,
      seen_timeout:     -> { pong_interval * 2 },
      flagging_timeout: 30,
      reconnect_delays: -> { default_reconnect_delays },
      channel:          "DevicesChannel",
      agent:            "garager 2.0.0",
      triggers:         -> { [] }
    )

    attr_reader :socket

    init do
      @connected = false
    end

    def start
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
          puts "Sleeping for #{delay} seconds before attempting reconnect"
          sleep delay
        end
      end
    end

    def stop
      puts "Attempting to disconnect control client"
      EM.next_tick do
        @running = false
        socket&.close
      end
    end

    def run
      EM.run do
        @socket = open_websocket_client
        socket.on(:open)    { @connected = true }
        socket.on(:message) { |event| handle_message(event) }
        socket.on(:close)   { |event| close_client(event) }
      end
    end

    def update_status(name, value)
      EM.next_tick do
        update = { action: "update_status", name: name, value: value }.to_json
        send_message(command: "message", data: update, identifier: channel_id)
      end
    end

    def add_to_output_stream(name, chunk)
      EM.next_tick do
        update = { action: "add_to_output_stream", name: name, chunk: chunk }.to_json
        send_message(command: "message", data: update, identifier: channel_id)
      end
    end

    private

    def handle_message(event)
      puts "Received message: #{event.data}"
      message = JSON.parse(event.data)
      case message["type"]
      when "welcome"
        send_message(subscription_message)
      when "confirm_subscription"
        send_message(registration_message)
        EM.add_periodic_timer(pong_interval) { send_message(pong_message) }
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
      puts "Triggering #{action}: #{param.inspect}"
      triggers.push([action, param])
    end

    def close_client(event)
      puts "Connection closed. Code: #{event.code}. Reason: #{event.reason}."
      @connected = false
      @socket = nil
      EM.stop_event_loop
    end

    def open_websocket_client
      Faye::WebSocket::Client.new(
        "#{websocket_scheme}://#{host}#{path}",
        [],
        headers: {
          "Origin" => "#{http_scheme}://#{host}",
          "Authorization" => "Bearer #{jwt_token}"
        }
      )
    end

    def reconnect_delay(reconnects)
      return reconnect_delays.last if reconnects >= reconnect_delays.count
      reconnect_delays[reconnects]
    end

    def default_reconnect_delays
      [ 0, 1, 2, 5, 10, 15, 20, 30 ]
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
        capabilities:   Capabilities.all,
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
      puts "Sending: #{message}"
      socket.send message
    end

    def jwt_token
      @jwt_token ||= JWT.encode(jwt_payload, private_key, "RS256")
    end

    def jwt_payload
      {
        sub:    "minecraft_server",
        agent:  agent,
      }
    end

    def config_private_key
      OpenSSL::PKey::RSA.new CONFIG["device_private_key"]
    end
  end
end
