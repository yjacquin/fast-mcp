# frozen_string_literal: true

require_relative 'streamable_http'

module FastMcp
  module Transports
    # Authenticated StreamableHTTP transport for MCP 2025-06-18 specification
    # This transport adds authentication capabilities to the StreamableHTTP transport
    class AuthenticatedStreamableHttpTransport < StreamableHttpTransport
      attr_reader :auth_enabled, :auth_token, :auth_header_name, :auth_exempt_paths

      def initialize(app, server, options = {})
        super

        @auth_token = options[:auth_token]
        @auth_header_name = options[:auth_header_name] || 'Authorization'
        @auth_exempt_paths = options[:auth_exempt_paths] || []
        @auth_enabled = !@auth_token.nil?

        @logger.debug("Authentication #{@auth_enabled ? 'enabled' : 'disabled'} for StreamableHTTP transport")
        @logger.debug("Auth exempt paths: #{@auth_exempt_paths}") if @auth_enabled && !@auth_exempt_paths.empty?
      end

      private

      # Override the MCP request handler to add authentication
      def handle_mcp_request(request, env)
        # Check authentication first if enabled and not exempt
        if auth_enabled? && !exempt_from_auth?(request.path_info) && !authenticated?(request)
          return unauthorized_response(request)
        end

        # Call parent implementation for the actual request handling
        super
      end

      # Check if authentication is enabled
      def auth_enabled?
        @auth_enabled
      end

      # Check if a path is exempt from authentication
      def exempt_from_auth?(path)
        @auth_exempt_paths.any? { |exempt_path| path.start_with?(exempt_path) }
      end

      # Check if the request is authenticated
      def authenticated?(request)
        auth_header = extract_auth_header(request)
        token = extract_token_from_header(auth_header)
        valid_token?(token)
      end

      # Extract authentication header from request
      def extract_auth_header(request)
        # Convert header name to HTTP_ format (e.g., Authorization -> HTTP_AUTHORIZATION)
        header_key = "HTTP_#{@auth_header_name.upcase.tr('-', '_')}"
        request.env[header_key]
      end

      # Extract token from authorization header
      def extract_token_from_header(auth_header)
        return nil unless auth_header

        # Support both "Bearer token" and "token" formats
        auth_header.gsub(/^Bearer\s+/i, '')
      end

      # Validate the authentication token
      def valid_token?(token)
        return false unless token

        # Simple token comparison - in production, this could be enhanced
        # with JWT validation, database lookups, etc.
        token == @auth_token
      end

      # Generate unauthorized response
      def unauthorized_response(request)
        @logger.warn("Unauthorized request attempt from #{request.ip}")

        # Extract request ID for JSON-RPC compliance
        request_id = extract_request_id_for_auth(request)

        error_response = {
          jsonrpc: '2.0',
          error: {
            code: -32_000,
            message: 'Unauthorized: Invalid or missing authentication token'
          },
          id: request_id
        }

        [401,
         {
           'Content-Type' => JSON_CONTENT_TYPE,
           'WWW-Authenticate' => 'Bearer realm="MCP"'
         },
         [JSON.generate(error_response)]]
      end

      # Extract request ID from JSON-RPC request body for error responses
      def extract_request_id_for_auth(request)
        return nil unless request.post?

        begin
          # Read and rewind body to extract ID without consuming it
          body = request.body.read
          request.body.rewind

          return nil if body.empty?

          parsed_body = JSON.parse(body)
          parsed_body['id']
        rescue StandardError
          nil
        end
      end
    end
  end
end
