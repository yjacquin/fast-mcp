#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'fast_mcp'
require 'json'

# Create a server
server = MCP::Server.new(name: 'resource-example-server', version: '1.0.0')

# Class-based tool for incrementing the counter
class IncrementCounterTool < MCP::Tool
  description 'Increment the counter'

  # Class variable to hold server instance
  @server = nil

  # Class method to get server instance
  class << self
    attr_accessor :server
  end

  # Class method to set server instance

  def call
    # Make sure we have a server reference
    raise 'Server not set' unless self.class.server

    # Get the current counter value
    counter_resource = self.class.server.read_resource('counter')
    counter_content = counter_resource.instance.content.to_i

    # Increment the counter
    counter_content += 1

    # Update the resource
    self.class.server.update_resource('counter', counter_content.to_s)

    # Return the new counter value
    { count: counter_content }
  end
end

IncrementCounterTool.server = server

# Define a counter resource
class CounterResource < MCP::Resource
  uri 'counter'
  resource_name 'Counter'
  description 'A simple counter resource'
  mime_type 'text/plain'

  def default_content
    '0'
  end
end

# Define a users resource
class UsersResource < MCP::Resource
  uri 'users'
  resource_name 'Users'
  description 'List of users'
  mime_type 'application/json'

  def default_content
    JSON.generate(
      [
        { id: 1, name: 'Alice', email: 'alice@example.com' },
        { id: 2, name: 'Bob', email: 'bob@example.com' }
      ]
    )
  end
end
# Define a weather resource that updates periodically

class WeatherResource < MCP::Resource
  uri 'weather'
  resource_name 'Weather'
  description 'Current weather conditions'
  mime_type 'application/json'

  def default_content
    JSON.generate(
      {
        temperature: 22.5,
        condition: 'Sunny',
        updated_at: Time.now.to_s
      }
    )
  end
end

server.register_resources(CounterResource, UsersResource, WeatherResource)

# Class-based tool for adding a user
class AddUserTool < MCP::Tool
  description 'Add a new user'

  # Class variable to hold server instance
  @server = nil

  # Class method to get server instance
  class << self
    attr_reader :server
  end

  # Class method to set server instance
  class << self
    attr_writer :server
  end

  arguments do
    required(:name).filled(:string).description("User's name")
    required(:email).filled(:string).description("User's email")
  end

  def call(name:, email:)
    # Make sure we have a server reference
    raise 'Server not set' unless self.class.server

    # Get the current users
    users_resource = self.class.server.read_resource('users')
    users = JSON.parse(users_resource.instance.content, symbolize_names: true)

    # Generate a new ID
    new_id = users.map { |u| u[:id] }.max + 1

    # Create the new user
    new_user = { id: new_id, name: name, email: email }

    # Add the user to the list
    users << new_user

    # Update the resource
    self.class.server.update_resource('users', JSON.generate(users))

    # Return the new user
    new_user
  end
end

# Register the add user tool
AddUserTool.server = server

# Class-based tool for deleting a user
class DeleteUserTool < MCP::Tool
  description 'Delete a user by ID'
  tool_name 'Delete User'

  # Class variable to hold server instance
  @server = nil

  # Class method to get server instance
  class << self
    attr_accessor :server
  end

  arguments do
    required(:id).filled(:integer).description('User ID to delete')
  end

  def call(id:)
    # Make sure we have a server reference
    raise 'Server not set' unless self.class.server

    # Get the current users
    users_resource = self.class.server.read_resource('users')
    users = JSON.parse(users_resource.content, symbolize_names: true)

    # Find the user
    user_index = users.find_index { |u| u[:id] == id }

    # Remove the user
    deleted_user = users.delete_at(user_index)

    # Update the resource
    self.class.server.update_resource('users', JSON.generate(users))

    # Return the deleted user
    deleted_user
  end
end

# Register the delete user tool
DeleteUserTool.server = server
server.register_tools(IncrementCounterTool, AddUserTool, DeleteUserTool)

# Start the server
# puts 'Starting MCP server with resources...'
server.start
