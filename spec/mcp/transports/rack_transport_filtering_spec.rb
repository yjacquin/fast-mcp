# frozen_string_literal: true

require 'stringio'
require 'rack'

RSpec.describe 'FastMcp::Transports::RackTransport with filtering' do
  let(:server) { FastMcp::Server.new(name: 'test-server', version: '1.0.0', logger: Logger.new(nil)) }
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:transport) { FastMcp::Transports::RackTransport.new(app, server) }
  
  # Define test tools
  let(:admin_tool) do
    Class.new(FastMcp::Tool) do
      tool_name 'admin_tool'
      description 'Admin tool'
      tags :admin
      
      def call
        "Admin action"
      end
    end
  end
  
  let(:user_tool) do
    Class.new(FastMcp::Tool) do
      tool_name 'user_tool' 
      description 'User tool'
      tags :user
      
      def call
        "User action"
      end
    end
  end
  
  before do
    server.register_tools(admin_tool, user_tool)
    transport.start
  end
  
  describe 'per-request server filtering' do
    context 'when server has filters' do
      before do
        server.filter_tools do |request, tools|
          role = request.params['role']
          role == 'admin' ? tools : tools.reject { |t| t.tags.include?(:admin) }
        end
      end
      
      it 'creates a filtered server for requests' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'QUERY_STRING' => 'role=user',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        }
        
        # The transport should create a filtered server
        expect(server).to receive(:create_filtered_copy).and_call_original
        
        transport.call(env)
      end
    end
    
    context 'when using SERVER_ENV_KEY' do
      let(:custom_server) { FastMcp::Server.new(name: 'custom-server', version: '1.0.0', logger: Logger.new(nil)) }
      
      before do
        custom_server.register_tool(user_tool) # Only register user tool
      end
      
      it 'uses server from env when provided' do
        env = {
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'REMOTE_ADDR' => '127.0.0.1',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}'),
          FastMcp::Transports::RackTransport::SERVER_ENV_KEY => custom_server
        }
        
        # Should use the custom server, not create a filtered copy
        expect(server).not_to receive(:create_filtered_copy)
        
        transport.call(env)
      end
    end
  end
  
  describe 'integration with server filtering' do
    it 'filters tools correctly' do
      # Set up filtering
      server.filter_tools do |request, tools|
        role = request.params['role']
        role == 'admin' ? tools : tools.reject { |t| t.tags.include?(:admin) }
      end
      
      # Create a filtered copy manually to verify it works
      mock_request = double('request', params: { 'role' => 'user' })
      filtered_server = server.create_filtered_copy(mock_request)
      
      # Check the filtered server has the right tools
      expect(filtered_server.tools.keys).to eq(['user_tool'])
      expect(filtered_server.tools.keys).not_to include('admin_tool')
    end
    
    it 'runs the filters for every request' do
      calls = 0
      server.filter_tools do |_request, tools|
        calls += 1
        tools
      end

      3.times do
        transport.call(
          'PATH_INFO' => '/mcp/messages',
          'REQUEST_METHOD' => 'POST',
          'QUERY_STRING' => 'role=user',
          'REMOTE_ADDR' => '127.0.0.1',
          'CONTENT_TYPE' => 'application/json',
          'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
        )
      end

      expect(calls).to eq(3)
    end
  end

  # A filter can read anything on the request: here a header, like the
  # feature-flag example in docs/filtering.md.
  describe 'filters that read other parts of the request' do
    let(:stream) { StringIO.new }

    before do
      server.filter_tools do |request, tools|
        request.env['HTTP_X_USER_ID'] == 'alice' ? tools : tools.reject { |t| t.tags.include?(:admin) }
      end
      transport.instance_variable_set(:@sse_clients, { 'client' => { stream: stream, mutex: Mutex.new } })
    end

    def rpc(user, body)
      transport.call(
        'PATH_INFO' => '/mcp/messages',
        'REQUEST_METHOD' => 'POST',
        'REMOTE_ADDR' => '127.0.0.1',
        'CONTENT_TYPE' => 'application/json',
        'HTTP_X_USER_ID' => user,
        'rack.input' => StringIO.new(JSON.generate(body))
      )
      JSON.parse(stream.string.scan(/^data: (.*)$/).last.first)
    end

    it "lists only the tools the caller's own request allows" do
      rpc('alice', { jsonrpc: '2.0', id: 1, method: 'tools/list' })
      bob = rpc('bob', { jsonrpc: '2.0', id: 2, method: 'tools/list' })

      expect(bob['result']['tools'].map { |tool| tool['name'] }).to eq(['user_tool'])
    end

    it "does not run a tool that the caller's request filters out" do
      rpc('alice', { jsonrpc: '2.0', id: 1, method: 'tools/list' })
      bob = rpc('bob', { jsonrpc: '2.0', id: 2, method: 'tools/call', params: { name: 'admin_tool', arguments: {} } })

      expect(bob).to include('error' => include('message' => 'Tool not found: admin_tool'))
    end
  end
end
