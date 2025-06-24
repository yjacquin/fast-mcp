# frozen_string_literal: true

require_relative 'streamable_http'
require_relative '../oauth/resource_server'

module FastMcp
  module Transports
    # OAuth 2.1 enabled StreamableHTTP transport for MCP 2025-06-18
    # Provides comprehensive OAuth 2.1 authorization with scope-based access control
    class OAuthStreamableHttpTransport < StreamableHttpTransport
      attr_reader :oauth_server, :oauth_enabled, :scope_requirements

      def initialize(app, server, options = {})
        super

        # OAuth configuration
        @oauth_enabled = options.fetch(:oauth_enabled, true)
        @oauth_server = FastMcp::OAuth::ResourceServer.new(options.merge(logger: @logger))

        # Scope requirements for different MCP operations
        @scope_requirements = {
          tools: options[:tools_scope] || 'mcp:tools',
          resources: options[:resources_scope] || 'mcp:resources',
          admin: options[:admin_scope] || 'mcp:admin'
        }

        @logger.debug("OAuth 2.1 #{@oauth_enabled ? 'enabled' : 'disabled'} for StreamableHTTP transport")
        @logger.debug("Scope requirements: #{@scope_requirements}") if @oauth_enabled
      end

      private

      # Override MCP request handler to add OAuth 2.1 authorization
      def handle_mcp_request(request, env)
        # Perform OAuth authorization if enabled
        if @oauth_enabled
          begin
            @token_info = @oauth_server.authorize_request(request)
            @logger.debug("OAuth authorization successful for subject: #{@token_info[:subject]}")
          rescue FastMcp::OAuth::ResourceServer::UnauthorizedError => e
            return oauth_unauthorized_response(e.message)
          rescue FastMcp::OAuth::ResourceServer::ForbiddenError => e
            return oauth_forbidden_response(e.message)
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
        JSON.parse(body) unless body.empty?

        # Extract method and validate scopes if OAuth is enabled
        if @oauth_enabled
          parsed_request = JSON.parse(body)
          required_scope = determine_required_scope(parsed_request)
          return oauth_insufficient_scope_response(required_scope) if required_scope && !required_scope?(required_scope)
        end

        # Extract headers
        headers = request.env.select { |k, _v| k.start_with?('HTTP_') }
                         .transform_keys { |k| k.sub('HTTP_', '').downcase.tr('_', '-') }

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
        return true unless @oauth_enabled || !@token_info

        @token_info[:scopes].include?(required_scope)
      end

      # Generate OAuth unauthorized response
      def oauth_unauthorized_response(message)
        error_response = @oauth_server.oauth_error_response('invalid_token', message, 401)
        [error_response[:status], error_response[:headers], [error_response[:body]]]
      end

      # Generate OAuth forbidden response
      def oauth_forbidden_response(message)
        error_response = @oauth_server.oauth_error_response('insufficient_scope', message, 403)
        [error_response[:status], error_response[:headers], [error_response[:body]]]
      end

      # Generate insufficient scope response
      def oauth_insufficient_scope_response(required_scope)
        message = "Required scope: #{required_scope}"
        error_response = @oauth_server.oauth_error_response('insufficient_scope', message, 403)
        [error_response[:status], error_response[:headers], [error_response[:body]]]
      end

      # Override SSE handling to include OAuth validation
      def handle_sse_stream(request, env)
        # For SSE streams, we need read access at minimum
        if @oauth_enabled && !required_scope?(@scope_requirements[:resources])
          return oauth_insufficient_scope_response(@scope_requirements[:resources])
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
