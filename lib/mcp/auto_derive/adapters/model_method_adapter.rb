# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      class ModelMethodAdapter < AutoDeriveAdapter
        def self.for_method(model, method_name, metadata)
          puts "  Creating ModelMethodAdapter for model: #{model.name}, method: #{method_name}"

          param_definitions = {}

          if metadata[:parameters].present?
            metadata[:parameters].each do |param_name, param_details|
              param_details = param_details.is_a?(Hash) ? param_details.dup : { description: param_details.to_s }

              param_details[:type] ||= :string
              param_details[:description] ||= "#{param_name} parameter"
              param_details[:required] = !(param_details[:optional] == true)

              param_definitions[param_name.to_sym] = param_details
            end
          end

          finder_key = metadata[:finder_key]
          if finder_key
            param_definitions[finder_key.to_sym] ||= {
              type: :string,
              description: "The #{finder_key} to find the #{model.name} record",
              required: true
            }
          end

          create_subclass(
            name: metadata[:tool_name] || "#{model.name.underscore}_#{method_name}",
            class_name: model.name,
            method_name: method_name,
            description: metadata[:description],
            parameters: param_definitions,
            read_only: metadata[:read_only] || true,
            finder_key: finder_key
          ).tap do |klass|
            klass.define_singleton_method(:model_class) { model }
            klass.define_singleton_method(:metadata) { metadata }

            klass.define_method(:call) do |params|
              model_class = self.class.model_class
              method_name = self.class.method_name
              finder_key = self.class.finder_key

              if finder_key
                finder_value = params[finder_key]

                record = model_class.find_by(finder_key => finder_value)
                raise "#{model_class.name} with #{finder_key}=#{finder_value} not found" unless record

                method_params = params.except(finder_key)

                if method_params.empty?
                  record.public_send(method_name)
                else
                  record.public_send(method_name, **method_params)
                end
              else
                model_class.public_send(method_name, **params)
              end
            end
          end
        end
      end
    end
  end
end
