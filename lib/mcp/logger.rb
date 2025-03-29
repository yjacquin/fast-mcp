# frozen_string_literal: true

module MCP
  class Logger < Logger
    class << self
      attr_accessor :log_path
    end

    self.log_path = "./logs/mcp-server.log" # Default value

    def initialize
      @client_initialized = false
      @transport = nil

      super(self.class.log_path, 'daily')

      # Keep a reference to stdout for JSON communication
      @stdout = $stdout
    end

    attr_accessor :transport, :client_initialized

    def send_json(data)
      # Use stdout directly for JSON communication
      @stdout.puts(JSON.generate(data))
      @stdout.flush
    end

    def client_initialized?
      client_initialized
    end
    
    def set_client_initialized
      @client_initialized = true
    end

    def stdio_transport?
      transport == :stdio
    end

    def rack_transport?
      transport == :rack
    end

    # Override add to ensure logs go to file only
    def add(severity, message = nil, progname = nil, &block)
      # Handle IO objects safely to avoid accidentally logging them
      message = safe_format(message) if message
      
      if block_given?
        original_message = yield
        message = safe_format(original_message)
      end
      
      super(severity, message, progname)
    end
    
    private
    
    # Safely format objects to avoid issues with IO objects
    def safe_format(obj)
      if obj.is_a?(IO) || obj.is_a?(StringIO)
        "IO:#{obj.object_id}"
      else
        obj
      end
    end
  end
end
