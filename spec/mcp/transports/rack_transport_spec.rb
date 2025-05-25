# frozen_string_literal: true

RSpec.describe FastMcp::Transports::RackTransport do
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:server) do 
    instance_double(FastMcp::Server, 
      logger: Logger.new(nil), 
      transport: nil, 
      'transport=' => nil,
      has_filters?: false,
      handle_request: StringIO.new('{"jsonrpc":"2.0","result":{},"id":1}')
    )
  end
  let(:logger) { Logger.new(nil) }
  let(:transport) { described_class.new(app, server, logger: logger, localhost_only: localhost_only) }
  let(:localhost_only) { true }

  describe '#initialize' do
    it 'initializes with server, app, and options' do
      expect(transport.server).to eq(server)
      expect(transport.app).to eq(app)
      expect(transport.logger).to eq(logger)
      expect(transport.path_prefix).to eq('/mcp')
      expect(transport.sse_clients).to eq({})
      expect(transport.localhost_only).to eq(localhost_only)
    end

    it 'accepts custom path prefix' do
      custom_transport = described_class.new(server, app, path_prefix: '/api/mcp', logger: logger)
      expect(custom_transport.path_prefix).to eq('/api/mcp')
    end
  end

  describe '#start' do
    it 'starts the transport' do
      expect(logger).to receive(:debug).with(/Starting Rack transport/)
      expect(logger).to receive(:debug).with(/DNS rebinding protection enabled/)
      transport.start
      expect(transport.instance_variable_get(:@running)).to be(true)
    end
  end

  describe '#stop' do
    it 'stops the transport and closes SSE connections' do
      # Add a mock SSE client
      client_stream = double('stream')
      expect(client_stream).to receive(:respond_to?).with(:close).and_return(true)
      expect(client_stream).to receive(:closed?).and_return(false)
      expect(client_stream).to receive(:close)

      transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream } })
      transport.instance_variable_set(:@running, true)

      expect(logger).to receive(:debug).with('Stopping Rack transport')
      transport.stop

      expect(transport.instance_variable_get(:@running)).to be(false)
      expect(transport.sse_clients).to be_empty
    end

    it 'handles errors when closing SSE connections' do
      # Add a mock SSE client that raises an error when closed
      client_stream = double('stream')
      expect(client_stream).to receive(:respond_to?).with(:close).and_return(true)
      expect(client_stream).to receive(:closed?).and_return(false)
      expect(client_stream).to receive(:close).and_raise(StandardError.new('Test error'))

      transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream } })
      transport.instance_variable_set(:@running, true)

      expect(logger).to receive(:debug).with('Stopping Rack transport')
      expect(logger).to receive(:error).with(/Error closing SSE connection/)

      transport.stop

      expect(transport.instance_variable_get(:@running)).to be(false)
      expect(transport.sse_clients).to be_empty
    end
  end

  describe '#send_message' do
    context 'with multiple clients' do
      it 'sends a message to all SSE clients' do
        # Add mock SSE clients
        client1_stream = double('stream1')
        client2_stream = double('stream2')

        expect(client1_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client1_stream).to receive(:closed?).and_return(false)
        expect(client1_stream).to receive(:write).with("data: {\"test\":\"message\"}\n\n")
        expect(client1_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client1_stream).to receive(:flush)

        expect(client2_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client2_stream).to receive(:closed?).and_return(false)
        expect(client2_stream).to receive(:write).with("data: {\"test\":\"message\"}\n\n")
        expect(client2_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client2_stream).to receive(:flush)

        transport.instance_variable_set(:@sse_clients, {
                                          'client1' => { stream: client1_stream, mutex: Mutex.new },
                                          'client2' => { stream: client2_stream, mutex: Mutex.new }
                                        })

        expect(logger).to receive(:debug).with(/Broadcasting message to 2 SSE clients/)

        transport.send_message({ test: 'message' })
      end
    end

    context 'with different message types' do
      it 'handles string messages' do
        client_stream = double('stream')
        expect(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client_stream).to receive(:closed?).and_return(false)
        expect(client_stream).to receive(:write).with("data: test message\n\n")
        expect(client_stream).to receive(:respond_to?).with(:flush).and_return(true)
        expect(client_stream).to receive(:flush)

        transport.instance_variable_set(:@sse_clients, {
                                          'client' => { stream: client_stream, mutex: Mutex.new }
                                        })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)

        transport.send_message('test message')
      end
    end

    context 'with error handling' do
      it 'handles errors when sending to clients' do
        # Add a mock SSE client that raises an error
        client_stream = double('stream')
        expect(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        expect(client_stream).to receive(:closed?).and_return(false)
        expect(client_stream).to receive(:write).and_raise(StandardError.new('Test error'))

        transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream, mutex: Mutex.new } })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)
        expect(logger).to receive(:error).with(/Error sending message to client test-client/)
        expect(logger).to receive(:info).with(/Unregistering SSE client: test-client/)

        transport.send_message({ test: 'message' })

        # The client should be removed after the error
        expect(transport.sse_clients).to be_empty
      end

      it 'handles errors when mutex raises exception' do
        # Add a mock SSE client that raises an error
        client_stream = double('stream')
        allow(client_stream).to receive(:respond_to?).and_return(false)
        allow(client_stream).to receive(:respond_to?).with(:closed?).and_return(true)
        allow(client_stream).to receive(:respond_to?).with(:flush).and_return(true)
        allow(client_stream).to receive(:closed?).and_return(false)
        allow(client_stream).to receive(:write)
        allow(client_stream).to receive(:flush)

        # Create a client with a mutex that will raise an error
        client_mutex = double('mutex')
        allow(client_mutex).to receive(:synchronize).and_raise(StandardError.new('Mutex error'))

        transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream, mutex: client_mutex } })

        expect(logger).to receive(:debug).with(/Broadcasting message to 1 SSE clients/)
        expect(logger).to receive(:error).with(/Error sending message to client test-client/)
        expect(logger).to receive(:info).with(/Unregistering SSE client: test-client/)

        transport.send_message({ test: 'message' })

        # The client should be removed after the error
        expect(transport.sse_clients).to be_empty
      end
    end
  end

  describe '#call' do
    it 'passes non-MCP requests to the app' do
      env = { 'PATH_INFO' => '/not-mcp' }
      expect(app).to receive(:call).with(env).and_return([200, {}, ['OK']])

      result = transport.call(env)
      expect(result).to eq([200, {}, ['OK']])
    end

    context 'with DNS rebinding protection' do
      let(:allowed_origins) { ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/] }
      let(:transport) do
        described_class.new(
          app,
          server,
          logger: logger,
          allowed_origins: allowed_origins,
          localhost_only: true,
          allowed_ips: ['127.0.0.1', '192.168.0.1']
        )
      end


      it 'accepts requests with allowed origin' do
        # Create request env
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://localhost',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(200)
      end

      it 'refuses requests with disallowed origin' do
        # Create request env
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://disallowed.com',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(403)
        expect(result[1]['Content-Type']).to eq('application/json')
        expect(result[2]).to eq([JSON.generate(
          {
            jsonrpc: '2.0',
            error: {
              code: -32_600,
              message: 'Forbidden: Origin validation failed'
            },
            id: nil
          })])
      end

      it 'refuses requests with disallowed ip' do
        # Create request env
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://localhost',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        # Create a proper request double that includes necessary methods
        request = instance_double(Rack::Request,
          ip: '127.0.0.2',
          path: '/mcp/messages',
          post?: true,
          params: {},
          body: instance_double(StringIO, read: '{"jsonrpc":"2.0","method":"ping","id":1}'),
          host: 'localhost'
        )
        allow(Rack::Request).to receive(:new).with(env).and_return(request)

        expect(server).to receive(:transport=).with(transport)
        expect(server).to receive(:handle_json_request).never

        result = transport.call(env)
        expect(result[0]).to eq(403)
        expect(result[1]['Content-Type']).to eq('application/json')
        expect(result[2]).to eq([JSON.generate(
          {
            jsonrpc: '2.0',
            error: {
              code: -32_600,
              message: 'Forbidden: Remote IP not allowed'
            },
            id: nil
          })])
      end

      it 'accepts requests with origin matching a regex pattern' do
        # Test with an origin matching a regex
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'https://sub.example.com',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(200)
      end

      it 'rejects requests with disallowed origin' do
        # Test with a disallowed origin
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_ORIGIN' => 'http://evil-site.com',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(403)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_600)
        expect(response['error']['message']).to include('Origin validation failed')
      end

      it 'falls back to Referer header when Origin is not present' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_REFERER' => 'http://localhost/some/path',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(200)
      end

      it 'falls back to Host header when Origin and Referer are not present' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'HTTP_HOST' => 'localhost:3000',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }

        result = transport.call(env)
        expect(result[0]).to eq(200)
      end
    end

    it 'returns 404 for unknown MCP endpoints' do
      env = { 'PATH_INFO' => '/mcp/invalid-endpoint', 'REMOTE_ADDR' => '127.0.0.1' }

      result = transport.call(env)

      expect(result[0]).to eq(404)
      expect(result[1]['Content-Type']).to eq('application/json')

      response = JSON.parse(result[2].first)
      expect(response['jsonrpc']).to eq('2.0')
      expect(response['error']['code']).to eq(-32_601)
      expect(response['error']['message']).to include('Endpoint not found')
    end

    context 'with root MCP endpoint' do
      it 'handles root MCP endpoint requests' do
        # The default route handler doesn't have a special case for root requests
        # so we expect a 404 response with "Endpoint not found" message
        env = { 'PATH_INFO' => '/mcp', 'REMOTE_ADDR' => '127.0.0.1'
 }
        result = transport.call(env)

        # This should match the endpoint_not_found_response method behavior
        expect(result[0]).to eq(404)
        expect(result[1]['Content-Type']).to eq('application/json')
        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_601)
        expect(response['error']['message']).to eq('Endpoint not found')
      end
    end

    context 'with SSE requests' do
      it 'handles SSE requests with rack hijack' do
        env = {
          'PATH_INFO' => '/mcp/sse',
          'REQUEST_METHOD' => 'GET',
          'rack.hijack?' => true,
          'rack.hijack' => -> {},
          'REMOTE_ADDR' => '127.0.0.1',
          'QUERY_STRING' => 'foo=example&bar=baz'
        }

        # Mock the hijack IO
        io = double('io')
        allow(io).to receive(:write)
        allow(io).to receive(:closed?).and_return(false)
        allow(io).to receive(:flush)
        allow(io).to receive(:close)
        env['rack.hijack_io'] = io
        allow(env['rack.hijack']).to receive(:call)

        result = transport.call(env)

        # The result should be [-1, {}, []] for async response
        expect(result[0]).to eq(-1)
        expect(result[1]).to eq({})
        expect(result[2]).to eq([])

        # Verify that the hijack was called
        expect(env['rack.hijack']).to have_received(:call)
      end

      it 'returns 405 for non-GET SSE requests' do
        env = {
          'PATH_INFO' => '/mcp/sse',
          'REQUEST_METHOD' => 'POST',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        result = transport.call(env)

        expect(result[0]).to eq(405)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_601)
        expect(response['error']['message']).to include('Method not allowed')
      end
    end

    context 'with JSON-RPC requests' do
      it 'handles valid JSON-RPC requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}'),
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1'
        }

        result = transport.call(env)

        expect(result[0]).to eq(200)
        expect(result[1]['Content-Type']).to eq('application/json')
        expect(result[2]).to be_a(Array)
      end

      it 'handles errors in JSON-RPC requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'rack.input' => StringIO.new('invalid json'),
          'CONTENT_TYPE' => 'application/json',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        
        # Mock the server to return a parse error
        allow(server).to receive(:handle_request).and_raise(JSON::ParserError, 'Invalid JSON')

        result = transport.call(env)

        expect(result[0]).to eq(400)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_700)
        expect(response['error']['message']).to include('Parse error')
      end

      it 'returns 405 for non-POST message requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'GET',
          'REMOTE_ADDR' => '127.0.0.1'
        }
        result = transport.call(env)

        expect(result[0]).to eq(405)
        expect(result[1]['Content-Type']).to eq('application/json')
        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_601)
        expect(response['error']['message']).to include('Method not allowed')
      end
    end
  end

  # Tests for private methods
  describe '#validate_origin (private)' do
    let(:allowed_origins) { ['localhost', '127.0.0.1', 'example.com', /.*\.example\.com/] }
    let(:transport) { described_class.new(app, server, logger: logger, allowed_origins: allowed_origins) }

    it 'validates origins correctly' do
      request = instance_double('Rack::Request', host: 'localhost:3000')

      # Test allowed origins
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://localhost'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://127.0.0.1'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'https://example.com'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'https://sub.example.com'})).to be true

      # Test disallowed origins
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://evil.com'})).to be false
      expect(transport.send(:validate_origin, request, {'HTTP_ORIGIN' => 'http://sub.evil.com'})).to be false
    end

    it 'falls back to referer when origin is missing' do
      request = instance_double('Rack::Request', host: 'localhost:3000')

      # Test with referer only
      expect(transport.send(:validate_origin, request, {'HTTP_REFERER' => 'http://localhost/path'})).to be true
      expect(transport.send(:validate_origin, request, {'HTTP_REFERER' => 'http://evil.com/path'})).to be false
    end

    it 'falls back to host when origin and referer are missing' do
      # Test with host only (from request)
      request = instance_double('Rack::Request', host: 'localhost:3000')
      expect(transport.send(:validate_origin, request, {})).to be true

      request = instance_double('Rack::Request', host: 'evil.com:3000')
      expect(transport.send(:validate_origin, request, {})).to be false
    end
  end

  describe '#extract_hostname (private)' do
    let(:transport) { described_class.new(app, server, logger: logger) }

    it 'extracts hostname from URLs correctly' do
      expect(transport.send(:extract_hostname, 'http://localhost')).to eq('localhost')
      expect(transport.send(:extract_hostname, 'https://example.com')).to eq('example.com')
      expect(transport.send(:extract_hostname, 'http://sub.domain.example.com:8080/path')).to eq('sub.domain.example.com')
    end

    it 'handles URLs without scheme by adding a dummy scheme' do
      expect(transport.send(:extract_hostname, 'localhost')).to eq('localhost')
      expect(transport.send(:extract_hostname, 'example.com')).to eq('example.com')
      expect(transport.send(:extract_hostname, 'sub.example.com:8080')).to eq('sub.example.com')
    end

    it 'returns nil for empty or nil URLs' do
      expect(transport.send(:extract_hostname, nil)).to be_nil
      expect(transport.send(:extract_hostname, '')).to be_nil
    end

    it 'gracefully handles invalid URLs' do
      expect(transport.send(:extract_hostname, 'not a url')).to eq('not a url')
      expect(transport.send(:extract_hostname, 'http://')).to be_nil
    end
  end
end
