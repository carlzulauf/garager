# Minimal stand-in for the ActionCable control server. Accepts one device,
# subscribes it, then triggers a toggle. Logs every message it receives.
#
#   bundle exec ruby nix/tests/fake_cable.rb [port]

require "bundler/setup"
require "async"
require "async/http/server"
require "async/http/endpoint"
require "async/websocket/adapters/http"
require "json"

$stdout.sync = true
port = ARGV.fetch(0, 3333)
endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}")
identifier = { channel: "DevicesChannel" }.to_json

app = lambda do |request|
  Async::WebSocket::Adapters::HTTP.open(request) do |connection|
    puts "connected authorization=#{request.headers['authorization'].to_s[0, 20]}..."
    send = lambda do |message|
      connection.write(Protocol::WebSocket::TextMessage.new(message.to_json))
      connection.flush
    end
    send.({ type: "welcome" })
    while (message = connection.read)
      data = JSON.parse(message.to_str)
      inner = data["data"] ? JSON.parse(data["data"]) : {}
      summary = inner.except("capabilities").transform_values do |v|
        v.is_a?(String) && v.size > 40 ? "#{v[0, 10]}...(#{v.size} bytes)" : v
      end
      puts "received #{data['command']} #{summary.to_json}"
      if data["command"] == "subscribe"
        send.({ type: "confirm_subscription", identifier: identifier })
      elsif inner["action"] == "register"
        Async do
          sleep 3
          puts "triggering toggle"
          send.({ identifier: identifier, message: { type: "action", name: "toggle" } })
        end
      end
    end
    puts "disconnected"
  end || Protocol::HTTP::Response[404, {}, ["not a websocket request"]]
end

Async { Async::HTTP::Server.for(endpoint) { |request| app.call(request) }.run }
