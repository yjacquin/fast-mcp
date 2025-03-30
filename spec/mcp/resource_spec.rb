# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FastMcp::Resource do
  let(:server) { FastMcp::Server.new(name: 'test-server', version: '1.0.0') }

  describe 'class methods' do
    it 'allows setting and getting uri' do
      resource_class = Class.new(FastMcp::Resource)
      resource_class.uri('test/resource')
      expect(resource_class.uri).to eq('test/resource')
    end

    it 'allows setting and getting resource_name' do
      resource_class = Class.new(FastMcp::Resource)
      resource_class.resource_name('Test Resource')
      expect(resource_class.resource_name).to eq('Test Resource')
    end

    it 'allows setting and getting description' do
      resource_class = Class.new(FastMcp::Resource)
      resource_class.description('A test resource')
      expect(resource_class.description).to eq('A test resource')
    end

    it 'allows setting and getting mime_type' do
      resource_class = Class.new(FastMcp::Resource)
      resource_class.mime_type('text/plain')
      expect(resource_class.mime_type).to eq('text/plain')
    end

    it 'inherits attributes from parent class' do
      parent_class = Class.new(FastMcp::Resource) do
        description "A base resource class"
        mime_type "text/plain"
      end

      child_class = Class.new(parent_class) do
        uri "test/child"
        resource_name "Child Resource"
      end

      expect(child_class.description).to eq("A base resource class")
      expect(child_class.mime_type).to eq("text/plain")
      expect(child_class.uri).to eq("test/child")
      expect(child_class.resource_name).to eq("Child Resource")
    end
  end

  describe 'instance methods' do
    it 'requires implementing content method in subclasses' do
      resource_class = Class.new(FastMcp::Resource)
      expect { resource_class.instance.content }.to raise_error(NotImplementedError)
    end

    it 'determines if content is binary based on mime_type' do
      text_resource = Class.new(FastMcp::Resource) do
        mime_type 'text/plain'
        def content; 'text'; end
      end

      binary_resource = Class.new(FastMcp::Resource) do
        mime_type 'image/png'
        def content; 'binary data'; end
      end

      expect(text_resource.instance.binary?).to be false
      expect(binary_resource.instance.binary?).to be true
    end

    it 'provides metadata as a hash' do
      resource = Class.new(FastMcp::Resource) do
        uri 'test/resource'
        resource_name 'Test Resource'
        description 'A test resource'
        mime_type 'text/plain'
        def content; 'test content'; end
      end

      metadata = resource.metadata

      expect(metadata).to be_a(Hash)
      expect(metadata[:uri]).to eq('test/resource')
      expect(metadata[:name]).to eq('Test Resource')
      expect(metadata[:description]).to eq('A test resource')
      expect(metadata[:mimeType]).to eq('text/plain')
    end

    it 'provides contents with text for non-binary resources' do
      resource = Class.new(FastMcp::Resource) do
        uri 'test/resource'
        mime_type 'text/plain'
        def content; 'test content'; end
      end

      contents = resource.instance.contents
      expect(contents[:text]).to eq('test content')
      expect(contents[:blob]).to be_nil
    end

    it 'provides contents with blob for binary resources' do
      resource = Class.new(FastMcp::Resource) do
        uri 'test/resource'
        mime_type 'image/png'
        def content; 'binary data'; end
      end

      contents = resource.instance.contents
      expect(contents[:text]).to be_nil
      expect(contents[:blob]).to eq(Base64.strict_encode64('binary data'))
    end
  end

  describe 'integration with server' do
    let(:counter_resource_class) do
      Class.new(FastMcp::Resource) do
        uri 'file://counter.txt'
        resource_name 'Counter'
        description 'A simple counter resource'
        mime_type 'text/plain'

        def content
          '0'
        end
      end
    end

    let(:users_resource_class) do
      Class.new(FastMcp::Resource) do
        uri 'file://users.json'
        resource_name 'Users'
        description 'List of users'
        mime_type 'application/json'

        def content
          JSON.generate([
            { id: 1, name: 'Alice', email: 'alice@example.com' },
            { id: 2, name: 'Bob', email: 'bob@example.com' }
          ])
        end
      end
    end

    it 'registers a resource instance' do
      expect(server.resources).not_to have_key('file://counter.txt')
      server.register_resource(counter_resource_class)
      expect(server.resources).to have_key('file://counter.txt')
      
      resource = server.resources['file://counter.txt']
      expect(resource.ancestors).to include(FastMcp::Resource)
      expect(resource.uri).to eq('file://counter.txt')
      expect(resource.resource_name).to eq('Counter')
      expect(resource.description).to eq('A simple counter resource')
      expect(resource.mime_type).to eq('text/plain')
      expect(resource.instance.content).to eq('0')
    end

    it 'registers multiple resources' do
      expect(server.resources).to be_empty
      server.register_resources(counter_resource_class, users_resource_class)
      
      expect(server.resources.keys).to contain_exactly('file://counter.txt', 'file://users.json')
    end

    it 'allows reading registered resources through the server' do
      server.register_resource(users_resource_class)
      resource = server.read_resource('file://users.json')
      expect(resource.ancestors).to include(FastMcp::Resource)
      expect(resource.uri).to eq('file://users.json')
      expect(resource.resource_name).to eq('Users')
      expect(JSON.parse(resource.instance.content).size).to eq(2)
    end
  end

  describe 'resource with dynamic content' do
    let(:weather_resource_class) do
      Class.new(FastMcp::Resource) do
        uri 'weather'
        resource_name 'Weather'
        description 'Current weather conditions'
        mime_type 'application/json'

        def content
          JSON.generate({
            temperature: rand(0..35),
            condition: ['Sunny', 'Cloudy', 'Rainy', 'Snowy'].sample,
            updated_at: Time.now.to_s
          })
        end
      end
    end

    it 'creates a resource with dynamic content' do
      server.register_resource(weather_resource_class)
      resource = server.read_resource('weather')
      
      weather_data = JSON.parse(resource.instance.content)
      expect(weather_data).to have_key('temperature')
      expect(weather_data).to have_key('condition')
      expect(weather_data).to have_key('updated_at')
    end
  end

  describe 'resource update_content method' do
    let(:counter_resource_class) do
      Class.new(FastMcp::Resource) do
        uri 'counter'
        resource_name 'Counter'
        description 'A counter resource'
        mime_type 'text/plain'

        def initialize
          @content = '0'
        end
        
        attr_accessor :content
      end
    end

    it 'allows updating resource content' do
      resource = counter_resource_class
      server.register_resource(resource)
      
      expect(resource.instance.content).to eq('0')
      resource.instance.content = '5'
      expect(resource.instance.content).to eq('5')
      
      # Verify through server
      updated_resource = server.read_resource('counter')
      expect(updated_resource.instance.content).to eq('5')
    end
  end

  describe 'creating resources from files' do
    it 'creates a resource from a file' do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('file content')
      allow(File).to receive(:basename).and_return('test.txt')
      
      resource = FastMcp::Resource.from_file('test.txt')
      
      expect(resource.ancestors).to include(FastMcp::Resource)
      expect(resource.uri).to match(/test\.txt$/)
      expect(resource.resource_name).to eq('test.txt')
      expect(resource.mime_type).to eq('text/plain')
      expect(resource.instance.content).to eq('file content')
    end

    it 'detects mime type from file extension' do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('file content')
      allow(File).to receive(:basename).and_return('test.json')
      
      resource = FastMcp::Resource.from_file('test.json')
      
      expect(resource.mime_type).to eq('application/json')
    end

    it 'uses provided name and description' do
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('file content')
      allow(File).to receive(:basename).and_return('test.txt')
      
      resource = FastMcp::Resource.from_file('test.txt', name: 'Custom Name', description: 'Custom description')
      
      expect(resource.resource_name).to eq('Custom Name')
      expect(resource.description).to eq('Custom description')
    end
  end
end 