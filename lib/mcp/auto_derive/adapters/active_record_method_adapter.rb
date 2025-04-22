# frozen_string_literal: true

module FastMcp
  module AutoDerive
    module Adapters
      class ActiveRecordMethodAdapter < AutoDeriveAdapter
        def self.for_method(model, method)
          create_subclass(
            name: method[:tool_name] || "#{model.name.underscore}_#{method[:method_name]}",
            class_name: model.name,
            method_name: method[:method_name],
            description: method[:description],
            parameters: enhance_param_definitions(method),
            read_only: method[:read_only] || true,
            finder_key: finder_key,
            post_process: method[:post_process]
          ).tap do |klass|
            klass.define_singleton_method(:model_class) { model }
            klass.define_singleton_method(:method) { method }
            klass.define_singleton_method(:class_method?) { method[:class_method] || false }

            define_method_call(klass, method)
          end
        end

        def self.define_method_call(klass, method)
          klass.define_method(:call) do |params|
            method_name = self.class.method_name
            method = self.class.method

            params = params.transform_keys(&:to_sym)

            result = result_of_method_call(params, method_name)

            if method[:post_process].respond_to?(:call)
              result = method[:post_process].call(result, params)
            elsif self.class.respond_to?(:post_process)
              result = self.class.post_process(result, params)
            end

            serialize_result(result)
          end
        end

        def result_of_method_call(params, method_name)
          model_class = self.class.model_class
          if self.class.class_method?
            processed_params = process_ar_parameters(params, method_name)

            model_class.public_send(method_name, *processed_params)
          else
            finder_key = self.class.finder_key || :id

            finder_value = params[finder_key.to_sym] || params[finder_key.to_s]

            raise "Required parameter '#{finder_key}' not provided" if finder_value.nil?

            record = model_class.find_by(finder_key => finder_value)
            raise "#{model_class.name} with #{finder_key}=#{finder_value} not found" unless record

            method_params = params.except(finder_key.to_sym, finder_key.to_s)

            processed_params = process_ar_parameters(method_params, method_name)

            if processed_params.empty?
              record.public_send(method_name)
            else
              record.public_send(method_name, *processed_params)
            end
          end
        end

        private

        class << self
          def enhance_param_definitions(method)
            param_definitions = {}
            assign_param_details(param_definitions, method)
            assign_finder_key(param_definitions, method)
            assign_limit_param(param_definitions, method)

            param_definitions
          end

          def assign_finder_key(param_definitions, method)
            finder_key = method[:finder_key]
            return unless finder_key && !method[:class_method]

            param_definitions[finder_key.to_sym] ||= {
              type: :string,
              description: "The #{finder_key} to find the #{model.name} record",
              required: true
            }
          end

          def assign_param_details(param_definitions, method)
            return unless method[:parameters].present?

            method[:parameters].each do |param_name, param_details|
              param_details = param_details.is_a?(Hash) ? param_details.dup : { description: param_details.to_s }

              param_details[:type] ||= :string
              param_details[:description] ||= "#{param_name} parameter"
              param_details[:required] = param_details[:optional] != true

              param_definitions[param_name.to_sym] = param_details
            end
          end

          def assign_limit_param(param_definitions, method)
            return unless method[:method_name] == :limit && !param_definitions.key?(:limit)

            param_definitions[:limit] = {
              type: :integer,
              description: "Number of #{model.name} records to return (default: 5)",
              required: false,
              default: 5
            }
          end
        end

        def serialize_result(result)
          case result
          when ActiveRecord::Base
            result.as_json
          when ActiveRecord::Relation
            result.map(&:as_json)
          when Array
            if result.all? { |item| item.is_a?(ActiveRecord::Base) }
              result.map(&:as_json)
            else
              result
            end
          else
            result
          end
        end

        def process_ar_parameters(params, method_name)
          case method_name
          when :where
            conditions = params[:conditions]
            return [JSON.parse(conditions)] if conditions.is_a?(String)
          when :create!, :update
            attributes = params[:attributes]
            return [JSON.parse(attributes)] if attributes.is_a?(String)
          when :limit
            return [params[:limit]] if params.key?(:limit)
          end
          return params.values if params.is_a?(Hash)

          []
        end
      end
    end
  end
end
