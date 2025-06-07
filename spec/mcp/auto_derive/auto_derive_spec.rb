# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/auto_derive'
require 'mcp/auto_derive/auto_derive_configuration'
require 'support/shared/test_auto_derive_methods'

RSpec.describe FastMcp::AutoDerive do
  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(FastMcp::AutoDerive::Configuration)
    end

    it 'memoizes the configuration' do
      config = described_class.configuration
      expect(described_class.configuration).to be(config)
    end
  end

  describe '.configure' do
    it 'yields the configuration' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end

    it 'allows configuration to be modified' do
      described_class.configure do |config|
        config.enabled_in_web = false
      end
      expect(described_class.configuration.enabled_in_web).to be(false)
    end
  end

  describe '.expose_to_mcp' do
    let(:test_class) do
      Class.new do
        extend TestAutoDeriveMethods
        self.mcp_exposed_methods = {}

        def test_method
          'test result'
        end

        expose_to_mcp :test_method,
                     description: 'Test method',
                     parameters: { param1: { type: :string, description: 'Test parameter' } },
                     read_only: true
      end
    end

    it 'registers the method with correct attributes' do
      method_info = test_class.mcp_exposed_methods['TestClass_test_method']
      expect(method_info).to include(
        method_name: :test_method,
        description: 'Test method',
        parameters: { param1: { type: :string, description: 'Test parameter' } },
        read_only: true
      )
    end

    it 'allows custom tool name to be set' do
      custom_class = Class.new do
        extend TestAutoDeriveMethods
        self.mcp_exposed_methods = {}

        def custom_method
          'custom result'
        end

        expose_to_mcp :custom_method,
                     description: 'Custom method',
                     tool_name: 'custom_tool_name'
      end

      expect(custom_class.mcp_exposed_methods.keys).to include('custom_tool_name')
    end
  end
end
