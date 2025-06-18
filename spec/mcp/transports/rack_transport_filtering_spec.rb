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
    
    it 'caches filtered servers' do
      server.filter_tools { |_request, tools| tools }
      
      # Get the cache
      cache = transport.instance_variable_get(:@filtered_servers_cache)
      expect(cache).to be_empty
      
      # After a request, it should have cached a server
      env = {
        'PATH_INFO' => '/mcp/messages',
        'REQUEST_METHOD' => 'POST',
        'QUERY_STRING' => 'role=user',
        'REMOTE_ADDR' => '127.0.0.1',
        'rack.input' => StringIO.new('{"jsonrpc":"2.0","method":"ping","id":1}')
      }
      
      transport.call(env)
      
      # Cache should have one entry
      expect(cache.size).to eq(1)
    end
  end
end 