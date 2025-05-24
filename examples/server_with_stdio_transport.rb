#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'fast_mcp'
require 'json'

# Create a server
server = FastMcp::Server.new(name: 'resource-example-server', version: '1.0.0')

# Define a counter resource
class CounterResource < FastMcp::Resource
  uri 'counter'
  resource_name 'Counter'
  description 'A simple counter resource'
  mime_type 'text/plain'

  def initialize
    @count = 0

    super
  end

  attr_accessor :count

  def content
    @count.to_s
  end
end

# Define a users resource
class UsersResource < FastMcp::Resource
  uri 'app:///users'
  resource_name 'Users'
  description 'List of users'
  mime_type 'application/json'

  def initialize
    @users = [
      { id: 1, name: 'Alice', email: 'alice@example.com' },
      { id: 2, name: 'Bob', email: 'bob@example.com' }
    ]

    super
  end

  attr_accessor :users

  def content
    JSON.generate(@users)
  end
end

class UserResource < FastMcp::Resource
  uri 'app:///users/{id}'
  resource_name 'User'
  description 'A user'
  mime_type 'application/json'

  def initialize
    @users = UsersResource.instance.users

    super
  end

  def content
    id = params[:id]

    user = @users.find { |u| u[:id] == id.to_i }

    JSON.generate(user)
  end
end

# Define a weather resource that updates periodically
class WeatherResource < FastMcp::Resource
  uri 'weather'
  resource_name 'Weather'
  description 'Current weather conditions'
  mime_type 'application/json'

  def initialize
    @temperature = 22.5
    @condition = 'Sunny'
    @updated_at = Time.now

    super
  end

  def content
    JSON.generate(
      {
        temperature: @temperature,
        condition: @condition,
        updated_at: @updated_at.to_s
      }
    )
  end
end

server.register_resources(CounterResource, UsersResource, UserResource, WeatherResource)

# Class-based tool for incrementing the counter
class IncrementCounterTool < FastMcp::Tool
  description 'Increment the counter'

  def call
    # Increment the counter
    CounterResource.instance.count += 1

    # Update the resource
    notify_resource_updated('counter')

    # Return the new counter value
    { count: CounterResource.instance.count }
  end
end

# Class-based tool for adding a user
class AddUserTool < FastMcp::Tool
  description 'Add a new user'
  tool_name 'add_user'
  arguments do
    required(:name).filled(:string).description("User's name")
    required(:email).filled(:string).description("User's email")
    optional(:admin).maybe(:bool).hidden
    required(:address).hash do
      required(:street).filled(:string)
      required(:city).filled(:string)
    end
  end

  def call(name:, email:, address:, admin: nil)
    # Get the current users
    users_resource = UsersResource.instance
    users = users_resource.users

    # Generate a new ID
    new_id = users.map { |u| u[:id] }.max + 1

    # Create the new user
    new_user = { id: new_id, name: name, email: email, address: address }

    new_user[:admin] = admin if admin

    # Add the user to the list
    users << new_user

    # Update the resource
    UsersResource.instance.users = users

    # Notify the server that the resource has been updated
    notify_resource_updated('users')

    # Return the new user
    new_user
  end
end

# Class-based tool for deleting a user
class DeleteUserTool < FastMcp::Tool
  description 'Delete a user by ID'
  tool_name 'delete_user'

  arguments do
    required(:id).filled(:integer).description('User ID to delete')
  end

  def call(id:)
    # Get the current users
    users_resource = UsersResource.instance
    users = users_resource.users

    # Find the user
    user_index = users.find_index { |u| u[:id] == id }

    # Remove the user
    deleted_user = users.delete_at(user_index)

    # Update the resource
    users_resource.users = users

    # Notify the server that the resource has been updated
    notify_resource_updated('users')

    # Return the deleted user
    deleted_user
  end
end

server.register_tools(IncrementCounterTool, AddUserTool, DeleteUserTool)

# Start the server
# puts 'Starting FastMcp server with resources...'
server.start
