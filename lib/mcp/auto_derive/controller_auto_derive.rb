# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module ControllerAutoDeriveModule
      extend ActiveSupport::Concern

      included do
        class_attribute :mcp_exposed_actions, default: {}
      end

      class_methods do
        # Expose a controller action to the Model Context Protocol
        #
        # @param action_name [Symbol] The name of the action to expose
        # @param description [String] Description of what the action does
        # @param parameters [Hash] Description of parameters (optional)
        # @param read_only [Boolean] Whether this action modifies data (default: true)
        # @param tool_name [String] Custom name for the tool (optional)
        def expose_action_to_mcp(action_name, description:, parameters: {}, read_only: true, tool_name: nil)
          # Generate a tool name if not provided
          tool_name ||= "#{name.underscore.gsub('_controller', '')}_#{action_name}"

          # Store the action metadata
          self.mcp_exposed_actions = mcp_exposed_actions.merge(
            tool_name => {
              action_name: action_name,
              description: description,
              parameters: parameters,
              read_only: read_only,
              class_name: name
            }
          )
        end
      end
    end
  end
end
