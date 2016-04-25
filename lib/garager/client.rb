require 'timeout'
require 'drb/drb'

module Garager
  class Client
    class TimeoutError < StandardError; end

    attr_accessor :options
    attr_reader :thread

    def initialize(options = {})
      self.options = options
    end

    def uri
      options.fetch(:uri) { "druby://localhost:8787" }
    end

    def key
      options.fetch(:key) do
        raise ArgumentError, "Missing required option: key"
      end
    end

    def garage_options
      options.merge(logger: logger)
    end

    def garage
      @garage ||= options.fetch(:garage) { Garager::Garage.current(garage_options) }
    end

    def ip
      @ip ||= options.fetch(:ip) do
        Socket.ip_address_list.detect{ |ip| !ip.ipv4_loopback? }
      end
    end

    def logger
      @logger ||= if path = options[:log]
        Logger.new(path)
      elsif options[:logger]
        options[:logger]
      else
        Logger.new(STDOUT)
      end
    end

    def name
      @name ||= options.fetch(:name) do
        name = `hostname`.chomp
        name << "|#{ip.ip_address}" if ip
        name
      end
    end

    def timeout
      options.fetch(:timeout) { 20 } # seconds
    end

    def with_timeout(&block)
      Timeout.timeout(timeout, TimeoutError, &block)
      true
    rescue DRb::DRbConnError, TimeoutError => e
      logger.error e.inspect
      sleep 5
      false
    end

    def handle_command(command)
      case command
      when :open
        garage.toggle
      end
    end

    def start
      @thread = Thread.new { listen }
      self
    end

    def listen
      loop do
        begin
          server = DRbObject.new_with_uri(uri)

          token = server.register(name: name, key: key)
          logger.info "Client token: #{token}"

          loop do
            success = with_timeout do
              handle_command server.listen(key, token)
            end
            break unless success
          end
        rescue DRb::DRbConnError => e
          logger.error e.inspect
          sleep 5
        end
      end
    end

    def inspect
      "#<Garager::Client:#{object_id}>"
    end

  end
end
