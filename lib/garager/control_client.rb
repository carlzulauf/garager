require "resolv"
require "async/websocket/client"
require "async/http/endpoint"

module Garager
  class ControlClient < OptStruct.new
    def self.config_option(name, config_name: nil, default: nil)
      config_name ||= name.to_s
      option_writer(name)
      define_method(name) do
        options.fetch(name) do
          ENV.fetch("GARAGER_#{config_name.upcase}") do
            CONFIG_DATA.fetch(config_name, default)
          end
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
      debug "#init"
      @connected = false
      @outbox = nil
      @stop_signal = Thread::Queue.new
    end

    def start
      debug "#start"
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
          @stop_signal.pop(timeout: delay)
        end
      end
    end

    def connected?
      @connected
    end

    # Safe to call from any thread
    def stop
      debug "Attempting to disconnect control client", "stop"
      @running = false
      @stop_signal.push(:stop)
      @outbox&.push(:close)
    end

    def run
      debug "#run"
      Sync do |task|
        log "connecting to #{server_uri} from #{origin}", "run"
        Async::WebSocket::Client.connect(endpoint, headers: connection_headers) do |connection|
          @socket = connection
          @outbox = Thread::Queue.new
          @connected = true
          @subscribed = false
          writer = task.async { write_loop(connection) }
          while (message = connection.read)
            handle_message(message.to_str)
          end
          log "Connection closed by server"
        ensure
          @connected = false
          @subscribed = false
          @outbox&.close
          @outbox = nil
          writer&.stop
          @socket = nil
        end
      end
    # IOError (incl. EOFError) means the server dropped the connection, or we
    # closed it in #stop. Either way, #start decides whether to reconnect.
    rescue Protocol::WebSocket::ClosedError, IOError => e
      log "Connection closed. #{e.class}: #{e.message}"
    rescue Socket::ResolutionError => e
      log "Connection failed. #{e.class}: #{e.message}", level: :warn
      reset_resolver
    rescue StandardError => e
      log "Connection failed. #{e.class}: #{e.message}", level: :warn
      debug e.full_message
    end

    # Safe to call from any thread
    def update_status(name, value)
      update = { action: "update_status", name: name, value: value }.to_json
      send_message(command: "message", data: update, identifier: channel_id)
    end

    # Safe to call from any thread
    def update_status_image(name, path)
      data = [File.binread(path)].pack("m")
      update = {
        action: "update_status_image",
        name:   name,
        image:  data,
        ext:    File.extname(path).delete_prefix("."),
      }.to_json
      send_message(command: "message", data: update, identifier: channel_id)
    end

    private

    def log(msg, context = nil, level: :info)
      logger.send level, "ControlClient#{context ? "##{context}" : ""}: #{msg}"
    end

    def debug(msg, context = nil)
      log(msg, context, level: :debug)
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

    def handle_message(data)
      debug "Received message: #{data}", "handle_message"
      message = JSON.parse(data)
      case message["type"]
      when "welcome"
        send_message(subscription_message)
      when "ping"
        # Lets the server know we're still here. Pongs go through the channel,
        # so there's nowhere to send them until the subscription is confirmed.
        send_message(pong_message) if @subscribed
      when "confirm_subscription"
        @subscribed = true
        send_message(registration_message)
        # The server forgets statuses when it restarts, so resend them
        triggers.push([:registered])
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

    # All writes to the socket happen in this fiber, so other threads (and the
    # reader fiber) only ever push onto the outbox queue.
    def write_loop(connection)
      while (message = @outbox&.pop)
        if message == :close
          connection.close
          break
        end
        connection.write(Protocol::WebSocket::TextMessage.new(message))
        connection.flush
      end
    end

    # Async looks up hostnames with Resolv, whose default resolver keeps the DNS
    # settings it read from /etc/resolv.conf when it was loaded. If that was before
    # the network came up, every lookup fails until restart. Fresh resolvers read
    # the current settings.
    def reset_resolver
      Resolv::DefaultResolver.replace_resolvers([Resolv::Hosts.new, Resolv::DNS.new])
    end

    def endpoint
      Async::HTTP::Endpoint.parse(
        server_uri,
        protocol:    Async::HTTP::Protocol::HTTP11,
        ssl_context: ssl_context
      )
    end

    # Matches the previous behavior of not verifying the server's certificate
    def ssl_context
      OpenSSL::SSL::SSLContext.new.tap do |context|
        context.alpn_protocols = Async::HTTP::Protocol::HTTP11.names
        context.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE)
      end
    end

    def origin
      "#{http_scheme}://#{host}:#{port}"
    end

    def connection_headers
      {
        "origin" => origin,
        "authorization" => "Bearer #{jwt_token}"
      }
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
      debug message.length > 200 ? message.first(200) + " ... " : message, "send_message"
      outbox = @outbox
      if outbox
        outbox.push(message)
      else
        debug "Not connected. Dropping message.", "send_message"
      end
    rescue ClosedQueueError
      debug "Connection closed. Dropping message.", "send_message"
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
