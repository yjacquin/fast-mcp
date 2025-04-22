# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative '../mcp/server'
require_relative 'auto_derive/auto_derive'
require_relative 'auto_derive/adapters/auto_derive_adapter'
require_relative 'auto_derive/registry/auto_derive_registry'

# Create ActionTool and ActionResource modules at load time
unless defined?(ActionTool)
  module ::ActionTool
    Base = FastMcp::Tool
  end
end

unless defined?(ActionResource)
  module ::ActionResource
    Base = FastMcp::Resource
  end
end

module FastMcp
  class Railtie < Rails::Railtie
    # Force ActiveRecord to load immediately and include AutoDerive
    # This needs to happen before any models are loaded
    ActiveSupport.on_load(:active_record) do
      puts 'Including FastMcp::AutoDerive in ActiveRecord::Base via on_load hook'
      include FastMcp::AutoDerive
    end

    initializer 'fast_mcp.setup_autoload_paths' do |app|
      app.config.autoload_paths += %W[
        #{app.root}/app/tools
        #{app.root}/app/resources
      ]
    end

    # Also include AutoDerive early in the initialization process as a backup
    initializer 'fast_mcp.include_auto_derive', before: :bootstrap_hook do
      # Force ActiveRecord to load immediately
      require 'active_record'
      puts 'Including FastMcp::AutoDerive in ActiveRecord::Base'
      ActiveRecord::Base.include FastMcp::AutoDerive

      # Include AutoDerive in common base classes if they exist
      if Object.const_defined?('ApplicationRecord')
        puts 'Found ApplicationRecord, including FastMcp::AutoDerive'
        ApplicationRecord.include FastMcp::AutoDerive
      end

      if Object.const_defined?('Model')
        puts 'Found Model base class, including FastMcp::AutoDerive'
        Model.include FastMcp::AutoDerive
      end
    end

    # Move tool generation to later in the process, after all models are loaded
    initializer 'fast_mcp.generate_tools', after: :load_config_initializers do
      # Defer tool generation until after all initializers are done
      Rails.application.config.after_initialize do
        puts 'After initialize: Generating tools from AutoDerive'
        FastMcp::AutoDerive::AutoDeriveRegistry.generate_tools
      end
    end

    config.after_initialize do
      # Load all files in app/tools and app/resources directories
      Dir[Rails.root.join('app', 'tools', '**', '*.rb')].each { |f| require f }
      Dir[Rails.root.join('app', 'resources', '**', '*.rb')].each { |f| require f }
    end

    # Add rake tasks
    rake_tasks do
      # Path to the tasks directory in the gem
      path = File.expand_path('../tasks', __dir__)
      Dir.glob("#{path}/**/*.rake").each { |f| load f }
    end
  end
end
