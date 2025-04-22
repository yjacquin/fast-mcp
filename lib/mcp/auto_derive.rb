# frozen_string_literal: true

require_relative 'auto_derive/auto_derive'
require_relative 'auto_derive/registry/auto_derive_registry'
require_relative 'auto_derive/adapters/active_record_method_adapter'
require_relative 'auto_derive/adapters/model_method_adapter'
require_relative 'auto_derive/adapters/controller_method_adapter'
require_relative 'auto_derive/controller_auto_derive'
require_relative 'auto_derive/auto_include'
require_relative 'auto_derive/auto_derive_configuration'
FastMcp::AutoDerive::AutoInclude.initialize if defined?(Rails)
