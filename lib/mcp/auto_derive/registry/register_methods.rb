# frozen_string_literal: true

require_relative '../adapters/model_method_adapter'
require_relative '../adapters/active_record_method_adapter'
require_relative '../adapters/controller_method_adapter'
require_relative '../controller_auto_derive'
require_relative '../auto_derive'
require_relative '../auto_derive_configuration'

module FastMcp
  module AutoDerive
    class AutoDeriveRegistry
      class << self
        private

        def register_model_method(model, tool_name, metadata)
          method_name = metadata[:method_name]

          tool_class = FastMcp::AutoDerive::Adapters::ModelMethodAdapter.for_method(model, method_name, metadata)

          class_name = tool_name.camelize
          FastMcp::AutoDerive::Tools.const_set(class_name, tool_class)

          full_class_name = "MCP#{class_name}"
          Object.const_set(full_class_name, tool_class) unless Object.const_defined?(full_class_name)

          cursor_style_name = "Tools#{class_name}"
          Object.const_set(cursor_style_name, tool_class) unless Object.const_defined?(cursor_style_name)

          tool_class
        end

        def register_controller_action(controller, tool_name, metadata)
          tool_class = FastMcp::AutoDerive::Adapters::ControllerMethodAdapter.for_action(controller, metadata)

          class_name = tool_name.camelize
          FastMcp::AutoDerive::Tools.const_set(class_name, tool_class)

          full_class_name = "MCP#{class_name}"
          Object.const_set(full_class_name, tool_class) unless Object.const_defined?(full_class_name)

          cursor_style_name = "Tools#{class_name}"
          Object.const_set(cursor_style_name, tool_class) unless Object.const_defined?(cursor_style_name)

          tool_class
        end

        def register_activerecord_methods(model)
          config = FastMcp::AutoDerive.configuration
          all_methods = all_active_record_methods(model)
          ar_methods = if config.auto_derive_active_record_methods.present?
                         all_methods.select do |method|
                           config.auto_derive_active_record_methods.include?(method[:method_name])
                         end
                       else
                         all_methods
                       end

          tools = []

          ar_methods.each do |method|
            tools << register_ar_method(model, method)
          rescue StandardError => e
            puts "  Error registering AR method #{method[:name]} for model #{model.name}: #{e.message}"
          end

          tools
        end

        def register_ar_method(model, method)
          tool_class = FastMcp::AutoDerive::Adapters::ActiveRecordMethodAdapter.for_method(model, method)

          class_name = method[:name].camelize
          FastMcp::AutoDerive::Tools.const_set(class_name, tool_class)

          full_class_name = "MCP#{class_name}"
          Object.const_set(full_class_name, tool_class) unless Object.const_defined?(full_class_name)

          cursor_style_name = "Tools#{class_name}"
          Object.const_set(cursor_style_name, tool_class) unless Object.const_defined?(cursor_style_name)

          tool_class
        end

        def all_active_record_methods(model)
          model_name = model.name
          base_name = model_name.demodulize.underscore
          [
            {
              name: "#{base_name}_find",
              method_name: :find,
              description: "Find a #{model_name} by ID",
              class_method: true,
              finder_key: :id,
              class_name: model_name
            },
            {
              name: "#{base_name}_sample",
              method_name: :limit,
              description: "Get sample #{model_name} records for examples",
              class_method: true,
              parameters: {
                limit: { type: :integer, description: 'Number of records to return (default: 5)', required: false,
                         default: 5 }
              },
              class_name: model_name,
              post_process: ->(result, _) { result.to_a }
            },
            {
              name: "#{base_name}_where",
              method_name: :where,
              description: "Find #{model_name} records matching conditions",
              class_method: true,
              parameters: {
                conditions: { type: :string, description: 'JSON string of conditions' }
              },
              class_name: model_name
            },
            {
              name: "#{base_name}_create",
              method_name: :create!,
              description: "Create a new #{model_name}",
              class_method: true,
              parameters: {
                attributes: { type: :string, description: 'JSON string of attributes' }
              },
              class_name: model_name
            },
            {
              name: "#{base_name}_update",
              method_name: :update,
              description: "Update a #{model_name}",
              class_method: false,
              finder_key: :id,
              parameters: {
                attributes: { type: :string, description: 'JSON string of attributes to update' }
              },
              class_name: model_name
            },
            {
              name: "#{base_name}_destroy",
              method_name: :destroy,
              description: "Delete a #{model_name}",
              class_method: false,
              finder_key: :id,
              class_name: model_name
            }
          ]
        end
      end
    end
  end
end
