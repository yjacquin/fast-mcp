# frozen_string_literal: true

require 'base64'
require 'json'
require 'jwt'
require 'net/http'
require 'openssl'
require 'uri'

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
        @clock_skew = options.fetch(:clock_skew, 60) # 60 seconds default clock skew
        @hmac_secret = options[:hmac_secret]
        @jwks_cache = {}
        @jwks_cache_mutex = Mutex.new
        @jwks_cache_ttl = options.fetch(:jwks_cache_ttl, 300) # 5 minutes default
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

        # Decode without verification for claim extraction
        payload, = JWT.decode(token, nil, false)
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
        payload = decode_and_verify_jwt(token)

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

      # Decode and verify JWT token using proper JWT library
      def decode_and_verify_jwt(token)
        # Extract algorithm from header without verification
        header = JSON.parse(Base64.urlsafe_decode64(token.split('.')[0]))
        algorithm = header['alg']

        case algorithm
        when 'HS256', 'HS384', 'HS512'
          decode_hmac_jwt(token, algorithm)
        when 'RS256', 'RS384', 'RS512', 'ES256', 'ES384', 'ES512'
          decode_rsa_jwt(token, algorithm, header)
        when 'none'
          raise InvalidTokenError, 'Unsigned tokens not allowed'
        else
          raise InvalidTokenError, "Unsupported algorithm: #{algorithm}"
        end
      rescue JSON::ParserError => e
        raise InvalidTokenError, "Invalid JWT format: #{e.message}"
      rescue JWT::DecodeError => e
        raise InvalidTokenError, "JWT verification failed: #{e.message}"
      end

      # Decode HMAC-signed JWT
      def decode_hmac_jwt(token, algorithm)
        raise InvalidTokenError, 'HMAC secret not configured' unless @hmac_secret

        payload, = JWT.decode(
          token,
          @hmac_secret,
          true,
          {
            algorithm: algorithm,
            iss: @issuer,
            aud: @audience,
            verify_iss: !@issuer.nil?,
            verify_aud: !@audience.nil?
          }
        )

        @logger.debug("HMAC JWT verified successfully (algorithm: #{algorithm})")
        payload
      end

      # Decode RSA/EC-signed JWT using JWKS
      def decode_rsa_jwt(token, algorithm, header)
        kid = header['kid']
        key = fetch_verification_key(kid, algorithm)

        payload, = JWT.decode(
          token,
          key,
          true,
          {
            algorithm: algorithm,
            iss: @issuer,
            aud: @audience,
            verify_iss: !@issuer.nil?,
            verify_aud: !@audience.nil?
          }
        )

        @logger.debug("RSA/EC JWT verified successfully (algorithm: #{algorithm})")
        payload
      end

      # Fetch verification key from JWKS
      def fetch_verification_key(kid, algorithm)
        raise InvalidTokenError, 'JWKS URI not configured for RSA/EC verification' unless @jwks_uri

        jwks = fetch_jwks
        key_data = find_key_in_jwks(jwks, kid, algorithm)
        convert_jwk_to_key(key_data)
      end

      # Fetch JWKS with caching
      def fetch_jwks
        @jwks_cache_mutex.synchronize do
          cache_entry = @jwks_cache[@jwks_uri]

          return cache_entry[:jwks] if cache_entry && (Time.now - cache_entry[:fetched_at]) < @jwks_cache_ttl

          @logger.debug("Fetching JWKS from #{@jwks_uri}")
          jwks = fetch_jwks_from_uri
          @jwks_cache[@jwks_uri] = { jwks: jwks, fetched_at: Time.now }
          jwks
        end
      end

      # Fetch JWKS from URI
      def fetch_jwks_from_uri
        uri = URI(@jwks_uri)
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise InvalidTokenError, "Failed to fetch JWKS: #{response.code} #{response.message}"
        end

        JSON.parse(response.body)
      rescue StandardError => e
        raise InvalidTokenError, "JWKS fetch error: #{e.message}"
      end

      # Find key in JWKS
      def find_key_in_jwks(jwks, kid, algorithm)
        keys = jwks['keys'] || []

        # If kid is provided, find by kid
        if kid
          key = keys.find { |k| k['kid'] == kid }
          raise InvalidTokenError, "Key with kid '#{kid}' not found in JWKS" unless key
        else
          # Otherwise, find by algorithm and use
          key = keys.find { |k| k['alg'] == algorithm && k['use'] == 'sig' }
          key ||= keys.find { |k| k['kty'] == key_type_for_algorithm(algorithm) }
          raise InvalidTokenError, "No suitable key found for algorithm '#{algorithm}'" unless key
        end

        key
      end

      # Convert JWK to OpenSSL key
      def convert_jwk_to_key(jwk)
        case jwk['kty']
        when 'RSA'
          convert_rsa_jwk_to_key(jwk)
        when 'EC'
          convert_ec_jwk_to_key(jwk)
        else
          raise InvalidTokenError, "Unsupported key type: #{jwk['kty']}"
        end
      end

      # Convert RSA JWK to OpenSSL key
      def convert_rsa_jwk_to_key(jwk)
        n = Base64.urlsafe_decode64(jwk['n'])
        e = Base64.urlsafe_decode64(jwk['e'])

        key = OpenSSL::PKey::RSA.new
        key.set_key(OpenSSL::BN.new(n, 2), OpenSSL::BN.new(e, 2), nil)
        key
      rescue StandardError => e
        raise InvalidTokenError, "Failed to convert RSA JWK: #{e.message}"
      end

      # Convert EC JWK to OpenSSL key
      def convert_ec_jwk_to_key(jwk)
        curve_name = case jwk['crv']
                     when 'P-256' then 'prime256v1'
                     when 'P-384' then 'secp384r1'
                     when 'P-521' then 'secp521r1'
                     else
                       raise InvalidTokenError, "Unsupported EC curve: #{jwk['crv']}"
                     end

        x = Base64.urlsafe_decode64(jwk['x'])
        y = Base64.urlsafe_decode64(jwk['y'])

        group = OpenSSL::PKey::EC::Group.new(curve_name)
        point = OpenSSL::PKey::EC::Point.new(group)
        point.set_to_coordinates(OpenSSL::BN.new(x, 2), OpenSSL::BN.new(y, 2))

        key = OpenSSL::PKey::EC.new(group)
        key.public_key = point
        key
      rescue StandardError => e
        raise InvalidTokenError, "Failed to convert EC JWK: #{e.message}"
      end

      # Get key type for algorithm
      def key_type_for_algorithm(algorithm)
        case algorithm
        when /\ARS/
          'RSA'
        when /\AES/
          'EC'
        else
          raise InvalidTokenError, "Cannot determine key type for algorithm: #{algorithm}"
        end
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
