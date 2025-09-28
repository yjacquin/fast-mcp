# frozen_string_literal: true

RSpec.describe FastMcp::OAuth::TokenValidator do
  let(:logger) { Logger.new(nil) }
  let(:validator) { described_class.new(logger: logger) }

  describe '#initialize' do
    it 'initializes with default options' do
      expect(validator.logger).to eq(logger)
      expect(validator.required_scopes).to eq([])
    end

    it 'accepts configuration options' do
      validator = described_class.new(
        issuer: 'https://auth.example.com',
        audience: 'mcp-api',
        required_scopes: ['mcp:read', 'mcp:write']
      )

      expect(validator.issuer).to eq('https://auth.example.com')
      expect(validator.audience).to eq('mcp-api')
      expect(validator.required_scopes).to eq(['mcp:read', 'mcp:write'])
    end
  end

  describe '#validate_token' do
    context 'with nil or empty tokens' do
      it 'returns false for nil token' do
        expect(validator.validate_token(nil)).to be(false)
      end

      it 'returns false for empty token' do
        expect(validator.validate_token('')).to be(false)
      end
    end

    context 'with opaque tokens' do
      let(:opaque_token) { 'abc123def456' }

      it 'returns false when no opaque validator is configured' do
        expect(validator.validate_token(opaque_token)).to be(false)
      end

      it 'uses opaque token validator when configured' do
        opaque_validator = ->(token) { { valid: token == 'valid_token', scopes: ['mcp:read'] } }
        validator = described_class.new(opaque_token_validator: opaque_validator)

        expect(validator.validate_token('valid_token')).to be(true)
        expect(validator.validate_token('invalid_token')).to be(false)
      end

      it 'validates scopes with opaque tokens' do
        opaque_validator = ->(_token) { { valid: true, scopes: ['mcp:read'] } }
        validator = described_class.new(opaque_token_validator: opaque_validator)

        expect(validator.validate_token('token', required_scopes: ['mcp:read'])).to be(true)
        expect(validator.validate_token('token', required_scopes: ['mcp:write'])).to be(false)
      end
    end

    context 'with JWT tokens' do
      let(:valid_jwt_header) { Base64.urlsafe_encode64(JSON.generate(typ: 'JWT', alg: 'HS256')) }
      let(:valid_payload) do
        {
          sub: 'user123',
          iss: 'https://auth.example.com',
          aud: 'mcp-api',
          exp: Time.now.to_i + 3600,
          iat: Time.now.to_i,
          scope: 'mcp:read mcp:write'
        }
      end
      let(:encoded_payload) { Base64.urlsafe_encode64(JSON.generate(valid_payload)) }
      let(:signature) { 'fake_signature' }
      let(:jwt_token) { "#{valid_jwt_header}.#{encoded_payload}.#{signature}" }

      it 'recognizes JWT tokens' do
        expect(validator.send(:jwt_token?, jwt_token)).to be(true)
      end

      it 'validates JWT tokens (simplified validation)' do
        # Configure validator with HMAC secret for HS256 algorithm
        validator = described_class.new(hmac_secret: 'test_secret', logger: logger)

        # Mock JWT.decode to return valid payload with string keys
        valid_payload_with_string_keys = valid_payload.transform_keys(&:to_s)
        allow(JWT).to receive(:decode).and_return([valid_payload_with_string_keys, { 'alg' => 'HS256' }])

        expect(validator.validate_token(jwt_token)).to be(true)
      end

      it 'rejects expired JWT tokens' do
        expired_payload = valid_payload.merge(exp: Time.now.to_i - 3600)
        expired_encoded = Base64.urlsafe_encode64(JSON.generate(expired_payload))
        expired_jwt = "#{valid_jwt_header}.#{expired_encoded}.#{signature}"

        validator = described_class.new(hmac_secret: 'test_secret', logger: logger)
        # Mock JWT decode to return expired payload with string keys, then let validation logic run
        expired_payload_with_string_keys = expired_payload.transform_keys(&:to_s)
        allow(JWT).to receive(:decode).and_return([expired_payload_with_string_keys, { 'alg' => 'HS256' }])

        expect(validator.validate_token(expired_jwt)).to be(false)
      end

      it 'validates JWT token scopes' do
        validator = described_class.new(hmac_secret: 'test_secret', logger: logger)
        # Mock JWT decode to return valid payload with string keys
        valid_payload_with_string_keys = valid_payload.transform_keys(&:to_s)
        allow(JWT).to receive(:decode).and_return([valid_payload_with_string_keys, { 'alg' => 'HS256' }])

        expect(validator.validate_token(jwt_token, required_scopes: ['mcp:read'])).to be(true)
        expect(validator.validate_token(jwt_token, required_scopes: ['mcp:admin'])).to be(false)
      end
    end
  end

  describe '#extract_claims' do
    let(:jwt_header) { Base64.urlsafe_encode64(JSON.generate(typ: 'JWT', alg: 'HS256')) }
    let(:payload) { { sub: 'user123', scope: 'mcp:read' } }
    let(:encoded_payload) { Base64.urlsafe_encode64(JSON.generate(payload)) }
    let(:jwt_token) { "#{jwt_header}.#{encoded_payload}.signature" }

    it 'extracts claims from JWT tokens' do
      # Mock JWT.decode to return the payload when called without verification
      payload_with_string_keys = payload.transform_keys(&:to_s)
      allow(JWT).to receive(:decode).with(jwt_token, nil,
                                          false).and_return([payload_with_string_keys, { 'alg' => 'HS256' }])

      claims = validator.extract_claims(jwt_token)
      expect(claims).to include('sub' => 'user123', 'scope' => 'mcp:read')
    end

    it 'returns nil for non-JWT tokens' do
      expect(validator.extract_claims('opaque_token')).to be_nil
    end

    it 'returns nil for malformed tokens' do
      expect(validator.extract_claims('invalid.jwt')).to be_nil
    end
  end

  describe 'scope validation' do
    it 'handles string scopes' do
      scopes = validator.send(:extract_scopes, 'mcp:read mcp:write')
      expect(scopes).to eq(['mcp:read', 'mcp:write'])
    end

    it 'handles array scopes' do
      scopes = validator.send(:extract_scopes, ['mcp:read', 'mcp:write'])
      expect(scopes).to eq(['mcp:read', 'mcp:write'])
    end

    it 'handles nil scopes' do
      scopes = validator.send(:extract_scopes, nil)
      expect(scopes).to eq([])
    end
  end

  describe 'error handling' do
    let(:logger_output) { StringIO.new }
    let(:logger) { Logger.new(logger_output) }
    let(:validator) { described_class.new(logger: logger, hmac_secret: 'lol') }

    it 'logs validation failures' do
      # Create a malformed JWT that will trigger an error during validation
      malformed_jwt = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.invalid_payload.signature'
      result = validator.validate_token(malformed_jwt)

      # Check that validation failed and error was logged
      expect(result).to be(false)
      logger_output.rewind
      log_content = logger_output.read
      puts 'hah'
      expect(log_content).to match(/Token validation failed: HMAC secret not configured/)
    end

    it 'logs unexpected errors' do
      logger_output = StringIO.new
      validator = described_class.new(logger: Logger.new(logger_output))

      allow(validator).to receive(:jwt_token?).and_raise(StandardError, 'Unexpected error')
      validator.validate_token('some_token')

      logger_output.rewind
      log_content = logger_output.read
      expect(log_content).to match(/Unexpected error during token validation/)
    end
  end
end
