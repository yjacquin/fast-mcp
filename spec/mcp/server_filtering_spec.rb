# frozen_string_literal: true

RSpec.describe 'FastMcp::Server filtering' do
  let(:server) { FastMcp::Server.new(name: 'test-server', version: '1.0.0', logger: Logger.new(nil)) }
  
  # Define test tools with tags
  let(:admin_tool) do
    Class.new(FastMcp::Tool) do
      tool_name 'admin_tool'
      description 'Admin only tool'
      tags :admin, :dangerous
      
      def call
        "Admin action executed"
      end
    end
  end
  
  let(:user_tool) do
    Class.new(FastMcp::Tool) do
      tool_name 'user_tool'
      description 'User tool'
      tags :user, :safe
      
      def call
        "User action executed"
      end
    end
  end
  
  let(:public_tool) do
    Class.new(FastMcp::Tool) do
      tool_name 'public_tool'
      description 'Public tool'
      tags :public
      
      def call
        "Public action executed"
      end
    end
  end
  
  # Define test resources with tags
  let(:admin_resource) do
    Class.new(FastMcp::Resource) do
      uri 'admin/config'
      resource_name 'Admin Config'
      description 'Admin configuration'
      mime_type 'application/json'
      
      def self.tags
        [:admin, :sensitive]
      end
      
      def content
        '{"admin": true}'
      end
    end
  end
  
  let(:user_resource) do
    Class.new(FastMcp::Resource) do
      uri 'user/profile'
      resource_name 'User Profile'
      description 'User profile data'
      mime_type 'application/json'
      
      def self.tags
        [:user]
      end
      
      def content
        '{"user": "data"}'
      end
    end
  end
  
  before do
    # Register all tools and resources
    server.register_tools(admin_tool, user_tool, public_tool)
    server.register_resources(admin_resource, user_resource)
  end
  
  describe '#filter_tools' do
    it 'adds tool filters to the server' do
      expect(server.instance_variable_get(:@tool_filters)).to be_empty
      
      server.filter_tools { |_request, tools| tools }
      
      expect(server.instance_variable_get(:@tool_filters).size).to eq(1)
    end
    
    it 'allows multiple filters' do
      server.filter_tools { |_request, tools| tools }
      server.filter_tools { |_request, tools| tools }
      
      expect(server.instance_variable_get(:@tool_filters).size).to eq(2)
    end
  end
  
  describe '#filter_resources' do
    it 'adds resource filters to the server' do
      expect(server.instance_variable_get(:@resource_filters)).to be_empty
      
      server.filter_resources { |_request, resources| resources }
      
      expect(server.instance_variable_get(:@resource_filters).size).to eq(1)
    end
  end
  
  describe '#contains_filters?' do
    it 'returns false when no filters are configured' do
      expect(server.contains_filters?).to be false
    end
    
    it 'returns true when tool filters are configured' do
      server.filter_tools { |_request, tools| tools }
      expect(server.contains_filters?).to be true
    end
    
    it 'returns true when resource filters are configured' do
      server.filter_resources { |_request, resources| resources }
      expect(server.contains_filters?).to be true
    end
  end
  
  describe '#create_filtered_copy' do
    let(:request) { double('request', params: { 'role' => 'user' }) }
    
    context 'with tool filtering' do
      before do
        server.filter_tools do |req, tools|
          role = req.params['role']
          case role
          when 'admin'
            tools
          when 'user'
            tools.reject { |t| t.tags.include?(:admin) }
          else
            tools.select { |t| t.tags.include?(:public) }
          end
        end
      end
      
      it 'creates a new server instance with filtered tools for user role' do
        filtered_server = server.create_filtered_copy(request)
        
        expect(filtered_server).not_to eq(server)
        expect(filtered_server.name).to eq(server.name)
        expect(filtered_server.version).to eq(server.version)
        
        # Check filtered tools
        expect(filtered_server.tools.keys).to contain_exactly('user_tool', 'public_tool')
        expect(filtered_server.tools.keys).not_to include('admin_tool')
      end
      
      it 'creates a server with all tools for admin role' do
        admin_request = double('request', params: { 'role' => 'admin' })
        filtered_server = server.create_filtered_copy(admin_request)
        
        expect(filtered_server.tools.keys).to contain_exactly('admin_tool', 'user_tool', 'public_tool')
      end
      
      it 'creates a server with only public tools for unknown role' do
        public_request = double('request', params: { 'role' => 'guest' })
        filtered_server = server.create_filtered_copy(public_request)
        
        expect(filtered_server.tools.keys).to contain_exactly('public_tool')
      end
    end
    
    context 'with resource filtering' do
      before do
        # Add tags method to resource classes if not already defined
        admin_resource.define_singleton_method(:tags) { [:admin, :sensitive] } unless admin_resource.respond_to?(:tags)
        user_resource.define_singleton_method(:tags) { [:user] } unless user_resource.respond_to?(:tags)
        
        server.filter_resources do |req, resources|
          role = req.params['role']
          case role
          when 'admin'
            resources
          when 'user'
            resources.reject { |r| r.respond_to?(:tags) && r.tags.include?(:admin) }
          else
            []
          end
        end
      end
      
      it 'filters resources based on role' do
        filtered_server = server.create_filtered_copy(request)
        
        resource_uris = filtered_server.resources.map(&:uri)
        expect(resource_uris).to contain_exactly('user/profile')
        expect(resource_uris).not_to include('admin/config')
      end
    end
    
    context 'with multiple filters' do
      before do
        # First filter: Remove dangerous tools
        server.filter_tools do |_req, tools|
          tools.reject { |t| t.tags.include?(:dangerous) }
        end
        
        # Second filter: Role-based filtering
        server.filter_tools do |req, tools|
          role = req.params['role']
          if role == 'user'
            tools.reject { |t| t.tags.include?(:admin) }
          else
            tools
          end
        end
      end
      
      it 'applies filters in sequence' do
        filtered_server = server.create_filtered_copy(request)
        
        # admin_tool should be removed by both filters (dangerous + admin)
        # user_tool and public_tool should remain
        expect(filtered_server.tools.keys).to contain_exactly('user_tool', 'public_tool')
      end
    end
    
    context 'with metadata-based filtering' do
      let(:categorized_tool) do
        Class.new(FastMcp::Tool) do
          tool_name 'categorized_tool'
          description 'Tool with metadata'
          metadata :category, 'reporting'
          metadata :risk_level, 'low'
          
          def call
            "Categorized action"
          end
        end
      end
      
      before do
        server.register_tool(categorized_tool)
        
        server.filter_tools do |req, tools|
          category = req.params['category']
          if category
            tools.select { |t| t.metadata(:category) == category }
          else
            tools
          end
        end
      end
      
      it 'filters tools based on metadata' do
        category_request = double('request', params: { 'category' => 'reporting' })
        filtered_server = server.create_filtered_copy(category_request)
        
        expect(filtered_server.tools.keys).to contain_exactly('categorized_tool')
      end
    end
  end
  
  describe 'Thread safety' do
    it 'creates independent server instances for concurrent requests' do
      server.filter_tools do |req, tools|
        role = req.params['role']
        role == 'admin' ? tools : tools.reject { |t| t.tags.include?(:admin) }
      end
      
      admin_request = double('request', params: { 'role' => 'admin' })
      user_request = double('request', params: { 'role' => 'user' })
      
      admin_server = server.create_filtered_copy(admin_request)
      user_server = server.create_filtered_copy(user_request)
      
      # Servers should be different instances
      expect(admin_server).not_to equal(user_server)
      expect(admin_server).not_to equal(server)
      
      # Each should have different tools
      expect(admin_server.tools.keys).to include('admin_tool')
      expect(user_server.tools.keys).not_to include('admin_tool')
      
      # Original server should be unchanged
      expect(server.tools.keys).to include('admin_tool', 'user_tool', 'public_tool')
    end
  end
end 