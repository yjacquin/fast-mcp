# frozen_string_literal: true

require_relative 'token_validator'
require_relative 'introspection'
require_relative 'errors'

module FastMcp
  module OAuth
    # OAuth 2.1 Resource Server
    # Provides OAuth-based authorization for MCP servers
    class ResourceServer
      # OAuth 2.1 standard scopes for MCP
      DEFAULT_SCOPES = {
        'mcp:read' => 'Read access to MCP resources',
        'mcp:write' => 'Write access to MCP resources',
        'mcp:tools' => 'Access to execute MCP tools',
        'mcp:admin' => 'Administrative access to MCP server'
      }.freeze

      attr_reader :authorization_servers, :token_validator, :logger, :scope_definitions, :introspector,
                  :resource_identifier

      def initialize(authorization_servers, options = {})
        @authorization_servers = authorization_servers
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @token_validator = TokenValidator.new(options.merge(logger: @logger))
        @scope_definitions = DEFAULT_SCOPES.merge(options[:custom_scopes] || {})
        @require_https = options.fetch(:require_https, true) # HTTPS required by default for OAuth 2.1 compliance

        # Resource identifier for audience binding (RFC 8707)
        @resource_identifier = options[:resource_identifier] || options[:audience]

        # Set up local token introspection (resource servers only need local validation)
        @introspector = LocalIntrospector.new(@token_validator, logger: @logger)
      end

      # Authorize a request with OAuth 2.1
      def authorize_request!(request, required_scopes: nil)
        # Extract token from request
        token = extract_bearer_token(request)
        raise InvalidRequestError.new('Missing authentication token', status: 401) unless token

        # Validate security requirements
        validate_request_security!(request) if @require_https

        # Validate token and scopes
        unless @token_validator.validate_token(token, required_scopes: required_scopes)
          raise InvalidRequestError.new('Invalid or expired token', status: 401)
        end

        # Extract token information
        token_info = extract_token_info(token)

        # Validate audience binding if resource identifier is configured
        validate_audience_binding!(token_info) if @resource_identifier

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
      def extract_token_info(token)
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

      def oauth_invalid_request_response(message, status:)
        oauth_error_response(:invalid_request, message, status)
      end

      def oauth_invalid_scope_response(required_scope, status:)
        message = "Required scope: #{required_scope}"
        oauth_error_response(:invalid_scope, message, status, required_scope)
      end

      def oauth_server_error_response(message, status: 500)
        oauth_error_response(:server_error, message, status)
      end

      # Generate OAuth error responses
      def oauth_error_response(error_type, description = nil, status = 401, realm = nil)
        error_data = { error: error_type }
        error_data[:error_description] = description if description

        www_authenticate = build_www_authenticate_header(error_type, description, realm)

        @logger.debug("Oauth error: #{error_data.inspect}")

        [
          status,
          {
            'Content-Type' => 'application/json',
            'WWW-Authenticate' => www_authenticate
          },
          [build_error_response_body(error_type, description, error_data)]
        ]
      end

      private

      BEARER_ERRORS = {
        'invalid_request' => 'Bearer error="invalid_request"',
        'invalid_token' => 'Bearer error="invalid_token"',
        'invalid_scope' => 'Bearer error="invalid_scope"',
        'insufficient_scope' => 'Bearer error="insufficient_scope"',
        'server_error' => 'Bearer error="server_error"'
      }.freeze
      private_constant :BEARER_ERRORS

      def build_www_authenticate_header(error_type, description, realm)
        www_authenticate = BEARER_ERRORS[error_type.to_s] || 'Bearer'

        www_authenticate += %(, error_description="#{description}") if description
        www_authenticate += %(, realm="#{realm}") if realm
        www_authenticate += %(, resource_metadata="#{resource_metadata_url}") if resource_metadata_url

        www_authenticate
      end

      # Build resource metadata URL for WWW-Authenticate header
      def resource_metadata_url
        # Only include metadata URL if we have authorization servers configured
        return nil if authorization_servers.empty?

        @resource_metadata_url ||= begin
          # Construct the resource metadata endpoint URL
          scheme = ENV.fetch('HTTPS', 'false').downcase == 'true' ? 'https' : 'http'
          host = ENV.fetch('HOST', 'localhost')
          port = ENV.fetch('PORT', scheme == 'https' ? '443' : '80').to_i

          # Only include port if it's non-standard
          base_url = if (scheme == 'https' && port == 443) || (scheme == 'http' && port == 80)
                       "#{scheme}://#{host}"
                     else
                       "#{scheme}://#{host}:#{port}"
                     end

          "#{base_url}/.well-known/oauth-protected-resource"
        end
      end

      def build_error_response_body(error_type, description, error_data)
        # Use OAuth 2.1 standard error response format (RFC 6749 Section 5.2)
        response = { error: error_type }
        response[:error_description] = description if description

        # Add optional error URI for more details
        response[:error_uri] = error_data[:error_uri] if error_data && error_data[:error_uri]

        JSON.generate(response)
      end

      # Extract Bearer token from request (OAuth 2.1 compliant)
      def extract_bearer_token(request)
        auth_header = request.get_header('HTTP_AUTHORIZATION')
        return nil unless auth_header

        # OAuth 2.1 requires Bearer prefix and ONLY Authorization header (no query params)
        return unless auth_header.start_with?('Bearer ')

        token = auth_header[7..]

        # Validate token format (RFC 6750 Section 2.1)
        return nil unless token.match?(%r{\A[A-Za-z0-9\-._~+/]+=*\z})

        token
      end

      # Validate request security (HTTPS requirement)
      def validate_request_security!(request)
        # Check if request is over HTTPS (simplified check)
        scheme = request.get_header('HTTP_X_FORWARDED_PROTO') ||
                 request.get_header('rack.url_scheme') || 'http'

        return unless scheme != 'https'

        raise FastMcp::OAuth::InvalidRequestError.new('HTTPS required for OAuth requests', status: 400)
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
      def validate_audience_binding!(token_info)
        token_audience = token_info[:audience]
        return unless token_audience # Skip validation if no audience in token

        # Normalize audiences to arrays for comparison
        token_audiences = Array(token_audience)

        # Check if our resource identifier is in the token's audience
        return unless token_audiences.include?(@resource_identifier)

        @logger.warn(
          "Audience binding validation failed: token audience #{token_audiences} does not include resource #{@resource_identifier}"
        )
        raise UnauthorizedError, 'Token not intended for this resource server'
      end
    end
  end
end
