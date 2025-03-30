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
