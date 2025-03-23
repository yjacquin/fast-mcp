#!/usr/bin/env ruby
# frozen_string_literal: true

# This script verifies that the gemspec can be loaded correctly
# It's used in CI to catch issues early

require 'rubygems'
require 'bundler'

puts "Ruby version: #{RUBY_VERSION}"
puts 'Loading gemspec...'

begin
  gemspec = Gem::Specification.load(File.expand_path('../fast-mcp.gemspec', __dir__))
  puts "Successfully loaded gemspec for #{gemspec.name} version #{gemspec.version}"
  exit 0
rescue StandardError => e
  puts "Error loading gemspec: #{e.message}"
  puts e.backtrace
  exit 1
end
