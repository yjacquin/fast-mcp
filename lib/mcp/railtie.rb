# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative '../mcp/server'
require_relative 'auto_derive/auto_derive'

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
      include FastMcp::AutoDerive
    end

    initializer 'fast_mcp.setup_autoload_paths' do |app|
      app.config.autoload_paths += %W[
        #{app.root}/app/tools
        #{app.root}/app/resources
      ]
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
