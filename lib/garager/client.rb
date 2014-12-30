require 'timeout'
require 'drb/drb'

module Garager
  class Client
    class TimeoutError < StandardError; end

    attr_accessor :options

    def initialize(options = {})
      self.options = options
    end

    def uri
      options.fetch(:uri) { "druby://localhost:8787" }
    end

    def key
      options.fetch(:key) { "533e98315f3de22fc4006674285aa837" }
    end

    def garage
      @garage ||= options.fetch(:garage) { Garager::Garage.current }
    end

    def ip
      @ip ||= options.fetch(:ip) do
        Socket.ip_address_list.detect{ |ip| !ip.ipv4_loopback? }
      end
    end

    def logger
      @logger ||= options.fetch(:logger) { Logger.new(STDOUT) }
    end

    def name
      @name ||= options.fetch(:name) do
        name = `hostname`.chomp
        name << "|#{ip.ip_address}" if ip
        name
      end
    end

    def timeout
      options.fetch(:timeout) { 60 } # seconds
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
      logger.info "Received command: #{command}"
      case command
      when :open
        garage.toggle
      end
    end

    def listen
      loop do

        server = DRbObject.new_with_uri(uri)

        token = server.register(name: name, key: key)
        logger.info "Client token: #{token}"

        loop do
          success = with_timeout do
            handle_command server.listen(token)
          end
          break unless success
        end

      end
    end

  end
end
