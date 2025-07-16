# frozen_string_literal: true

module FastMcp
  module OAuth
    # Local Token Introspection for Resource Servers
    # Provides local token validation without requiring external introspection endpoints
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
