require 'drb/drb'

module Garager
  class Server

    attr_accessor :options
    attr_reader :shared, :devices

    def initialize(options = {})
      self.options = options
      @shared = Shared.new(self)
      @devices = {}
    end

    def valid_key?(key)
      keys.member?(key)
    end

    def keys
      options.fetch(:keys) do
        logger.error "No valid API keys are configured for Garager::Server"
        []
      end
    end

    def uri
      options.fetch(:uri) { "druby://:8787" }
    end

    def timeout
      options.fetch(:timeout) { 15 }
    end

    def logger
      @logger ||= options.fetch(:logger) { Logger.new(STDOUT) }
    end

    def client
      Thread.current['DRb']['client']
    end

    def start
      DRb.start_service(uri, shared)
      self
    end

    def stop
      DRb.stop_service
      self
    end

    def register(options = {})
      logger.info "Registering: #{options.inspect}"
      device = Device.new(options)
      if valid_key?(device.key)
        devices[device.key] = device
        device.token
      else
        client.close
      end
    end

    def listen(key, token)
      device = devices[key]
      if device && device.token == token
        Timeout.timeout(timeout) { device.pop }
      else
        logger.info "Unauthorized: #{token.inspect}"
        client.close
      end
    rescue Timeout::Error
      :tick
    end

    def open
      devices.values.each(&:open)
    end

    def inspect
      "#<Garager::Server:#{object_id}>"
    end

    class Shared
      def initialize(server)
        @server = server
      end

      def register(options = {})
        @server.register(options)
      end

      def listen(key, token)
        @server.listen(key, token)
      end
    end

    class Device
      attr_accessor :options, :queue, :seen
      attr_reader :token

      def initialize(options = {})
        self.options = options
        self.queue   = Queue.new
        self.seen    = Time.now
        @token = SecureRandom.hex
      end

      def name
        options[:name]
      end

      def key
        options[:key]
      end

      def pop
        self.seen = Time.now
        queue.pop
      end

      def open
        queue.push :open
      end

      def inspect
        "#<Garager::Server::Device:#{object_id} queue:#{queue.count}>"
      end
    end

  end
end
