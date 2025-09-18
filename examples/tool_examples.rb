# frozen_string_literal: true

#
# MCP Tool Examples
# ================
#
# This file demonstrates the different ways to define and use MCP tools.
# FastMcp::Tool is designed to be used as a base class that you inherit from to define your tools.
#
# Key concepts demonstrated:
#
# 1. Creating a tool by inheriting from FastMcp::Tool
# 2. Defining a schema using Dry::Schema to validate inputs
# 3. Using the arguments DSL to define input schemas
# 4. Validating arguments with various predicates (type checking, format checking, etc.)
# 5. Processing nested object structures
# 6. Handling optional arguments
# 7. Using call_with_schema_validation! to ensure inputs match the schema
#
# The preferred way to create tools is to inherit from FastMcp::Tool and define
# the arguments and call method in your subclass.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'fast_mcp'

puts 'MCP Tool Examples'
puts '================='
puts

# Example 1: Class-based with arguments using Dry::Schema
puts 'Example 1: Class-based with arguments using Dry::Schema'

class GreetTool < FastMcp::Tool
  description 'Greet someone by name'

  arguments do
    required(:name).filled(:string).description('Name to greet')
  end

  def call(args)
    "Hello, #{args[:name]}!"
  end
end

# Create an instance and use it
greet_tool = GreetTool.new
puts "Tool name: #{greet_tool.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{greet_tool.class.description}"
puts "Tool schema: #{greet_tool.class.input_schema.inspect}"
puts "Tool call result: #{greet_tool.call(name: 'World')}"
puts

# Example 2: Class with multiple arguments and validations
puts 'Example 2: Class with multiple arguments and validations'

class FullNameGreetTool < FastMcp::Tool
  description 'Greet someone by their full name'

  arguments do
    required(:first_name).filled(:string, min_size?: 2).description('First name')
    required(:last_name).filled(:string, format?: /^[A-Z][a-z]+$/).description('Last name')
  end

  def call(args)
    "Hello, #{args[:first_name]} #{args[:last_name]}!"
  end
end

full_name_tool = FullNameGreetTool.new
puts "Tool name: #{full_name_tool.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{full_name_tool.class.description}"
puts "Tool schema: #{full_name_tool.class.input_schema.inspect}"
puts "Tool call result: #{full_name_tool.call_with_schema_validation!(first_name: 'John', last_name: 'Doe')}"
puts

# Example 3: Array arguments
puts 'Example 3: Array arguments'

class GroupGreetingTool < FastMcp::Tool
  description 'Greet multiple people at once'

  arguments do
    required(:people).filled(:array, min_size?: 1).each(:string)
  end

  def call(args)
    "Hello, #{args[:people].join(', ')}!"
  end
end

group_tool = GroupGreetingTool.new
puts "Tool name: #{group_tool.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{group_tool.class.description}"
puts "Tool schema: #{group_tool.class.input_schema.inspect}"
puts "Tool call result: #{group_tool.call_with_schema_validation!(people: %w[Alice Bob Charlie])}"
puts

# Example 4: Calculator with multiple argument types
puts 'Example 4: Calculator with multiple argument types'

class CalculatorTool < FastMcp::Tool
  description 'Perform a calculation'

  arguments do
    required(:x).filled(:integer, gteq?: 0).description('First number')
    required(:y).filled(:integer, gteq?: 0).description('Second number')
    required(:operation).filled(:string,
                                included_in?: %w[add subtract multiply divide]).description('Operation to perform')
  end

  def call(args)
    x = args[:x]
    y = args[:y]
    case args[:operation]
    when 'add'
      x + y
    when 'subtract'
      x - y
    when 'multiply'
      x * y
    when 'divide'
      x.to_f / y
    end
  end
end

calculator_tool = CalculatorTool.new
puts "Tool name: #{calculator_tool.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{calculator_tool.class.description}"
puts "Tool schema: #{calculator_tool.class.input_schema.inspect}"
puts "Tool call result: #{calculator_tool.call_with_schema_validation!(x: 10, y: 5, operation: 'multiply')}"
puts

