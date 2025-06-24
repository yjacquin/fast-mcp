# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module FastMcp
  module OAuth
    # OAuth 2.1 Token Introspection
    # RFC 7662: https://tools.ietf.org/html/rfc7662
    class Introspection
      class IntrospectionError < StandardError; end

      # Standard introspection response fields
      INTROSPECTION_FIELDS = %w[
        active
        scope
        client_id
        username
        token_type
        exp
        iat
        nbf
        sub
        aud
        iss
        jti
      ].freeze

      attr_reader :logger, :introspection_endpoint, :client_id, :client_secret

      def initialize(options = {})
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @introspection_endpoint = options[:introspection_endpoint]
        @client_id = options[:client_id]
        @client_secret = options[:client_secret]
        @timeout = options.fetch(:timeout, 30)
        @user_agent = options[:user_agent] || "FastMCP/#{FastMcp::VERSION} OAuth Introspection"

        raise ArgumentError, 'Introspection endpoint is required' unless @introspection_endpoint
        raise ArgumentError, 'Client credentials are required for introspection' unless @client_id && @client_secret
      end

      # Introspect a token
      def introspect_token(token, token_type_hint: nil)
        raise ArgumentError, 'Token is required' if token.nil? || token.empty?

        @logger.debug("Introspecting token (hint: #{token_type_hint})")

        response = send_introspection_request(token, token_type_hint)
        parse_introspection_response(response)
      end

      # Check if token is active
      def token_active?(token, token_type_hint: nil)
        result = introspect_token(token, token_type_hint: token_type_hint)
        result['active'] == true
      rescue StandardError => e
        @logger.warn("Token introspection failed: #{e.message}")
        false
      end

      # Get token information
      def token_info(token, token_type_hint: nil)
        result = introspect_token(token, token_type_hint: token_type_hint)

        return nil unless result['active']

        {
          subject: result['sub'],
          scopes: parse_scopes(result['scope']),
          client_id: result['client_id'],
          username: result['username'],
          token_type: result['token_type'],
          expires_at: result['exp'] ? Time.at(result['exp']) : nil,
          issued_at: result['iat'] ? Time.at(result['iat']) : nil,
          not_before: result['nbf'] ? Time.at(result['nbf']) : nil,
          audience: result['aud'],
          issuer: result['iss'],
          jwt_id: result['jti']
        }
      end

      # Validate token with required scopes
      def validate_token_with_scopes(token, required_scopes, token_type_hint: nil)
        info = token_info(token, token_type_hint: token_type_hint)
        return false unless info

        return true if required_scopes.nil? || required_scopes.empty?

        token_scopes = info[:scopes] || []
        required_scopes.all? { |scope| token_scopes.include?(scope) }
      end

      private

      # Send introspection request to authorization server
      def send_introspection_request(token, token_type_hint)
        uri = URI(@introspection_endpoint)

        # Prepare request parameters
        params = { 'token' => token }
        params['token_type_hint'] = token_type_hint if token_type_hint

        # Create HTTP request
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/x-www-form-urlencoded'
        request['Accept'] = 'application/json'
        request['User-Agent'] = @user_agent

        # Add client authentication
        request.basic_auth(@client_id, @client_secret)

        # Set request body
        request.body = URI.encode_www_form(params)

        @logger.debug("Sending introspection request to #{@introspection_endpoint}")

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise IntrospectionError, "Introspection request failed: #{response.code} #{response.message}"
        end

        response
      rescue StandardError => e
        raise IntrospectionError, "Introspection request error: #{e.message}"
      end

      # Parse introspection response
      def parse_introspection_response(response)
        begin
          result = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise IntrospectionError, "Invalid JSON response: #{e.message}"
        end

        # Validate required 'active' field
        unless result.key?('active')
          raise IntrospectionError, "Missing required 'active' field in introspection response"
        end

        # Log introspection result
        if result['active']
          @logger.debug("Token is active (client: #{result['client_id']}, subject: #{result['sub']})")
        else
          @logger.debug('Token is inactive')
        end

        result
      end

      # Parse scopes from introspection response
      def parse_scopes(scope_value)
        case scope_value
        when String
          scope_value.split
        when Array
          scope_value
        else
          []
        end
      end

      # Build introspection client for local token validation
      class LocalIntrospector
        def initialize(token_validator, logger: nil)
          @token_validator = token_validator
          @logger = logger || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        end

        # Introspect token locally (for resource server use)
        def introspect_token(token, _token_type_hint = nil)
          # Extract claims from token
          claims = @token_validator.extract_claims(token)

          # Validate token
          is_valid = @token_validator.validate_token(token)

          # Build introspection response
          response = { 'active' => is_valid }

          if is_valid && claims
            response.merge!(
              'scope' => claims['scope'],
              'client_id' => claims['client_id'] || claims['azp'],
              'username' => claims['preferred_username'] || claims['name'],
              'token_type' => 'Bearer',
              'exp' => claims['exp'],
              'iat' => claims['iat'],
              'nbf' => claims['nbf'],
              'sub' => claims['sub'],
              'aud' => claims['aud'],
              'iss' => claims['iss'],
              'jti' => claims['jti']
            )
          end

          @logger.debug("Local introspection result: active=#{is_valid}")
          response
        end

        # Check if token is active locally
        def token_active?(token, token_type_hint: nil)
          result = introspect_token(token, token_type_hint)
          result['active'] == true
        rescue StandardError => e
          @logger.warn("Local token introspection failed: #{e.message}")
          false
        end

        # Get token information locally
        def token_info(token, token_type_hint: nil)
          result = introspect_token(token, token_type_hint)

          return nil unless result['active']

          {
            subject: result['sub'],
            scopes: parse_scopes(result['scope']),
            client_id: result['client_id'],
            username: result['username'],
            token_type: result['token_type'],
            expires_at: result['exp'] ? Time.at(result['exp']) : nil,
            issued_at: result['iat'] ? Time.at(result['iat']) : nil,
            not_before: result['nbf'] ? Time.at(result['nbf']) : nil,
            audience: result['aud'],
            issuer: result['iss'],
            jwt_id: result['jti']
          }
        end

        private

        # Parse scopes from introspection response
        def parse_scopes(scope_value)
          case scope_value
          when String
            scope_value.split
          when Array
            scope_value
          else
            []
          end
        end
      end
    end
  end
end
