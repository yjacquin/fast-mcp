# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Rails 7 Compatibility' do
  it 'loads without errors in Rails 7 environment' do
    # Simulate Rails 7 environment
    stub_const('Rails::VERSION::MAJOR', 7)
    stub_const('Rails::VERSION::MINOR', 0)
    stub_const('Rails::VERSION::TINY', 8)
    
    expect { require 'fast_mcp' }.not_to raise_error
  end

  it 'has compatible dependencies' do
    gemspec = Gem::Specification.load('fast-mcp.gemspec')
    
    # Check Rails dependency
    rails_dep = gemspec.dependencies.find { |d| d.name == 'rails' }
    expect(rails_dep).to be_present
    expect(rails_dep.requirement.to_s).to include('>= 7.0')
    expect(rails_dep.requirement.to_s).to include('< 8.0')
    
    # Check Rack dependency
    rack_dep = gemspec.dependencies.find { |d| d.name == 'rack' }
    expect(rack_dep).to be_present
    expect(rack_dep.requirement.to_s).to include('>= 2.2')
    expect(rack_dep.requirement.to_s).to include('< 4.0')
  end

  it 'railtie works with Rails 7' do
    # Mock Rails application
    app = double('Rails::Application')
    config = double('Rails::Configuration')
    allow(config).to receive(:autoload_paths).and_return([])
    allow(config).to receive(:autoload_paths=)
    allow(app).to receive(:config).and_return(config)
    allow(app).to receive(:root).and_return(Pathname.new('/tmp/test_app'))
    
    # Mock Rails version
    stub_const('Rails::VERSION::STRING', '7.0.8.7')
    
    expect {
      railtie = FastMcp::Railtie.new
      railtie.initializers.find { |i| i.name == 'fast_mcp.setup_autoload_paths' }.run(app)
    }.not_to raise_error
  end
end 