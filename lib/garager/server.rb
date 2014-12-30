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
      true
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
    end

    def register(options = {})
      puts "Registering: #{options.inspect}"
      device = Device.new(options)
      devices[device.key] = device if valid_key?(device.key)
      device.token
    end

    def listen(token)
      device = devices.values.detect { |d| d.token == token }
      if device
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

    class Shared
      def initialize(server)
        @server = server
      end

      def register(options = {})
        @server.register(options)
      end

      def listen(token)
        @server.listen(token).tap{ |r| puts r }
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
    end

  end
end
