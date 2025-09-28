# frozen_string_literal: true

RSpec.describe FastMcp::Transports::BaseTransport do
  let(:server) { instance_double(FastMcp::Server, logger: Logger.new(nil)) }
  let(:transport) { described_class.new(server) }

  describe '#initialize' do
    it 'initializes with server and logger' do
      expect(transport.server).to eq(server)
      expect(transport.logger).to eq(server.logger)
    end

    it 'accepts custom logger' do
      custom_logger = Logger.new(nil)
      transport = described_class.new(server, logger: custom_logger)
      expect(transport.logger).to eq(custom_logger)
    end
  end

  describe 'PROTOCOL_VERSION' do
    it 'defines the correct protocol version' do
      expect(described_class::PROTOCOL_VERSION).to eq('2025-06-18')
    end
  end

  describe '#valid_protocol_version?' do
    let(:logger) { instance_double(Logger) }
    let(:transport) { described_class.new(server, logger: logger) }

    context 'when no protocol version header is provided' do
      it 'returns true for empty headers' do
        expect(transport.send(:valid_protocol_version?, {})).to be(true)
      end

      it 'returns true when header is nil' do
        headers = { 'mcp-protocol-version' => nil }
        expect(transport.send(:valid_protocol_version?, headers)).to be(true)
      end

      it 'returns true when header is empty string' do
        headers = { 'mcp-protocol-version' => '' }
        expect(transport.send(:valid_protocol_version?, headers)).to be(true)
      end
    end

    context 'when protocol version header is provided' do
      it 'returns true for supported version' do
        headers = { 'mcp-protocol-version' => '2025-06-18' }
        expect(transport.send(:valid_protocol_version?, headers)).to be(true)
      end

      it 'returns false for unsupported version' do
        headers = { 'mcp-protocol-version' => '2024-11-05' }
        expect(logger).to receive(:warn).with(/Unsupported protocol version: 2024-11-05/)
        expect(transport.send(:valid_protocol_version?, headers)).to be(false)
      end

      it 'returns false for invalid version' do
        headers = { 'mcp-protocol-version' => 'invalid-version' }
        expect(logger).to receive(:warn).with(/Unsupported protocol version: invalid-version/)
        expect(transport.send(:valid_protocol_version?, headers)).to be(false)
      end

      it 'logs warning with expected version' do
        headers = { 'mcp-protocol-version' => '1.0.0' }
        expect(logger).to receive(:warn).with('Unsupported protocol version: 1.0.0, expected: 2025-06-18')
        transport.send(:valid_protocol_version?, headers)
      end
    end
  end

  describe '#protocol_version_error_response' do
    context 'when version is provided' do
      it 'returns error response with specific version' do
        response = transport.send(:protocol_version_error_response, '2024-11-05')

        expect(response).to eq({
                                 jsonrpc: '2.0',
                                 error: {
                                   code: -32_000,
                                   message: 'Unsupported protocol version: 2024-11-05',
                                   data: { expected_version: '2025-06-18' }
                                 },
                                 id: nil
                               })
      end
    end

    context 'when no version is provided' do
      it 'returns generic error response' do
        response = transport.send(:protocol_version_error_response)

        expect(response).to eq({
                                 jsonrpc: '2.0',
                                 error: {
                                   code: -32_000,
                                   message: 'Invalid protocol version',
                                   data: { expected_version: '2025-06-18' }
                                 },
                                 id: nil
                               })
      end
    end

    context 'when version is nil' do
      it 'returns generic error response' do
        response = transport.send(:protocol_version_error_response, nil)

        expect(response).to eq({
                                 jsonrpc: '2.0',
                                 error: {
                                   code: -32_000,
                                   message: 'Invalid protocol version',
                                   data: { expected_version: '2025-06-18' }
                                 },
                                 id: nil
                               })
      end
    end
  end

  describe '#process_message' do
    it 'delegates to server handle_request' do
      message = 'test message'
      headers = { 'content-type' => 'application/json' }

      expect(server).to receive(:handle_request).with(message, headers: headers)
      transport.process_message(message, headers: headers)
    end
  end

  describe 'abstract methods' do
    it 'raises NotImplementedError for start' do
      expect { transport.start }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for stop' do
      expect { transport.stop }.to raise_error(NotImplementedError)
    end

    it 'raises NotImplementedError for send_message' do
      expect { transport.send_message('test') }.to raise_error(NotImplementedError)
    end
  end
end

