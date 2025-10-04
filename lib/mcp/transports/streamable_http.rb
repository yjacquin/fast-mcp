# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'rack'
require_relative 'base_transport'
require_relative '../protocol_version'
require_relative 'concurrency_adapter'

module FastMcp
  module Transports
    # StreamableHTTP transport for MCP 2025-06-18 specification
    # This transport implements the unified HTTP endpoint with POST/GET support
    # and optional Server-Sent Events streaming as per MCP specification
    class StreamableHttpTransport < BaseTransport # rubocop:disable Metrics/ClassLength
      DEFAULT_PATH = '/mcp'
      DEFAULT_ALLOWED_ORIGINS = ['localhost', '127.0.0.1', '[::1]'].freeze
      DEFAULT_ALLOWED_IPS = ['127.0.0.1', '::1', '::ffff:127.0.0.1'].freeze
      SERVER_ENV_KEY = 'fast_mcp.server'

      # StreamableHTTP implements MCP 2025-06-18 specification
      PROTOCOL_VERSION = Protocol::VERSION

      # Required headers for MCP 2025-06-18
      REQUIRED_ACCEPT_HEADERS = ['application/json', 'text/event-stream'].freeze
      SSE_CONTENT_TYPE = 'text/event-stream'
      JSON_CONTENT_TYPE = 'application/json'

      SSE_HEADERS = {
        'Content-Type' => SSE_CONTENT_TYPE,
        'Cache-Control' => 'no-cache, no-store, must-revalidate',
        'Connection' => 'keep-alive',
        'X-Accel-Buffering' => 'no',
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Accept, MCP-Protocol-Version, MCP-Session-Id',
        'Access-Control-Max-Age' => '86400',
        'Keep-Alive' => 'timeout=600',
        'Pragma' => 'no-cache',
        'Expires' => '0'
      }.freeze

      attr_reader :app, :path, :sse_clients, :allowed_origins, :localhost_only, :allowed_ips, :sessions

      def initialize(app, server, options = {})
        super(server, logger: options[:logger])
        @app = app
        @path = options[:path] || DEFAULT_PATH
        @allowed_origins = options[:allowed_origins] || DEFAULT_ALLOWED_ORIGINS
        @localhost_only = options.fetch(:localhost_only, true)
        @allowed_ips = options[:allowed_ips] || DEFAULT_ALLOWED_IPS

        # NEW: Detect async mode and create appropriate concurrency adapter
        @async_mode = options.fetch(:async_mode, :auto)
        @concurrency = ConcurrencyAdapter.create(async_enabled: detect_async_mode?)

        # Use adapter for concurrency primitives
        @sse_clients = @concurrency.create_hash
        @sessions = @concurrency.create_hash

        @running = false
        @filtered_servers_cache = {}
      end

      def start
        @logger.debug("Starting StreamableHTTP transport at path: #{@path}")
        @logger.debug("DNS rebinding protection enabled. Allowed origins: #{allowed_origins.join(', ')}")
        @running = true
      end

      def stop
        @logger.debug('Stopping StreamableHTTP transport')
        @running = false

        # Close all SSE connections
        @concurrency.synchronize do
          @sse_clients.each_value do |client|
            client[:stream].close if client[:stream].respond_to?(:close) && !client[:stream].closed?
          rescue StandardError => e
            @logger.error("Error closing SSE connection: #{e.message}")
          end
          @sse_clients.clear
        end

        # Clear sessions
        @concurrency.synchronize { @sessions.clear }
      end

      def send_message(message, session_id: nil)
        json_message = message.is_a?(String) ? message : JSON.generate(message)

        if session_id
          @logger.debug("Sending message to session #{session_id}: #{json_message}")
          send_message_to_session(json_message, session_id)
        else
          @logger.debug("Broadcasting message to #{@sse_clients.size} SSE clients: #{json_message}")
          broadcast_message_to_all(json_message)
        end

        [json_message]
      end

      # Server-controlled streaming API
      # Initiate a streaming response for the current request
      # This should be called by server code when it decides to stream instead of returning immediately
      def initiate_streaming_response(session_id, env)
        return unless env['rack.hijack']

        @logger.debug("Server-initiated streaming response for session: #{session_id}")

        # Hijack the connection and setup SSE
        env['rack.hijack'].call
        io = env['rack.hijack_io']

        setup_server_controlled_sse(session_id, io)

        # Return hijacked response indicator
        [-1, {}, []]
      end

      # Send a message to a specific streaming session
      # This allows the server to send notifications/progress during request processing
      def send_streaming_message(session_id, message, event_type: 'message')
        client = @sse_clients[session_id]
        return false unless client

        stream = client[:stream]
        return false if stream.nil? || (stream.respond_to?(:closed?) && stream.closed?)

        json_message = message.is_a?(String) ? message : JSON.generate(message)

        begin
          @concurrency.synchronize do
            stream.write("event: #{event_type}\n") if event_type
            stream.write("data: #{json_message}\n\n")
            stream.flush if stream.respond_to?(:flush)
          end
          true
        rescue Errno::EPIPE, IOError => e
          @logger.info("Streaming client #{session_id} disconnected: #{e.message}")
          unregister_sse_client(session_id)
          false
        rescue StandardError => e
          @logger.error("Error sending streaming message to client #{session_id}: #{e.message}")
          unregister_sse_client(session_id)
          false
        end
      end

      # Complete a streaming response by sending the final result and closing the stream
      def complete_streaming_response(session_id, response, response_id: nil)
        # Send the final response
        final_response = if response_id
                           response.merge(id: response_id)
                         else
                           response
                         end

        success = send_streaming_message(session_id, final_response, event_type: 'response')

        # Send completion event and close stream
        if success
          send_streaming_message(session_id, { status: 'completed' }, event_type: 'stream-end')

          # Close the stream after a brief delay
          @concurrency.async_task do
            @concurrency.sleep(0.1)
            client = @sse_clients[session_id]
            if client && client[:stream] && !client[:stream].closed?
              begin
                client[:stream].close
              rescue StandardError
                nil
              end
            end
            unregister_sse_client(session_id)
          end
        end

        success
      end

      private

      # Send message to specific session
      def send_message_to_session(json_message, session_id)
        client = @sse_clients[session_id]
        return unless client

        stream = client[:stream]
        return if stream.nil? || (stream.respond_to?(:closed?) && stream.closed?)

        begin
          @concurrency.synchronize do
            stream.write("data: #{json_message}\n\n")
            stream.flush if stream.respond_to?(:flush)
          end
        rescue Errno::EPIPE, IOError => e
          @logger.info("Client #{session_id} disconnected: #{e.message}")
          unregister_sse_client(session_id)
        rescue StandardError => e
          @logger.error("Error sending message to client #{session_id}: #{e.message}")
          unregister_sse_client(session_id)
        end
      end

      # Broadcast message to all connected clients
      def broadcast_message_to_all(json_message)
        clients_to_remove = []
        @concurrency.synchronize do
          @sse_clients.each do |client_id, client|
            stream = client[:stream]
            next if stream.nil? || (stream.respond_to?(:closed?) && stream.closed?)

            begin
              stream.write("data: #{json_message}\n\n")
              stream.flush if stream.respond_to?(:flush)
            rescue Errno::EPIPE, IOError => e
              @logger.info("Client #{client_id} disconnected: #{e.message}")
              clients_to_remove << client_id
            rescue StandardError => e
              @logger.error("Error sending message to client #{client_id}: #{e.message}")
              clients_to_remove << client_id
            end
          end
        end

        clients_to_remove.each { |client_id| unregister_sse_client(client_id) }
      end

      public

      # Rack call method - unified endpoint handler
      def call(env)
        request = Rack::Request.new(env)
        path = request.path

        # Check if this is our MCP endpoint
        if path == @path
          @server.transport = self
          handle_mcp_request(request, env)
        else
          # Pass through to the main application
          @app.call(env)
        end
      end

      private

      # Handle MCP requests at the unified endpoint
      def handle_mcp_request(request, env)
        # Security validations
        return forbidden_response('Forbidden: Remote IP not allowed') unless valid_client_ip?(request)
        return forbidden_response('Forbidden: Origin validation failed') unless valid_origin?(request, env)

        # Validate protocol version (required in MCP 2025-06-18)
        return protocol_version_error unless valid_protocol_version_header?(request)

        # Get appropriate server for this request
        request_server = get_server_for_request(request, env)

        # Store original transport if using filtered server
        if request_server != @server
          original_transport = request_server.transport
          request_server.transport = self
        end

        # Route based on HTTP method
        result = case request.request_method
                 when 'OPTIONS'
                   handle_options_request
                 when 'GET'
                   handle_get_request(request, env)
                 when 'POST'
                   handle_post_request(request, request_server)
                 else
                   method_not_allowed_response
                 end

        # Restore original transport if needed
        request_server.transport = original_transport if request_server != @server && original_transport

        result
      end

      # Handle OPTIONS preflight requests
      def handle_options_request
        [200, setup_cors_headers, ['']]
      end

      # Handle GET requests (SSE stream initialization)
      def handle_get_request(request, env)
        # Validate Accept header for SSE
        accept_header = request.get_header('HTTP_ACCEPT') || ''
        unless accept_header.include?(SSE_CONTENT_TYPE)
          error_msg = 'Bad Request: Accept header must include text/event-stream'
          return [400, { 'Content-Type' => JSON_CONTENT_TYPE },
                  [JSON.generate(create_error_response(-32_600, error_msg))]]
        end

        # Handle SSE stream
        handle_sse_stream(request, env)
      end

      # Handle POST requests (JSON-RPC messages)
      def handle_post_request(request, server)
        # Validate Accept header
        accept_header = request.get_header('HTTP_ACCEPT') || ''
        valid_accept = REQUIRED_ACCEPT_HEADERS.any? { |header| accept_header.include?(header) }

        unless valid_accept
          error_msg = 'Bad Request: Accept header must include application/json and text/event-stream'
          return [400, { 'Content-Type' => JSON_CONTENT_TYPE },
                  [JSON.generate(create_error_response(-32_600, error_msg))]]
        end

        # Process JSON-RPC request
        begin
          process_json_rpc_request(request, server)
        rescue JSON::ParserError => e
          handle_parse_error(e)
        rescue StandardError => e
          handle_internal_error(e)
        end
      end

      # Process JSON-RPC request
      def process_json_rpc_request(request, server)
        body = request.body.read
        @logger.debug("Processing JSON-RPC request: #{body}")

        # Validate JSON first to catch parse errors
        JSON.parse(body) unless body.empty?

        # Extract headers
        headers = extract_headers_from_request(request)

        # Handle the request
        response = server.handle_request(body, headers: headers)

        # Determine if this is a notification (no response expected)
        if response.nil? || response.empty?
          # Return 202 Accepted for notifications with session ID
          session_id = get_or_create_session(request)
          headers = { 'Content-Type' => JSON_CONTENT_TYPE, 'MCP-Session-Id' => session_id }
          [202, headers, ['']]
        else
          # Return JSON response or potentially SSE stream
          handle_json_rpc_response(response, request)
        end
      end

      def extract_headers_from_request(request)
        request.env.select { |k, _v| k.start_with?('HTTP_') }
               .transform_keys { |k| k.sub('HTTP_', '').downcase.tr('_', '-') }
      end

      # Handle JSON-RPC response (always single response since batching was removed in MCP 2025-06-18)
      def handle_json_rpc_response(response, request)
        # Get session ID for header
        session_id = get_or_create_session(request)

        # Return single JSON response with session ID header
        headers = { 'Content-Type' => JSON_CONTENT_TYPE, 'MCP-Session-Id' => session_id }
        [200, headers, response]
      end

      # Handle SSE stream setup
      def handle_sse_stream(request, env)
        if env['rack.hijack']
          # Use rack hijacking for SSE
          handle_rack_hijack_sse(request, env)
        else
          # Fallback for servers without hijacking support
          [200, SSE_HEADERS.dup, [": SSE connection established\n\n"]]
        end
      end

      # Handle SSE with rack hijacking
      def handle_rack_hijack_sse(request, env)
        session_id = get_or_create_session(request)
        @logger.debug("Setting up SSE connection for session: #{session_id}")

        env['rack.hijack'].call
        io = env['rack.hijack_io']

        setup_sse_connection(session_id, io, env)
        start_sse_keep_alive(session_id, io)

        [-1, {}, []]
      end

      # Set up SSE connection
      def setup_sse_connection(session_id, io, _env)
        # Send HTTP headers
        @concurrency.synchronize do
          io.write("HTTP/1.1 200 OK\r\n")
          SSE_HEADERS.each { |k, v| io.write("#{k}: #{v}\r\n") }
          io.write("MCP-Session-Id: #{session_id}\r\n")
          io.write("\r\n")
          io.flush
        end

        # Register SSE client
        register_sse_client(session_id, io)

        # Send initial connection message
        @concurrency.synchronize do
          io.write(": SSE connection established\n\n")
          io.write("retry: 1000\n\n")
          io.flush
        end
      end

      # Set up SSE connection for server-controlled streaming
      def setup_server_controlled_sse(session_id, io)
        # Send HTTP headers for SSE
        @concurrency.synchronize do
          io.write("HTTP/1.1 200 OK\r\n")
          SSE_HEADERS.each { |k, v| io.write("#{k}: #{v}\r\n") }
          io.write("MCP-Session-Id: #{session_id}\r\n")
          io.write("\r\n")
          io.flush
        end

        # Register SSE client
        register_sse_client(session_id, io)

        # Send initial connection message
        @concurrency.synchronize do
          io.write(": Server-controlled streaming initialized\n\n")
          io.write("retry: 1000\n\n")
          io.flush
        end
      end

      # Get or create session ID
      def get_or_create_session(request)
        # Try to get session ID from various sources (MCP-Session-Id header takes precedence)
        session_id = request.get_header('HTTP_MCP_SESSION_ID')
        session_id ||= request.params['session_id']
        session_id ||= request.get_header('HTTP_X_SESSION_ID')
        session_id ||= request.get_header('HTTP_LAST_EVENT_ID')

        # Validate session ID format if provided
        if session_id && !valid_session_id_format?(session_id)
          @logger.warn("Invalid session ID format received: #{session_id}")
          session_id = nil
        end

        # Generate new session ID if none provided or invalid
        if session_id.nil? || session_id.empty?
          session_id = generate_session_id
          @logger.debug("Generated new session ID: #{session_id}")
        else
          @logger.debug("Using existing session ID: #{session_id}")
        end

        # Store/update session information
        update_session_info(session_id, request)

        session_id
      end

      # Validate session ID format (must be alphanumeric, 32 chars)
      def valid_session_id_format?(session_id)
        session_id.match?(/\A[a-zA-Z0-9]{32}\z/)
      end

      # Update session information
      def update_session_info(session_id, request)
        @concurrency.synchronize do
          current_time = Time.now

          @sessions[session_id] ||= {
            created_at: current_time,
            last_seen: current_time,
            connections: 0,
            user_agent: request.get_header('HTTP_USER_AGENT'),
            remote_ip: request.ip
          }

          session = @sessions[session_id]
          session[:connections] += 1
          session[:last_seen] = current_time
          session[:user_agent] ||= request.get_header('HTTP_USER_AGENT')
          session[:remote_ip] ||= request.ip

          # Clean up old sessions periodically
          clean_old_sessions if (session[:connections] % 10).zero?
        end
      end

      # Clean up sessions older than 1 hour with no active connections
      def clean_old_sessions
        cutoff_time = Time.now - 3600 # 1 hour ago

        @sessions.each do |session_id, session_info|
          # Remove if session is old and has no active SSE connections
          if session_info[:last_seen] < cutoff_time && !@sse_clients.key?(session_id)
            @sessions.delete(session_id)
            @logger.debug("Cleaned up old session: #{session_id}")
          end
        end
      end

      # Generate cryptographically secure session ID
      def generate_session_id
        # Generate a cryptographically secure, globally unique session ID
        # containing only visible ASCII characters as per MCP spec
        SecureRandom.alphanumeric(32)
      end

      # Register SSE client
      def register_sse_client(client_id, stream)
        @concurrency.synchronize do
          @logger.info("Registering SSE client: #{client_id}")
          @sse_clients[client_id] = {
            stream: stream,
            connected_at: Time.now
          }
        end
      end

      # Unregister SSE client
      def unregister_sse_client(client_id)
        @concurrency.synchronize do
          @logger.info("Unregistering SSE client: #{client_id}")
          @sse_clients.delete(client_id)
        end
      end

      # Start SSE keep-alive thread
      def start_sse_keep_alive(session_id, io)
        @concurrency.async_task do
          keep_alive_loop(session_id, io)
        rescue StandardError => e
          @logger.error("Error in SSE keep-alive for session #{session_id}: #{e.message}")
        ensure
          cleanup_sse_connection(session_id, io)
        end
      end

      # Keep-alive loop for SSE connections
      def keep_alive_loop(session_id, io)
        ping_count = 0
        client = @sse_clients[session_id]

        while @running && !io.closed? && client
          begin
            @concurrency.synchronize do
              ping_count += 1
              io.write(": keep-alive #{ping_count}\n\n")
              io.flush
            end
            @concurrency.sleep(30) # Send keep-alive every 30 seconds
          rescue Errno::EPIPE, IOError => e
            @logger.info("SSE connection closed for session #{session_id}: #{e.message}")
            break
          end
        end
      end

      # Clean up SSE connection
      def cleanup_sse_connection(session_id, io)
        @logger.info("Cleaning up SSE connection for session: #{session_id}")
        unregister_sse_client(session_id)

        begin
          io.close unless io.closed?
        rescue StandardError => e
          @logger.error("Error closing SSE connection: #{e.message}")
        end
      end

      # Validate client IP
      def valid_client_ip?(request)
        client_ip = request.ip

        if @localhost_only && !@allowed_ips.include?(client_ip)
          @logger.warn("Blocked connection from non-localhost IP: #{client_ip}")
          return false
        end

        true
      end

      # Validate Origin header (DNS rebinding protection)
      def valid_origin?(request, env)
        origin = env['HTTP_ORIGIN']
        origin = env['HTTP_REFERER'] || request.host if origin.nil? || origin.empty?

        hostname = extract_hostname(origin)

        if hostname && !allowed_origins.empty?
          @logger.debug("Validating origin: #{hostname}")

          is_allowed = allowed_origins.any? do |allowed|
            if allowed.is_a?(Regexp)
              hostname.match?(allowed)
            else
              hostname == allowed
            end
          end

          unless is_allowed
            @logger.warn("Blocked request with origin: #{hostname}")
            return false
          end
        end

        true
      end

      # Extract hostname from URL
      def extract_hostname(url)
        return nil if url.nil? || url.empty?

        begin
          has_scheme = url.match?(%r{^[a-zA-Z][a-zA-Z0-9+.-]*://})
          parsing_url = has_scheme ? url : "http://#{url}"
          uri = URI.parse(parsing_url)
          return nil if uri.host.nil? || uri.host.empty?

          uri.host
        rescue URI::InvalidURIError
          url.split(':').first if url.match?(%r{^([^:/]+)(:\d+)?$})
        end
      end

      # Validate MCP protocol version header (required in 2025-06-18)
      def valid_protocol_version_header?(request)
        version = request.get_header('HTTP_MCP_PROTOCOL_VERSION')
        return true if version.nil? || version.empty?

        unless version == PROTOCOL_VERSION
          @logger.warn("Unsupported protocol version: #{version}, expected: #{PROTOCOL_VERSION}")
          return false
        end

        true
      end

      # Get server for request (with filtering support)
      def get_server_for_request(request, env)
        # Check for explicit server in env
        return env[SERVER_ENV_KEY] if env[SERVER_ENV_KEY]

        # Apply filters if configured
        if @server.contains_filters?
          @logger.debug('Server has filters, creating filtered copy')
          cache_key = generate_cache_key(request)
          @filtered_servers_cache[cache_key] ||= @server.create_filtered_copy(request)
          return @filtered_servers_cache[cache_key]
        end

        # Use default server
        @server
      end

      # Generate cache key for filtered servers
      def generate_cache_key(request)
        {
          path: request.path,
          params: request.params.sort.to_h,
          headers: extract_relevant_headers(request)
        }.hash
      end

      # Extract relevant headers for filtering
      def extract_relevant_headers(request)
        relevant_headers = {}
        ['X-User-Role', 'X-API-Version', 'X-Tenant-ID', 'Authorization'].each do |header|
          header_key = "HTTP_#{header.upcase.tr('-', '_')}"
          relevant_headers[header] = request.env[header_key] if request.env[header_key]
        end
        relevant_headers
      end

      # Response helpers
      def setup_cors_headers
        {
          'Access-Control-Allow-Origin' => '*',
          'Access-Control-Allow-Methods' => 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers' => 'Content-Type, Accept, MCP-Protocol-Version, MCP-Session-Id',
          'Access-Control-Max-Age' => '86400',
          'Content-Type' => 'text/plain'
        }
      end

      def forbidden_response(message)
        [403, { 'Content-Type' => JSON_CONTENT_TYPE },
         [JSON.generate(create_error_response(-32_600, message))]]
      end

      def method_not_allowed_response
        [405, { 'Content-Type' => JSON_CONTENT_TYPE },
         [JSON.generate(create_error_response(-32_601, 'Method not allowed'))]]
      end

      def protocol_version_error
        [400, { 'Content-Type' => JSON_CONTENT_TYPE },
         [JSON.generate(protocol_version_error_response)]]
      end

      # Override base class to use StreamableHTTP protocol version
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

      def handle_parse_error(error)
        @logger.error("Invalid JSON in request: #{error.message}")
        [400, { 'Content-Type' => JSON_CONTENT_TYPE },
         [JSON.generate(create_error_response(-32_700, 'Parse error: Invalid JSON'))]]
      end

      def handle_internal_error(error)
        @logger.error("Error processing request: #{error.message}")
        [500, { 'Content-Type' => JSON_CONTENT_TYPE },
         [JSON.generate(create_error_response(-32_603, "Internal error: #{error.message}"))]]
      end

      def create_error_response(code, message, id = nil)
        {
          jsonrpc: '2.0',
          error: { code: code, message: message },
          id: id
        }
      end

      # Detect async mode based on configuration and environment
      def detect_async_mode?
        case @async_mode
        when :auto
          # Auto-detect: Check if running in Falcon/Async context
          !Fiber.scheduler.nil?
        when :enabled, true
          true
        else
          false
        end
      end
    end
  end
end