# Example 5: Nested object structures
puts 'Example 5: Nested object structures'

class UserValidatorTool < FastMcp::Tool
  description 'Validate user information'

  arguments do
    required(:user).hash do
      required(:username).filled(:string, min_size?: 3, max_size?: 20,
                                          format?: /^[a-zA-Z0-9_]+$/).description('Username')
      required(:email).filled(:string).description('Email address')
      required(:age).filled(:integer, gt?: 18, lt?: 120).description('Age in years')
      required(:interests).array(:string).description('User interests')
    end
  end

  def call(args)
    user = args[:user]
    "User #{user[:username]} (#{user[:email]}) is #{user[:age]} years old and likes #{user[:interests].join(', ')}."
  end
end

user_validator = UserValidatorTool.new
puts "Tool name: #{user_validator.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{user_validator.class.description}"
puts "Tool schema: #{user_validator.class.input_schema.inspect}"
puts "Tool call result: #{user_validator.call_with_schema_validation!(
  user: {
    username: 'johndoe',
    email: 'john@example.com',
    age: 30,
    interests: %w[coding reading]
  }
)}"
puts

# Example 6: Optional arguments
puts 'Example 6: Optional arguments'

class UserProfileTool < FastMcp::Tool
  description 'Create a user profile with optional fields'

  arguments do
    required(:username).filled(:string, min_size?: 3, max_size?: 20, format?: /^[a-zA-Z0-9_]+$/).description('Username')
    required(:email).filled(:string).description('Email address')
    required(:age).filled(:integer, gt?: 18, lt?: 120).description('Age in years')
    optional(:interests).array(:string).description('User interests')
  end

  def call(args)
    interests_text = args[:interests] ? args[:interests].join(', ') : 'nothing in particular'
    "User profile created: #{args[:username]} (#{args[:email]}) is #{args[:age]} years old and likes #{interests_text}."
  end
end

user_profile = UserProfileTool.new
puts "Tool name: #{user_profile.class.name.split('::').last.gsub(/Tool$/, '').downcase}"
puts "Tool description: #{user_profile.class.description}"
puts "Tool schema: #{user_profile.class.input_schema.inspect}"
puts "Tool call result with interests: #{user_profile.call_with_schema_validation!(
  username: 'johndoe',
  email: 'john@example.com',
  age: 30,
  interests: %w[coding reading]
)}"
puts "Tool call result without interests: #{user_profile.call_with_schema_validation!(
  username: 'janedoe',
  email: 'jane@example.com',
  age: 25
)}"
puts

# Example 7: Tools with descriptions and hidden properties
puts 'Example 7: Tools with descriptions and hidden properties'

class ApiCallTool < FastMcp::Tool
  description 'Make an authenticated API call'

  arguments do
    required(:url).filled(:string).description('API endpoint URL')
    required(:method).filled(:string, included_in?: %w[GET POST PUT DELETE]).description('HTTP method')
    optional(:headers).hash.description('HTTP headers to include')
    optional(:api_key).filled(:string).description('API key for authentication').hidden(true)
    optional(:secret_token).filled(:string).hidden(true) # Hidden field without description
  end

  def call(args)
    headers_info = args[:headers] ? 'with custom headers' : 'with default headers'
    auth_info = args[:api_key] ? 'authenticated' : 'unauthenticated'
    "Making #{auth_info} #{args[:method]} request to #{args[:url]} #{headers_info}"
  end
end

api_tool = ApiCallTool.new
puts "Tool: #{api_tool.class.name}"
puts 'JSON Schema:'
require 'json'
puts JSON.pretty_generate(api_tool.class.input_schema_to_json)
puts "Call result: #{api_tool.call(url: 'https://api.example.com/users', method: 'GET', api_key: 'secret123')}"
puts

