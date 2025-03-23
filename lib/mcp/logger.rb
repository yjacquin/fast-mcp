# frozen_string_literal: true

# This class is not used yet.
module MCP
  class Logger < Logger
    def initialize
      @client_initialized = false
      @transport = nil

      super($stdout)
    end

    attr_accessor :transport, :client_initialized

    def client_initialized?
      client_initialized
    end

    def stdio_transport?
      transport == :stdio
    end

    def rack_transport?
      transport == :rack
    end

    # def add(severity, message = nil, progname = nil, &block)
    #   # return unless client_initialized? && rack_transport?

    #   super
    # end
  end
end
