# frozen_string_literal: true

module FastMcp
  module Transports
    # Base class for all MCP transports
    # This defines the interface that all transports must implement
    class BaseTransport
      attr_reader :server, :logger

      PROTOCOL_VERSION = FastMcp::Server::PROTOCOL_VERSION

      def initialize(server, logger: nil)
        @server = server
        @logger = logger || server.logger
      end

      # Start the transport
      # This method should be implemented by subclasses
      def start
        raise NotImplementedError, "#{self.class} must implement #start"
      end

      # Stop the transport
      # This method should be implemented by subclasses
      def stop
        raise NotImplementedError, "#{self.class} must implement #stop"
      end

      # Send a message to the client
      # This method should be implemented by subclasses
      def send_message(message)
        raise NotImplementedError, "#{self.class} must implement #send_message"
      end

      # Process an incoming message
      # This is a helper method that can be used by subclasses
      def process_message(message, headers: {})
        server.handle_request(message, headers: headers)
      end

      protected

      # Validate the MCP protocol version from headers
      def validate_protocol_version(headers)
        version = headers['mcp-protocol-version']
        return true if version.nil? || version.empty?

        unless version == PROTOCOL_VERSION
          @logger.warn("Unsupported protocol version: #{version}, expected: #{PROTOCOL_VERSION}")
          return false
        end

        true
      end

      # Create a protocol version error response
      def protocol_version_error_response(version = nil)
        message = version ? "Unsupported protocol version: #{version}" : 'Invalid protocol version'

        {
          jsonrpc: '2.0',
          error: {
            code: -32_000,
            message: message,
            data: { expected_version: PROTOCOL_VERSION }
          },
          id: nil
        }
      end
    end
  end
end
