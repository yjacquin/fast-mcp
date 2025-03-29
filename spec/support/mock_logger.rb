# frozen_string_literal: true

require 'logger'

module MCP
  # A mock logger for testing that doesn't write to any files
  class MockLogger
    def initialize
      @logs = []
      @client_initialized = false
      @transport = nil
      
      # Don't call super, just setup our own mock
      @level = Logger::INFO
    end

    attr_accessor :transport, :client_initialized, :level
    attr_reader :logs

    def info(message)
      @logs << { level: :info, message: message }
      nil
    end

    def debug(message)
      @logs << { level: :debug, message: message }
      nil
    end

    def warn(message)
      @logs << { level: :warn, message: message }
      nil
    end

    def error(message)
      @logs << { level: :error, message: message }
      nil
    end
    
    def fatal(message)
      @logs << { level: :fatal, message: message }
      nil
    end

    def client_initialized?
      client_initialized
    end

    def stdio_transport?
      transport == :stdio
    end

    def rack_transport?
      transport == :rack
    end
    
    def set_client_initialized
      @client_initialized = true
    end
    
    def send_json(data)
      # Mock implementation that doesn't actually send anything
      @logs << { level: :json, message: data }
      nil
    end
  end
end