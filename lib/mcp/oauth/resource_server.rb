# frozen_string_literal: true

require_relative 'token_validator'
require_relative 'introspection'

module FastMcp
  module OAuth
    # OAuth 2.1 Resource Server
    # Provides OAuth-based authorization for MCP servers
    class ResourceServer
      class UnauthorizedError < StandardError; end
      class ForbiddenError < StandardError; end

      # OAuth 2.1 standard scopes for MCP
      DEFAULT_SCOPES = {
        'mcp:read' => 'Read access to MCP resources',
        'mcp:write' => 'Write access to MCP resources',
        'mcp:tools' => 'Access to execute MCP tools',
        'mcp:admin' => 'Administrative access to MCP server'
      }.freeze

      attr_reader :token_validator, :logger, :scope_definitions, :introspector, :resource_identifier

      def initialize(options = {})
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @token_validator = TokenValidator.new(options.merge(logger: @logger))
        @scope_definitions = DEFAULT_SCOPES.merge(options[:custom_scopes] || {})
        @require_https = options.fetch(:require_https, true) # HTTPS required by default for OAuth 2.1 compliance

        # Resource identifier for audience binding (RFC 8707)
        @resource_identifier = options[:resource_identifier] || options[:audience]

        # Set up token introspection
        @introspection_endpoint = options[:introspection_endpoint]
        @introspector = if @introspection_endpoint
                          Introspection.new(options.merge(logger: @logger))
                        else
                          # Use local introspection as fallback
                          Introspection::LocalIntrospector.new(@token_validator, logger: @logger)
                        end
      end

      # Authorize a request with OAuth 2.1
      def authorize_request(request, required_scopes: nil)
        # Extract token from request
        token = extract_bearer_token(request)
        raise UnauthorizedError, 'Missing authentication token' unless token

        # Validate security requirements
        validate_request_security(request) if @require_https

        # Validate token and scopes
        unless @token_validator.validate_token(token, required_scopes: required_scopes)
          raise UnauthorizedError, 'Invalid or expired token'
        end

        # Extract token information
        token_info = extract_token_info(token)

        # Validate audience binding if resource identifier is configured
        validate_audience_binding(token_info) if @resource_identifier

        token_info
      end

      # Check if request has sufficient scope
      def scope?(request, required_scope)
        token = extract_bearer_token(request)
        return false unless token

        @token_validator.validate_token(token, required_scopes: [required_scope])
      rescue StandardError
        false
      end

      # Get token information for debugging/logging
      def get_token_info(token)
        return nil unless token

        # Try introspection first (works for both JWT and opaque tokens)
        begin
          info = @introspector.token_info(token)
          return info if info
        rescue StandardError => e
          @logger.debug("Introspection failed, falling back to local JWT parsing: #{e.message}")
        end

        # Fallback to local JWT parsing for backwards compatibility
        claims = @token_validator.extract_claims(token)
        if claims
          {
            subject: claims['sub'],
            scopes: extract_scopes(claims['scope']),
            issuer: claims['iss'],
            audience: claims['aud'],
            expires_at: claims['exp'] ? Time.at(claims['exp']) : nil,
            client_id: claims['client_id']
          }
        else
          # Last resort for opaque tokens without introspection
          { subject: 'unknown', scopes: [] }
        end
      end

      # Generate OAuth error responses
      def oauth_error_response(error_type, description = nil, status = 401)
        error_data = { error: error_type }
        error_data[:error_description] = description if description

        www_authenticate = build_www_authenticate_header(error_type, description)

        {
          status: status,
          headers: {
            'Content-Type' => 'application/json',
            'WWW-Authenticate' => www_authenticate
          },
          body: build_error_response_body(error_type, description, error_data)
        }
      end

      private

      def build_www_authenticate_header(error_type, description)
        www_authenticate = case error_type
                           when 'invalid_token'
                             'Bearer error="invalid_token"'
                           when 'insufficient_scope'
                             'Bearer error="insufficient_scope"'
                           when 'invalid_request'
                             'Bearer error="invalid_request"'
                           else
                             'Bearer'
                           end

        www_authenticate += %(, error_description="#{description}") if description

        # Add realm parameter for enhanced security
        www_authenticate += %(, realm="#{@scope_definitions.keys.join(' ')}") unless @scope_definitions.empty?

        www_authenticate
      end

      def build_error_response_body(error_type, description, error_data)
        # Use OAuth 2.1 standard error response format (RFC 6749 Section 5.2)
        # instead of JSON-RPC format
        response = { error: error_type }
        response[:error_description] = description if description

        # Add optional error URI for more details
        response[:error_uri] = error_data[:error_uri] if error_data[:error_uri]

        JSON.generate(response)
      end

      # Extract Bearer token from request
      def extract_bearer_token(request)
        auth_header = request.get_header('HTTP_AUTHORIZATION')
        return nil unless auth_header

        # Support both "Bearer token" and "token" formats
        if auth_header.start_with?('Bearer ')
          auth_header[7..]
        elsif auth_header.match?(%r{\A[A-Za-z0-9\-._~+/]+=*\z})
          # Looks like a token without Bearer prefix
          auth_header
        end
      end

      # Validate request security (HTTPS requirement)
      def validate_request_security(request)
        # Check if request is over HTTPS (simplified check)
        scheme = request.get_header('HTTP_X_FORWARDED_PROTO') ||
                 request.get_header('rack.url_scheme') || 'http'

        return unless scheme != 'https' && !localhost_request?(request)

        raise UnauthorizedError, 'HTTPS required for OAuth requests'
      end

      # Check if request is from localhost (HTTPS not required)
      def localhost_request?(request)
        host = request.get_header('HTTP_HOST') || request.get_header('SERVER_NAME')
        return false unless host

        localhost_patterns = [
          /\Alocalhost(:\d+)?\z/,
          /\A127\.0\.0\.1(:\d+)?\z/,
          /\A\[::1\](:\d+)?\z/
        ]

        localhost_patterns.any? { |pattern| host.match?(pattern) }
      end

      # Extract token information from validated token
      def extract_token_info(token)
        info = get_token_info(token)

        @logger.debug("OAuth authorization successful for subject: #{info[:subject]}")
        @logger.debug("Granted scopes: #{info[:scopes].join(', ')}") unless info[:scopes].empty?

        info
      end

      # Extract scopes from token claims
      def extract_scopes(scope_claim)
        case scope_claim
        when String
          scope_claim.split
        when Array
          scope_claim
        else
          []
        end
      end

      # Validate audience binding for enhanced security (RFC 8707)
      def validate_audience_binding(token_info)
        token_audience = token_info[:audience]
        return unless token_audience # Skip validation if no audience in token

        # Normalize audiences to arrays for comparison
        token_audiences = Array(token_audience)

        # Check if our resource identifier is in the token's audience
        unless token_audiences.include?(@resource_identifier)
          @logger.warn("Audience binding validation failed: token audience #{token_audiences} does not include resource #{@resource_identifier}")
          raise UnauthorizedError, 'Token not intended for this resource server'
        end

        @logger.debug("Audience binding validation successful: resource #{@resource_identifier} found in token audience")
      end
    end
  end
end
