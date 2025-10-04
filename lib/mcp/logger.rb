# frozen_string_literal: true

# This class is not used yet.
module FastMcp
  class Logger < Logger
    def initialize(transport: :stdio)
      @client_initialized = false
      @transport = transport

      # we don't want to log to stdout if we're using the stdio transport
      super($stdout) unless stdio_transport?
    end

    attr_accessor :transport, :client_initialized
    alias client_initialized? client_initialized

    def stdio_transport?
      transport == :stdio
    end

    def add(severity, message = nil, progname = nil, &block)
      return if stdio_transport? # we don't want to log to stdout if we're using the stdio transport

      # NOTE: MCP 2025-06-18 specifies structured logging via notifications/message
      # This basic implementation works for current use cases. Future enhancement:
      # send structured log messages as JSON-RPC notifications when client_initialized
      super
    end

    def rack_transport?
      transport == :rack
    end
  end
end
