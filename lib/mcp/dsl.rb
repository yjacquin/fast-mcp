# frozen_string_literal: true

require_relative 'dsl/dsl'
require_relative 'dsl/dsl_registry'
require_relative 'dsl/active_record_method_adapter'
require_relative 'dsl/model_method_adapter'
require_relative 'dsl/controller_method_adapter'
require_relative 'dsl/controller_dsl'
require_relative 'dsl/auto_include'

FastMcp::DSL::AutoInclude.initialize if defined?(Rails)
