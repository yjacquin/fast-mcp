# frozen_string_literal: true

require_relative 'streamable_http'
require_relative '../oauth/resource_server'
require_relative '../oauth/errors'
require 'forwardable'

module FastMcp
  module Transports
    # OAuth 2.1 enabled StreamableHTTP transport for MCP 2025-06-18
    # Provides comprehensive OAuth 2.1 authorization with scope-based access control
    class OAuthStreamableHttpTransport < StreamableHttpTransport
      extend Forwardable

      attr_reader :oauth_resource_server, :oauth_enabled, :scope_requirements, :authorization_servers

      def initialize(app, server, options = {})
        super

        # OAuth configuration
        # oauth_enabled can be set to false to disable OAuth authorization for development purposes
        # oauth_enabled needs to be true for production environments, otherwise use StreamableHttpTransport
        @oauth_enabled = options.fetch(:oauth_enabled, true)
        @authorization_servers = options.fetch(:authorization_servers, [])
        @oauth_resource_server = FastMcp::OAuth::ResourceServer.new(authorization_servers,
                                                                    options.merge(logger: @logger))

        # Authorization servers for metadata endpoint (RFC 9728)

        # Scope requirements for different MCP operations
        @scope_requirements = {
          tools: options[:tools_scope] || 'mcp:tools',
          resources: options[:resources_scope] || 'mcp:resources',
          admin: options[:admin_scope] || 'mcp:admin'
        }

        @logger.debug("OAuth 2.1 #{@oauth_enabled ? 'enabled' : 'disabled'} for StreamableHTTP transport")
        @logger.debug("Scope requirements: #{@scope_requirements}") if @oauth_enabled
      end

      def call(env)
        request = Rack::Request.new(env)
        path = request.path

        # Check for OAuth protected resource metadata endpoint (RFC 9728)
        return handle_oauth_protected_resource_metadata(request) if path == '/.well-known/oauth-protected-resource'

        super
      end

      private

      def_delegators :@oauth_resource_server, :oauth_invalid_request_response, :oauth_invalid_scope_response,
                     :oauth_server_error_response

      # Handle OAuth Protected Resource Metadata endpoint (RFC 9728)
      def handle_oauth_protected_resource_metadata(request)
        # Only GET method is allowed for metadata endpoint
        unless request.request_method == 'GET'
          return [405, { 'Content-Type' => JSON_CONTENT_TYPE, 'Allow' => 'GET' },
                  [JSON.generate(create_error_response(-32_601, 'Method not allowed'))]]
        end

        # Basic security validations
        return forbidden_response('Forbidden: Remote IP not allowed') unless valid_client_ip?(request)

        # Construct the resource identifier
        scheme = request.scheme
        host = request.host
        port = request.port

        # Only include port if it's non-standard
        resource_uri = if (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80)
                         "#{scheme}://#{host}"
                       else
                         "#{scheme}://#{host}:#{port}"
                       end

        # Get authorization servers (can be overridden in subclasses)
        auth_servers = authorization_servers

        metadata = {
          resource: resource_uri,
          authorization_servers: auth_servers
        }

        @logger.debug("Serving OAuth protected resource metadata: #{metadata}")

        headers = {
          'Content-Type' => JSON_CONTENT_TYPE,
          'Cache-Control' => 'public, max-age=3600'
        }

        [200, headers, [JSON.generate(metadata)]]
      end

      # Override MCP request handler to add OAuth 2.1 authorization
      def handle_mcp_request(request, env)
        # Perform OAuth authorization if enabled
        if @oauth_enabled
          begin
            @token_info = @oauth_resource_server.authorize_request!(request)
            @logger.debug("OAuth authorization successful for subject: #{@token_info[:subject]}")
          rescue OAuth::InvalidRequestError => e
            return oauth_invalid_request_response(e.message, status: e.status)
          end
        end

        # Call parent implementation
        super
      end

      # Override JSON-RPC request processing to add scope validation
      def process_json_rpc_request(request, server)
        body = request.body.read
        @logger.debug("Processing OAuth-protected JSON-RPC request: #{body}")

        # Validate JSON first
        parsed_request = JSON.parse(body)

        # validate scopes if OAuth is enabled
        validate_scope!(parsed_request) if @oauth_enabled

        # Extract headers
        headers = extract_headers_from_request(request)

        # Add OAuth token info to headers for server processing
        if @oauth_enabled && @token_info
          headers['oauth-subject'] = @token_info[:subject]
          headers['oauth-scopes'] = @token_info[:scopes].join(' ')
          headers['oauth-client-id'] = @token_info[:client_id] if @token_info[:client_id]
        end

        # Handle the request
        response = server.handle_request(body, headers: headers)

        # Determine response handling
        if response.nil? || response.empty?
          [202, { 'Content-Type' => JSON_CONTENT_TYPE }, ['']]
        else
          handle_json_rpc_response(response, request)
        end
      rescue OAuth::InvalidRequestError => e
        oauth_invalid_request_response(e.message, status: e.status)
      rescue OAuth::InvalidScopeError => e
        oauth_invalid_scope_response(e.required_scope, status: e.status)
      rescue OAuth::ServerError => e
        oauth_server_error_response(e.message, status: e.status)
      rescue StandardError => e
        oauth_server_error_response(e.message)
      end

      def validate_scope!(parsed_request)
        required_scope = determine_required_scope(parsed_request)
        return unless required_scope && !required_scope?(required_scope)

        raise OAuth::InvalidScopeError.new("Required scope: #{required_scope}", required_scope: required_scope,
                                                                                status: 403)
      end

      # Determine required scope based on JSON-RPC method
      def determine_required_scope(parsed_request)
        method = parsed_request['method']
        return nil unless method

        case method
        when %r{\Atools/}
          @scope_requirements[:tools]
        when %r{\Aresources/}
          @scope_requirements[:resources]
        when 'initialize', 'ping'
          nil # No special scope required for these
        else
          @scope_requirements[:admin] # Default to admin scope for unknown methods
        end
      end

      # Check if current token has required scope
      def required_scope?(required_scope)
        return true unless @oauth_enabled && @token_info

        @token_info[:scopes].include?(required_scope)
      end

      # Override SSE handling to include OAuth validation
      def handle_sse_stream(request, env)
        # Perform OAuth authorization if enabled
        if @oauth_enabled
          begin
            @token_info = @oauth_resource_server.authorize_request!(request)
            @logger.debug("OAuth authorization successful for subject: #{@token_info[:subject]}")
          rescue OAuth::InvalidRequestError => e
            return oauth_invalid_request_response(e.message, status: e.status)
          end
        end

        super
      end

      # Override to add OAuth info to SSE connections
      def setup_sse_connection(session_id, io, _env)
        super

        # Send OAuth info as initial SSE event if available
        return unless @oauth_enabled && @token_info

        mutex = @sse_clients[session_id]&.dig(:mutex)
        return unless mutex

        oauth_info = {
          subject: @token_info[:subject],
          scopes: @token_info[:scopes],
          expires_at: @token_info[:expires_at]&.iso8601
        }

        mutex.synchronize do
          io.write("event: oauth-info\n")
          io.write("data: #{JSON.generate(oauth_info)}\n\n")
          io.flush
        end
      end
    end
  end
end
