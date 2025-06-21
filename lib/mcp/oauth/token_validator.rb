# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'

module FastMcp
  module OAuth
    # OAuth 2.1 Token Validator
    # Handles JWT and opaque token validation for MCP servers
    class TokenValidator
      class InvalidTokenError < StandardError; end
      class ExpiredTokenError < StandardError; end
      class InvalidScopeError < StandardError; end

      # JWT token types
      JWT_TYPES = %w[JWT jwt].freeze

      attr_reader :logger, :issuer, :audience, :jwks_uri, :required_scopes

      def initialize(options = {})
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @issuer = options[:issuer]
        @audience = options[:audience]
        @jwks_uri = options[:jwks_uri]
        @required_scopes = Array(options[:required_scopes])
        @opaque_token_validator = options[:opaque_token_validator]
        @clock_skew = options[:clock_skew] || 60 # 60 seconds default clock skew
        @jwks_cache = {}
        @jwks_cache_mutex = Mutex.new
      end

      # Validate an OAuth 2.1 token
      def validate_token(token, required_scopes: nil)
        return false if token.nil? || token.empty?

        # Determine token type and validate accordingly
        if jwt_token?(token)
          validate_jwt_token(token, required_scopes: required_scopes)
        else
          validate_opaque_token(token, required_scopes: required_scopes)
        end
      rescue InvalidTokenError, ExpiredTokenError, InvalidScopeError => e
        @logger.warn("Token validation failed: #{e.message}")
        false
      rescue StandardError => e
        @logger.error("Unexpected error during token validation: #{e.message}")
        false
      end

      # Extract claims from a valid token (for debugging/logging)
      def extract_claims(token)
        return nil unless jwt_token?(token)

        payload, _header = decode_jwt(token, verify: false)
        payload
      rescue StandardError => e
        @logger.debug("Failed to extract claims: #{e.message}")
        nil
      end

      private

      # Check if token looks like a JWT
      def jwt_token?(token)
        parts = token.split('.')
        parts.length == 3 && valid_jwt_header?(parts[0])
      end

      # Validate JWT header
      def valid_jwt_header?(header_part)
        header = JSON.parse(Base64.urlsafe_decode64(header_part))
        JWT_TYPES.include?(header['typ']) && !header['alg'].nil?
      rescue StandardError
        false
      end

      # Validate JWT token
      def validate_jwt_token(token, required_scopes: nil)
        payload, = decode_jwt(token)

        # Validate standard JWT claims
        validate_jwt_claims(payload)

        # Validate scopes if required
        validate_token_scopes(payload['scope'], required_scopes) if required_scopes

        @logger.debug("JWT token validated successfully for subject: #{payload['sub']}")
        true
      end

      # Validate opaque token using external validator
      def validate_opaque_token(token, required_scopes: nil)
        return false unless @opaque_token_validator

        result = @opaque_token_validator.call(token)
        return false unless result.is_a?(Hash) && result[:valid]

        # Validate scopes if provided
        validate_token_scopes(result[:scopes], required_scopes) if required_scopes && result[:scopes]

        @logger.debug('Opaque token validated successfully')
        true
      end

      # Decode and verify JWT token
      def decode_jwt(token, verify: true)
        parts = token.split('.')
        raise InvalidTokenError, 'Invalid JWT format' unless parts.length == 3

        header = JSON.parse(Base64.urlsafe_decode64(parts[0]))
        payload = JSON.parse(Base64.urlsafe_decode64(parts[1]))

        verify_jwt_signature(token, header) if verify

        [payload, header]
      rescue JSON::ParserError => e
        raise InvalidTokenError, "Invalid JWT format: #{e.message}"
      end

      # Verify JWT signature (simplified - in production use a proper JWT library)
      def verify_jwt_signature(token, header)
        algorithm = header['alg']

        case algorithm
        when 'HS256', 'HS384', 'HS512'
          verify_hmac_signature(token, algorithm)
        when 'RS256', 'RS384', 'RS512'
          verify_rsa_signature(token, algorithm, header)
        when 'none'
          raise InvalidTokenError, 'Unsigned tokens not allowed'
        else
          raise InvalidTokenError, "Unsupported algorithm: #{algorithm}"
        end
      end

      # Verify HMAC signature (for shared secret scenarios)
      def verify_hmac_signature(_token, algorithm)
        # This would require a shared secret - simplified implementation
        # In production, implement proper HMAC verification
        @logger.debug("HMAC signature verification not implemented (algorithm: #{algorithm})")
        true
      end

      # Verify RSA signature using JWKS
      def verify_rsa_signature(_token, algorithm, _header)
        # This would require JWKS key retrieval - simplified implementation
        # In production, implement proper RSA verification with JWKS
        @logger.debug("RSA signature verification not implemented (algorithm: #{algorithm})")
        true
      end

      # Validate JWT standard claims
      def validate_jwt_claims(payload)
        current_time = Time.now.to_i

        # Validate expiration
        if payload['exp'] && (payload['exp'] < (current_time - @clock_skew))
          raise ExpiredTokenError, 'Token has expired'
        end

        # Validate not before
        if payload['nbf'] && (payload['nbf'] > (current_time + @clock_skew))
          raise InvalidTokenError, 'Token not yet valid'
        end

        # Validate issued at (with clock skew)
        if payload['iat'] && (payload['iat'] > (current_time + @clock_skew))
          raise InvalidTokenError, 'Token issued in the future'
        end

        # Validate issuer
        if @issuer && payload['iss'] != @issuer
          raise InvalidTokenError, "Invalid issuer: expected #{@issuer}, got #{payload['iss']}"
        end

        # Validate audience
        return unless @audience

        token_audiences = Array(payload['aud'])
        return if token_audiences.include?(@audience)

        raise InvalidTokenError, "Invalid audience: expected #{@audience}, got #{token_audiences}"
      end

      # Validate token scopes
      def validate_token_scopes(token_scopes, required_scopes)
        token_scope_list = extract_scopes(token_scopes)
        required_scope_list = Array(required_scopes)

        missing_scopes = required_scope_list - token_scope_list
        raise InvalidScopeError, "Missing required scopes: #{missing_scopes.join(', ')}" unless missing_scopes.empty?

        @logger.debug("Scope validation passed: #{token_scope_list}")
      end

      # Extract scopes from token (handles both string and array formats)
      def extract_scopes(scopes)
        case scopes
        when String
          scopes.split
        when Array
          scopes
        else
          []
        end
      end
    end
  end
end