class DatabaseQueryTool < FastMcp::Tool
  description 'Execute a database query with connection settings'

  arguments do
    required(:query).filled(:string).description('SQL query to execute')
    required(:connection).description('Database connection settings').hash do
      required(:host).filled(:string).description('Database host')
      required(:port).filled(:integer, gteq?: 1, lteq?: 65_535).description('Database port')
      required(:database).filled(:string).description('Database name')
      required(:username).filled(:string).description('Database username')
      required(:password).filled(:string).hidden(true) # Hidden password
      optional(:ssl_mode).filled(:string, included_in?: %w[disable require prefer]).description('SSL connection mode')
      optional(:internal_id).filled(:string).hidden(true) # Hidden internal field
    end
    optional(:timeout).filled(:integer, gteq?: 1).description('Query timeout in seconds')
    optional(:debug_info).filled(:string).hidden(true) # Hidden debug field
  end

  def call(args)
    conn = args[:connection]
    timeout_info = args[:timeout] ? "with #{args[:timeout]}s timeout" : 'with default timeout'
    ssl_info = conn[:ssl_mode] ? "using #{conn[:ssl_mode]} SSL" : 'without SSL config'
    "Executing query on #{conn[:database]}@#{conn[:host]}:#{conn[:port]} #{ssl_info} #{timeout_info}"
  end
end

db_tool = DatabaseQueryTool.new
puts "Tool: #{db_tool.class.name}"
puts 'JSON Schema:'
puts JSON.pretty_generate(db_tool.class.input_schema_to_json)
puts "Call result: #{db_tool.call(
  query: 'SELECT * FROM users',
  connection: {
    host: 'localhost',
    port: 5432,
    database: 'myapp',
    username: 'admin',
    password: 'secret123',
    ssl_mode: 'require'
  },
  timeout: 30
)}"
puts

# Example 8: Tools with annotations
puts 'Example 8: Tools with annotations'

class WebSearchTool < FastMcp::Tool
  description 'Search the web for information'

  annotations(
    title: 'Web Search',
    read_only_hint: true,
    open_world_hint: true
  )

  arguments do
    required(:query).filled(:string).description('Search query')
    optional(:max_results).filled(:integer, gteq?: 1, lteq?: 50).description('Maximum number of results')
  end

  def call(args)
    max_results = args[:max_results] || 10
    "Searching for '#{args[:query]}' (returning up to #{max_results} results)..."
  end
end

class DeleteFileTool < FastMcp::Tool
  description 'Delete a file from the filesystem'

  annotations(
    title: 'Delete File',
    read_only_hint: false,
    destructive_hint: true,
    idempotent_hint: true,
    open_world_hint: false
  )

  arguments do
    required(:path).filled(:string).description('File path to delete')
  end

  def call(args)
    "Would delete file at: #{args[:path]}"
  end
end

class CreateRecordTool < FastMcp::Tool
  description 'Create a new record in the database'

  annotations(
    title: 'Create Database Record',
    read_only_hint: false,
    destructive_hint: false,
    idempotent_hint: false,
    open_world_hint: false
  )

  arguments do
    required(:table).filled(:string).description('Database table name')
    required(:data).hash.description('Record data')
  end

  def call(args)
    "Creating record in #{args[:table]} with data: #{args[:data].inspect}"
  end
end

# Demonstrate the web search tool
web_search = WebSearchTool.new
puts "Tool: #{web_search.class.name}"
puts "Annotations: #{web_search.class.annotations.inspect}"
puts "Call result: #{web_search.call(query: 'Ruby programming')}"
puts

# Demonstrate the delete file tool
delete_file = DeleteFileTool.new
puts "Tool: #{delete_file.class.name}"
puts "Annotations: #{delete_file.class.annotations.inspect}"
puts "Call result: #{delete_file.call(path: '/tmp/test.txt')}"
puts

# Demonstrate the create record tool
create_record = CreateRecordTool.new
puts "Tool: #{create_record.class.name}"
puts "Annotations: #{create_record.class.annotations.inspect}"
puts "Call result: #{create_record.call(table: 'users', data: { name: 'John', email: 'john@example.com' })}"
