# frozen_string_literal: true

# Load the version directly instead of requiring the entire library
# This avoids circular dependencies with gems like mime-types
require_relative 'lib/mcp/version'

Gem::Specification.new do |spec|
  spec.name = 'fast-mcp'
  spec.version = FastMCP::VERSION
  spec.authors = ['Yorick Jacquin']
  spec.email = ['yorickjacquin@gmail.com']

  spec.summary = 'A Ruby implementation of the Model Context Protocol.'
  spec.description = 'A flexible and powerful implementation of the MCP with tools, resources, and prompts support.'
  spec.homepage = 'https://github.com/yjacquin/fast_mcp'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.glob('{lib,bin}/**/*') + %w[LICENSE README.md CHANGELOG.md]
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'dry-schema', '~> 1.14'
  spec.add_dependency 'json', '~> 2.0'
  spec.add_dependency 'mime-types', '~> 3.4'

  # Conditional dependency for Ruby >= 3.3
  if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3.0')
    spec.add_dependency 'base64'
  end

  # Development dependencies are specified in the Gemfile
end
