# frozen_string_literal: true

require 'active_support/core_ext/string'

# require_relative '../adapters/model_method_adapter'
# require_relative '../adapters/active_record_method_adapter'
# require_relative '../adapters/controller_method_adapter'
# require_relative '../controller_auto_derive'
# require_relative '../auto_derive'
# require_relative '../auto_derive_configuration'

module FastMcp
  module AutoDerive
    class Deriver
      class << self
        private

        def derive_model_method(model, tool_name, metadata)
          method_name = metadata[:method_name]

          tool_class = FastMcp::AutoDerive::Adapters::ModelMethodAdapter.derive_model_method(model, method_name,
                                                                                             metadata)

          # Ensure the tool_name is sanitized for use as a constant
          class_name = sanitize_for_constant(tool_name.camelize)
          FastMcp::AutoDerive::Tools.const_set(class_name, tool_class)

          full_class_name = "MCP#{class_name}"
          Object.const_set(full_class_name, tool_class) unless Object.const_defined?(full_class_name)

          cursor_style_name = "Tools#{class_name}"
          Object.const_set(cursor_style_name, tool_class) unless Object.const_defined?(cursor_style_name)

          tool_class
        end

        def derive_controller_action(controller, tool_name, metadata)
          tool_class = FastMcp::AutoDerive::Adapters::ControllerMethodAdapter.derive_controller_action(controller,
                                                                                                       metadata)

          # Ensure the tool_name is sanitized for use as a constant
          class_name = sanitize_for_constant(tool_name.camelize)
          FastMcp::AutoDerive::Tools.const_set(class_name, tool_class)

          full_class_name = "MCP#{class_name}"
          Object.const_set(full_class_name, tool_class) unless Object.const_defined?(full_class_name)

          cursor_style_name = "Tools#{class_name}"
          Object.const_set(cursor_style_name, tool_class) unless Object.const_defined?(cursor_style_name)

          tool_class
        end

        # Helper method to ensure strings are safe to use as constants
        def sanitize_for_constant(name)
          # Remove any characters that wouldn't be valid in a constant name
          name.to_s.gsub(/[^a-zA-Z0-9_]/, '')
        end
      end
    end
  end
end
