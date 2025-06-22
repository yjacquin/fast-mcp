# frozen_string_literal: true

require 'base64'
require 'digest'
require 'securerandom'

module FastMcp
  module OAuth
    # PKCE (Proof Key for Code Exchange) implementation for OAuth 2.1
    # RFC 7636: https://tools.ietf.org/html/rfc7636
    class PKCE
      # PKCE code challenge methods
      CHALLENGE_METHODS = %w[S256 plain].freeze

      # Minimum and maximum code verifier lengths (RFC 7636)
      MIN_VERIFIER_LENGTH = 43
      MAX_VERIFIER_LENGTH = 128

      # Valid characters for code verifier (RFC 7636)
      VERIFIER_CHARS = ('A'..'Z').to_a + ('a'..'z').to_a + ('0'..'9').to_a + ['-', '.', '_', '~']

      attr_reader :code_verifier, :code_challenge, :code_challenge_method

      # Initialize PKCE with optional parameters
      def initialize(code_verifier: nil, code_challenge_method: 'S256')
        @code_challenge_method = validate_challenge_method(code_challenge_method)
        @code_verifier = code_verifier || generate_code_verifier
        @code_challenge = generate_code_challenge(@code_verifier, @code_challenge_method)

        validate_code_verifier(@code_verifier)
      end

      # Generate authorization URL parameters for PKCE
      def authorization_params
        {
          'code_challenge' => @code_challenge,
          'code_challenge_method' => @code_challenge_method
        }
      end

      # Generate token request parameters for PKCE
      def token_params
        {
          'code_verifier' => @code_verifier
        }
      end

      # Verify code challenge against code verifier
      def verify_challenge(code_verifier, code_challenge, method = 'S256')
        expected_challenge = generate_code_challenge(code_verifier, method)
        secure_compare(expected_challenge, code_challenge)
      end

      # Validate PKCE parameters from authorization request
      def self.validate_authorization_request(params)
        code_challenge = params['code_challenge']
        method = params['code_challenge_method'] || 'plain'

        raise ArgumentError, 'Missing code_challenge parameter' unless code_challenge
        raise ArgumentError, "Invalid code_challenge_method: #{method}" unless CHALLENGE_METHODS.include?(method)

        # Validate code challenge format
        if method == 'S256'
          # For S256, challenge should be base64url-encoded
          raise ArgumentError, 'Invalid code_challenge format for S256' unless valid_base64url?(code_challenge)
        else
          # For plain, challenge should be valid verifier
          validate_code_verifier(code_challenge)
        end

        { code_challenge: code_challenge, code_challenge_method: method }
      end

      # Validate PKCE parameters from token request
      def self.validate_token_request(params, stored_challenge, stored_method)
        code_verifier = params['code_verifier']
        raise ArgumentError, 'Missing code_verifier parameter' unless code_verifier

        validate_code_verifier(code_verifier)

        # Verify the challenge
        expected_challenge = generate_code_challenge(code_verifier, stored_method)
        raise ArgumentError, 'Invalid code_verifier' unless secure_compare(expected_challenge, stored_challenge)

        true
      end

      private

      # Generate a cryptographically secure code verifier
      def generate_code_verifier(length = MIN_VERIFIER_LENGTH)
        # Use SecureRandom to generate random bytes, then encode safely
        random_bytes = SecureRandom.random_bytes(length)
        Base64.urlsafe_encode64(random_bytes, padding: false)[0, length]
      end

      # Generate code challenge from verifier
      def generate_code_challenge(verifier, method)
        case method
        when 'S256'
          digest = Digest::SHA256.digest(verifier)
          Base64.urlsafe_encode64(digest, padding: false)
        when 'plain'
          verifier
        else
          raise ArgumentError, "Unsupported challenge method: #{method}"
        end
      end

      # Validate challenge method
      def validate_challenge_method(method)
        unless CHALLENGE_METHODS.include?(method)
          raise ArgumentError,
                "Invalid code_challenge_method: #{method}. Must be one of: #{CHALLENGE_METHODS.join(', ')}"
        end

        method
      end

      # Validate code verifier format and length
      def self.validate_code_verifier(verifier)
        if verifier.length < MIN_VERIFIER_LENGTH || verifier.length > MAX_VERIFIER_LENGTH
          raise ArgumentError, "Code verifier length must be between #{MIN_VERIFIER_LENGTH} and #{MAX_VERIFIER_LENGTH}"
        end

        # Check for valid characters
        unless verifier.chars.all? { |c| VERIFIER_CHARS.include?(c) }
          raise ArgumentError, 'Code verifier contains invalid characters'
        end

        true
      end

      # Validate code verifier (instance method)
      def validate_code_verifier(verifier)
        self.class.validate_code_verifier(verifier)
      end

      # Check if string is valid base64url
      def self.valid_base64url?(string)
        # Base64url uses A-Z, a-z, 0-9, -, _ and no padding
        string.match?(/\A[A-Za-z0-9\-_]+\z/)
      end

      # Secure string comparison to prevent timing attacks
      def self.secure_compare(a, b)
        return false unless a.length == b.length

        result = 0
        a.bytes.zip(b.bytes) { |x, y| result |= x ^ y }
        result.zero?
      end

      # Instance method for secure comparison
      def secure_compare(a, b)
        self.class.secure_compare(a, b)
      end
    end
  end
end
