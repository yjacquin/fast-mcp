# frozen_string_literal: true

require 'stringio'

RSpec.describe 'MCP Server Integration' do
  let(:server) { MCP::Server.new(name: 'test-server', version: '1.0.0', logger: MCP::MockLogger.new) }
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


      def default_content
        @count = 0

        JSON.generate({ count: @count })
      end

      def update_content(new_content)
        data = JSON.parse(new_content)
        @count = data['count']
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
    io = StringIO.new
    $stdout = io
    example.run
    $stdout = original_stdout
  end
  
  # Helper method to get responses that are sent to stdout
  def get_response_from_stdout(request)
    io = StringIO.new
    original_stdout = $stdout
    $stdout = io
    
    # Send the request
    server.handle_request(request.is_a?(String) ? request : JSON.generate(request))
    
    # Capture and restore stdout
    $stdout = original_stdout
    
    # Get the response if any (for notifications it will be empty)
    io.string.strip.empty? ? nil : io.string.strip
  end

  describe 'request handling' do
    it 'responds to ping requests' do
      request = { jsonrpc: '2.0', method: 'ping', id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']).to eq({})
      expect(response_json['id']).to eq(1)
    end

    it 'responds to initialize requests' do
      request = { jsonrpc: '2.0', method: 'initialize', id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['serverInfo']['name']).to eq('test-server')
      expect(response_json['result']['serverInfo']['version']).to eq('1.0.0')
      expect(response_json['id']).to eq(1)
    end

    it 'lists tools' do
      request = { jsonrpc: '2.0', method: 'tools/list', id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['tools']).to be_an(Array)
      expect(response_json['result']['tools'].length).to eq(1)
      expect(response_json['result']['tools'][0]['name']).to eq('greet')
      expect(response_json['id']).to eq(1)
    end

    it 'calls tools' do
      request = { jsonrpc: '2.0', method: 'tools/call', params: { name: 'greet', arguments: { name: 'World' } }, id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['content'][0]['text']).to eq('Hello, World!')
      expect(response_json['id']).to eq(1)
    end

    it 'lists resources' do
      request = { jsonrpc: '2.0', method: 'resources/list', id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['resources']).to be_an(Array)
      expect(response_json['result']['resources'].length).to eq(1)
      expect(response_json['result']['resources'][0]['uri']).to eq('test/counter')
      expect(response_json['id']).to eq(1)
    end

    it 'reads resources' do
      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter' }, id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['contents']).to be_an(Array)
      expect(response_json['result']['contents'].length).to eq(1)
      expect(response_json['result']['contents'][0]['uri']).to eq('test/counter')
      expect(response_json['result']['contents'][0]['mimeType']).to eq('application/json')
      expect(response_json['result']['contents'][0]['text']).to eq(JSON.generate({ count: 0 }))
      expect(response_json['id']).to eq(1)
    end

    it 'updates resources' do
      # First update the resource
      new_content = JSON.generate({ count: 1 })
      server.update_resource('test/counter', new_content)

      # Then read it to verify the update
      request = { jsonrpc: '2.0', method: 'resources/read', params: { uri: 'test/counter' }, id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['result']['contents'][0]['text']).to eq(new_content)
      expect(response_json['id']).to eq(1)
    end

    it 'handles errors for unknown methods' do
      request = { jsonrpc: '2.0', method: 'unknown', id: 1 }
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['error']['code']).to eq(-32_601)
      expect(response_json['error']['message']).to eq('Method not found: unknown')
      expect(response_json['id']).to eq(1)
    end

    it 'handles errors for invalid JSON requests' do
      request = 1 # Invalid JSON
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['error']['code']).to eq(-32_600)
      # The error message may change based on implementation, so we just check that it exists
      expect(response_json['error']['message']).to be_a(String)
      expect(response_json['id']).to eq(nil)
    end

    it 'handles errors for invalid JSON-RPC 2.0 requests' do
      request = { id: 1 } # Missing jsonrpc and method
      response = get_response_from_stdout(request)

      # Parse the JSON response from stdout
      response_json = JSON.parse(response)
      expect(response_json['jsonrpc']).to eq('2.0')
      expect(response_json['error']['code']).to eq(-32_600)
      expect(response_json['error']['message']).to eq('Invalid Request')
      expect(response_json['id']).to eq(1)
    end
    
    it 'handles notification messages without responses' do
      # Save the current state to check it after
      initial_state = server.instance_variable_get(:@client_initialized)
      
      request = { jsonrpc: '2.0', method: 'notifications/initialized' }
      response = get_response_from_stdout(request)
      
      # For notifications, we expect no response (empty stdout)
      expect(response).to be_nil
      
      # But we expect the client to be initialized
      expect(server.instance_variable_get(:@client_initialized)).to be true
      expect(server.instance_variable_get(:@client_initialized)).not_to eq(initial_state)
    end
  end
end
