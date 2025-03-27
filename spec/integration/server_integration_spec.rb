# frozen_string_literal: true

require 'stringio'

RSpec.describe 'MCP Server Integration' do
  let(:server) { MCP::Server.new(name: 'test-server', version: '1.0.0', logger: Logger.new(nil)) }
  let(:transport) { MCP::Transports::StdioTransport.new(server) }

  # Define a test tool class
  let(:greet_tool) do
    Class.new(MCP::Tool) do
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
    Class.new(MCP::Resource) do
      uri 'test/counter'
      resource_name 'Test Counter'
      description 'A test counter resource'
      mime_type 'application/json'

      def initialize
        @count = 0
      end

      def content
        JSON.generate({ count: @count })
      end

      def update_count(new_count)
        @count = new_count
      end
    end
  end

  before do
    # Register the test tool
    server.register_tool(greet_tool)

    # Register the test resource
    server.register_resource(counter_resource_class)

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
      expect(io_as_json['result']['resources'].length).to eq(1)
      expect(io_as_json['result']['resources'][0]['uri']).to eq('test/counter')
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

    it 'notifies subscribers about resource updates' do
      # First update the resource
      new_count = 1
      counter_resource_class.instance.update_count(new_count)

      # Then read it to verify the update
      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter' }, id: 1 }
      io_response = server.handle_request(JSON.generate(request))

      io_response.rewind
      io_as_json = JSON.parse(io_response.read)
      expect(io_as_json['jsonrpc']).to eq('2.0')
      expect(io_as_json['result']['contents'][0]['text']).to eq(JSON.generate({ count: new_count }))
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
end
