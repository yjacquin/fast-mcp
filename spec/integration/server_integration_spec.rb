# frozen_string_literal: true

require 'stringio'

RSpec.describe 'MCP Server Integration' do
  let(:server) { FastMcp::Server.new(name: 'test-server', version: '1.0.0', logger: Logger.new(nil)) }
  let(:transport) { FastMcp::Transports::StdioTransport.new(server) }

  # Define a test tool class
  let(:greet_tool) do
    Class.new(FastMcp::Tool) do
      def self.name
        'greet'
      end

      def self.description
        'Greet a person'
      end

      arguments do
        required(:name).filled(:string).description('Name to greet')
      end

      def call(name:)
        "Hello, #{name}!"
      end
    end
  end

  # Define a test resource class
  let(:counter_resource_class) do
    Class.new(FastMcp::Resource) do
      uri 'test/counter'
      resource_name 'Test Counter'
      description 'A test counter resource'
      mime_type 'application/json'

      def content
        JSON.generate({ count: 0 })
      end
    end
  end

  # Define a test templated resource class
  let(:templated_resource_class) do
    Class.new(FastMcp::Resource) do
      uri 'test/counter/{id}'
      resource_name 'Test Counter with ID'
      description 'A test counter resource with ID parameter'
      mime_type 'application/json'

      def content
        JSON.generate({ count: 0, id: params[:id] })
      end
    end
  end

  before do
    # Register the test tool
    server.register_tool(greet_tool)

    # Register the test resources
    server.register_resource(counter_resource_class)
    server.register_resource(templated_resource_class)

    # Set the transport
    server.instance_variable_set(:@transport, transport)
  end

  around do |example|
    original_stdout = $stdout
    $stdout = StringIO.new
    example.run
    $stdout = original_stdout
  end

  describe 'request handling' do
    it 'responds to ping requests' do
      request = { jsonrpc: '2.0', method: 'ping', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']).to eq({})
      expect(io_as_json['id']).to eq(1)
    end

    it 'responds to initialize requests' do
      request = { jsonrpc: '2.0', method: 'initialize', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['serverInfo']['name']).to eq('test-server')
      expect(io_as_json['result']['serverInfo']['version']).to eq('1.0.0')
      expect(io_as_json['id']).to eq(1)
    end

    it 'responds nil to notifications/initialized requests' do
      request = { jsonrpc: '2.0', method: 'notifications/initialized' }
      io_response = server.handle_request(JSON.generate(request))

      expect(io_response).to be_nil
    end

    it 'lists tools' do
      request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['tools']).to be_an(Array)
      expect(io_as_json['result']['tools'].length).to eq(1)
      expect(io_as_json['result']['tools'][0]['name']).to eq('greet')
      expect(io_as_json['id']).to eq(1)
    end

    it 'calls tools' do
      request = { jsonrpc: '2.0', method: 'tools/call', params: { name: 'greet', arguments: { name: 'World' } }, id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['content'][0]['text']).to eq('Hello, World!')
      expect(io_as_json['id']).to eq(1)
    end

    it 'lists resources' do
      request = { jsonrpc: '2.0', method: 'resources/list', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['resources']).to be_an(Array)
      expect(io_as_json['result']['resources'].length).to eq(1)  # Only non-templated resources

      # Check for regular resource
      expect(io_as_json['result']['resources'].map { |r| r['uri'] }).to include('test/counter')
      expect(io_as_json['id']).to eq(1)
    end

    it 'lists resource templates' do
      request = { jsonrpc: '2.0', method: 'resources/templates/list', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['resourceTemplates']).to be_an(Array)
      expect(io_as_json['result']['resourceTemplates'].length).to eq(1)

      # Check for templated resource
      expect(io_as_json['result']['resourceTemplates'].first['uriTemplate']).to eq('test/counter/{id}')
      expect(io_as_json['id']).to eq(1)
    end

    it 'reads resources' do
      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter' }, id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['contents']).to be_an(Array)
      expect(io_as_json['result']['contents'].length).to eq(1)
      expect(io_as_json['result']['contents'][0]['uri']).to eq('test/counter')
      expect(io_as_json['result']['contents'][0]['mimeType']).to eq('application/json')
      expect(io_as_json['result']['contents'][0]['text']).to eq(JSON.generate({ count: 0 }))
      expect(io_as_json['id']).to eq(1)
    end

    it 'reads resources consistently' do
      # Read the resource to verify it returns expected content
      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter' }, id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['contents'][0]['text']).to eq(JSON.generate({ count: 0 }))
      expect(io_as_json['id']).to eq(1)
    end

    it 'handles errors for unknown methods' do
      request = { jsonrpc: '2.0', method: 'unknown', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['error']['code']).to eq(-32_601)
      expect(io_as_json['error']['message']).to eq('Method not found: unknown')
      expect(io_as_json['id']).to eq(1)
    end

    it 'handles errors for invalid JSON requests' do
      request = 1 # Invalid JSON
      io_response = server.handle_request(request)

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['error']['code']).to eq(-32_600)
      expect(io_as_json['error']['message']).to eq('Invalid Request')
      expect(io_as_json['id']).to eq(nil)
    end

    it 'handles errors for invalid JSON-RPC 2.0 requests' do
      request = { id: 1 } # Missing jsonrpc and method
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['error']['code']).to eq(-32_600)
      expect(io_as_json['error']['message']).to eq('Invalid Request')
      expect(io_as_json['id']).to eq(1)
    end
  end

  describe 'protocol version negotiation' do
    it 'responds to initialize with correct protocol version' do
      request = { jsonrpc: '2.0', method: 'initialize', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['protocolVersion']).to eq('2025-06-18')
      expect(io_as_json['id']).to eq(1)
    end

    it 'accepts requests without protocol version header' do
      request = { jsonrpc: '2.0', method: 'ping', id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']).to eq({})
      expect(io_as_json['id']).to eq(1)
    end

    it 'accepts requests with supported protocol version header' do
      request = { jsonrpc: '2.0', method: 'ping', id: 1 }
      headers = { 'mcp-protocol-version' => '2025-06-18' }
      io_response = server.handle_request(JSON.generate(request), headers: headers)

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']).to eq({})
      expect(io_as_json['id']).to eq(1)
    end

    context 'with RackTransport' do
      let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
      let(:rack_transport) { FastMcp::Transports::RackTransport.new(app, server, localhost_only: true) }

      before do
        server.transport = rack_transport
      end

      it 'validates protocol version in HTTP requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}'),
          'CONTENT_TYPE' => 'application/json',
          'HTTP_MCP_PROTOCOL_VERSION' => '2024-11-05',
          'REMOTE_ADDR' => '127.0.0.1'
        }

        result = rack_transport.call(env)

        expect(result[0]).to eq(400)
        expect(result[1]['Content-Type']).to eq('application/json')

        response = JSON.parse(result[2].first)
        expect(response['jsonrpc']).to eq('2.0')
        expect(response['error']['code']).to eq(-32_000)
        expect(response['error']['message']).to eq('Unsupported protocol version: 2024-11-05')
        expect(response['error']['data']['expected_version']).to eq('2025-06-18')
      end
    end
  end

  describe 'templated resources' do
    let(:debug_logger) { Logger.new($stderr) }

    it 'registers and lists templated resources' do
      # Debug output of available resources
      resources = server.instance_variable_get(:@resources)

      expect(resources.map(&:uri)).to include('test/counter')
      expect(resources.map(&:uri)).to include('test/counter/{id}')
    end

    it 'reads templated resources with parameters' do
      # Enable more detailed logging for this test
      logger = Logger.new($stderr)
      original_logger = server.logger
      server.logger = logger

      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter/123' }, id: 1 }

      # Print request JSON for debugging
      logger.debug("Request JSON: #{JSON.generate(request)}")

      # Print template resource pattern check
      pattern = templated_resource_class.addressable_template
      test_uri = 'test/counter/123'
      match_result = pattern.match(test_uri)
      logger.debug("Pattern: #{pattern.inspect}, URI: #{test_uri}, Match: #{match_result.inspect}")

      # Handle the request
      io_response = server.handle_request(JSON.generate(request))

      # Reset logger
      server.logger = original_logger

      # Continue with the test
      io_response.rewind
      io_as_json = JSON.parse(io_response.read)

      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json).to have_key('result')
      expect(io_as_json['result']).to have_key('contents')
      expect(io_as_json['result']['contents']).to be_an(Array)
      expect(io_as_json['result']['contents'].length).to eq(1)
      expect(io_as_json['result']['contents'][0]['uri']).to eq('test/counter/123')
      expect(io_as_json['result']['contents'][0]['mimeType']).to eq('application/json')

      content = JSON.parse(io_as_json['result']['contents'][0]['text'])
      expect(content['count']).to eq(0)
      expect(content['id']).to eq('123')
      expect(io_as_json['id']).to eq(1)
    end
  end
end
