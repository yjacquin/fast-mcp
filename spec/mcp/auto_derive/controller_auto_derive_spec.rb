# frozen_string_literal: true

require 'spec_helper'
require 'mcp/auto_derive/controller_auto_derive'

module TestControllerMethods
  def expose_action_to_mcp(action_name, description:, parameters: {}, read_only: true, tool_name: nil,
                          title: nil, destructive: nil, idempotent: false, open_world: true)
    tool_name ||= "#{name}_#{action_name}"

    self.mcp_exposed_actions = mcp_exposed_actions.merge(
      tool_name => {
        action_name: action_name,
        description: description,
        parameters: parameters,
        read_only: read_only,
        class_name: name,
        title: title,
        destructive: destructive,
        idempotent: idempotent,
        open_world: open_world
      }
    )
  end
end

RSpec.describe FastMcp::AutoDerive::ControllerAutoDeriveModule do
  let(:controller_class) do
    Class.new do
      class << self
        attr_accessor :mcp_exposed_actions

        def name
          'TestController'
        end

        def underscore
          'test_controller'
        end
      end

      self.mcp_exposed_actions = {}

      extend TestControllerMethods
    end
  end

  describe '.expose_action_to_mcp' do
    it 'registers the action in mcp_exposed_actions' do
      controller_class.expose_action_to_mcp(
        :test_action,
        description: 'Test action description',
        parameters: { param1: { type: :string, description: 'Test parameter' } },
        read_only: true
      )

      expect(controller_class.mcp_exposed_actions.keys).to include('TestController_test_action')
    end

    it 'sets action details correctly' do
      controller_class.expose_action_to_mcp(
        :test_action,
        description: 'Test action description',
        parameters: { param1: { type: :string, description: 'Test parameter' } },
        read_only: true
      )

      action_info = controller_class.mcp_exposed_actions['TestController_test_action']
      expect(action_info[:action_name]).to eq(:test_action)
      expect(action_info[:description]).to eq('Test action description')
      expect(action_info[:parameters]).to include(param1: { type: :string, description: 'Test parameter' })
      expect(action_info[:read_only]).to be(true)
    end

    it 'allows custom tool name to be set' do
      controller_class.expose_action_to_mcp(
        :custom_action,
        description: 'Custom action description',
        tool_name: 'custom_tool_name'
      )

      expect(controller_class.mcp_exposed_actions.keys).to include('custom_tool_name')
    end

    it 'correctly sets additional tool properties' do
      controller_class.expose_action_to_mcp(
        :test_action,
        description: 'Test action description',
        read_only: false,
        title: 'Test Action',
        destructive: true,
        idempotent: true,
        open_world: false
      )

      action_info = controller_class.mcp_exposed_actions['TestController_test_action']
      expect(action_info[:title]).to eq('Test Action')
      expect(action_info[:read_only]).to be(false)
      expect(action_info[:destructive]).to be(true)
      expect(action_info[:idempotent]).to be(true)
      expect(action_info[:open_world]).to be(false)
    end

    it 'derives default tool name from controller name and action' do
      test_controller = Class.new do
        class << self
          attr_accessor :mcp_exposed_actions

          def name
            'TestController'
          end

          def underscore
            'test_controller'
          end
        end

        self.mcp_exposed_actions = {}
      end

      test_controller.extend(TestControllerMethods)

      test_controller.expose_action_to_mcp(
        :show,
        description: 'Show resource'
      )

      expect(test_controller.mcp_exposed_actions.keys).to include('TestController_show')
    end
  end
end
