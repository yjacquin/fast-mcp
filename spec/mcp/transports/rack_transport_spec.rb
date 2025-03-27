# frozen_string_literal: true

RSpec.describe FastMcp::Transports::RackTransport do
  let(:server) { instance_double(FastMcp::Server, logger: Logger.new(nil), transport: nil) }
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:logger) { Logger.new(nil) }
  let(:transport) { described_class.new(app, server, logger: logger) }

  describe '#initialize' do
    it 'initializes with server, app, and options' do
      expect(transport.server).to eq(server)
      expect(transport.app).to eq(app)
      expect(transport.logger).to eq(logger)
      expect(transport.path_prefix).to eq('/mcp')
      expect(transport.sse_clients).to eq({})
    end

    it 'accepts custom path prefix' do
      custom_transport = described_class.new(server, app, path_prefix: '/api/mcp', logger: logger)
      expect(custom_transport.path_prefix).to eq('/api/mcp')
    end
  end

  describe '#start' do
    it 'starts the transport' do
      expect(logger).to receive(:debug).with(/Starting Rack transport/)
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
                                          'client1' => { stream: client1_stream },
                                          'client2' => { stream: client2_stream }
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
                                          'client' => { stream: client_stream }
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

        transport.instance_variable_set(:@sse_clients, { 'test-client' => { stream: client_stream } })

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

    it 'returns 404 for unknown MCP endpoints' do
      env = { 'PATH_INFO' => '/mcp/invalid-endpoint' }

      expect(server).to receive(:transport=).with(transport)

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
        env = { 'PATH_INFO' => '/mcp/' }
        expect(server).to receive(:transport=).with(transport)

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
          'rack.hijack' => -> {}
        }

        # Mock the hijack IO
        io = double('io')
        allow(io).to receive(:write)
        allow(io).to receive(:closed?).and_return(false)
        allow(io).to receive(:flush)
        allow(io).to receive(:close)
        env['rack.hijack_io'] = io
        allow(env['rack.hijack']).to receive(:call)

        expect(server).to receive(:transport=).with(transport)

        # We can't fully test the SSE connection setup because it involves
        # thread creation and complex IO operations, but we can test the
        # initial response headers
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
          'REQUEST_METHOD' => 'POST'
        }
        expect(server).to receive(:transport=).with(transport)

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
          'CONTENT_TYPE' => 'application/json'
        }
        expect(server).to receive(:transport=).with(transport)

        # Mock the server's handle_json_request method
        expect(server).to receive(:handle_json_request)
          .with('{"jsonrpc":"2.0","method":"ping","id":1}')
          .and_return('{"jsonrpc":"2.0","result":{},"id":1}')

        result = transport.call(env)

        expect(result[0]).to eq(200)
        expect(result[1]['Content-Type']).to eq('application/json')
        expect(result[2].first).to eq('{"jsonrpc":"2.0","result":{},"id":1}')
      end

      it 'handles errors in JSON-RPC requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'rack.input' => StringIO.new('invalid json'),
          'CONTENT_TYPE' => 'application/json'
        }
        expect(server).to receive(:transport=).with(transport)

        # Mock the behavior to simulate a JSON parse error when processing the message
        allow(transport).to receive(:process_message).and_raise(JSON::ParserError.new('Invalid JSON'))

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
          'REQUEST_METHOD' => 'GET'
        }
        expect(server).to receive(:transport=).with(transport)

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
end
