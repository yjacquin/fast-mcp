#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'fast_mcp'
require 'json'

# Create a server
server = FastMcp::Server.new(name: 'resource-example-server', version: '1.0.0')

# Define a counter resource (stateless - reads from file)
class CounterResource < FastMcp::Resource
  uri 'counter'
  resource_name 'Counter'
  description 'A simple counter resource'
  mime_type 'text/plain'

  def content
    # Read counter from file or return default
    File.exist?('counter.txt') ? File.read('counter.txt').strip : '0'
  end
end

# Define a users resource (stateless - reads from file)
class UsersResource < FastMcp::Resource
  uri 'app:///users'
  resource_name 'Users'
  description 'List of users'
  mime_type 'application/json'

  def content
    # Read users from file or return default
    if File.exist?('users.json')
      File.read('users.json')
    else
      JSON.generate(
        [
          { id: 1, name: 'Alice', email: 'alice@example.com' },
          { id: 2, name: 'Bob', email: 'bob@example.com' }
        ]
      )
    end
  end
end

class UserResource < FastMcp::Resource
  uri 'app:///users/{id}'
  resource_name 'User'
  description 'A user'
  mime_type 'application/json'

  def content
    id = params[:id]

    # Read users from file or use default
    users_data = if File.exist?('users.json')
                   JSON.parse(File.read('users.json'))
                 else
                   [
                     { 'id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com' },
                     { 'id' => 2, 'name' => 'Bob', 'email' => 'bob@example.com' }
                   ]
                 end

    user = users_data.find { |u| u['id'] == id.to_i }

    JSON.generate(user)
  end
end

# Define a weather resource that updates periodically
class WeatherResource < FastMcp::Resource
  uri 'weather'
  resource_name 'Weather'
  description 'Current weather conditions'
  mime_type 'application/json'

  def content
    JSON.generate(
      {
        temperature: rand(15..30),
        condition: ['Sunny', 'Cloudy', 'Rainy'].sample,
        updated_at: Time.now.to_s
      }
    )
  end
end

# Example prompt that uses inline text instead of ERB templates
class InlinePrompt < FastMcp::Prompt
  prompt_name 'inline_example'
  description 'An example prompt that uses inline text instead of ERB templates'
  
  arguments do
    required(:query).description('The user query to respond to')
    optional(:context).description('Additional context for the response')
  end

  def call(query:, context: nil)
    # Create assistant message
    assistant_message = "I'll help you answer your question about: #{query}"
    
    # Create user message
    user_message = if context
                     "My question is: #{query}\nHere's some additional context: #{context}"
                   else
                     "My question is: #{query}"
                   end

    # Using the messages method with a hash
    messages(
      assistant: assistant_message,
      user: user_message
    )
  end
end

server.register_resources(CounterResource, UsersResource, UserResource, WeatherResource)
server.register_prompts(InlinePrompt)

# Class-based tool for incrementing the counter
class IncrementCounterTool < FastMcp::Tool
  description 'Increment the counter'

  def call
    # Read current counter value
    current_count = File.exist?('counter.txt') ? File.read('counter.txt').strip.to_i : 0

    # Increment the counter
    new_count = current_count + 1

    # Write back to file
    File.write('counter.txt', new_count.to_s)

    # Update the resource
    notify_resource_updated('counter')

    # Return the new counter value
    { count: new_count }
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
    # Read current users
    users = if File.exist?('users.json')
              JSON.parse(File.read('users.json'))
            else
              [
                { 'id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com' },
                { 'id' => 2, 'name' => 'Bob', 'email' => 'bob@example.com' }
              ]
            end

    # Generate a new ID
    new_id = users.map { |u| u['id'] }.max + 1

    # Create the new user
    new_user = { 'id' => new_id, 'name' => name, 'email' => email, 'address' => address }
    new_user['admin'] = admin if admin

    # Add the user to the list
    users << new_user

    # Write back to file
    File.write('users.json', JSON.generate(users))

    # Notify the server that the resource has been updated
    notify_resource_updated('app:///users')

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
    # Read current users
    users = if File.exist?('users.json')
              JSON.parse(File.read('users.json'))
            else
              [
                { 'id' => 1, 'name' => 'Alice', 'email' => 'alice@example.com' },
                { 'id' => 2, 'name' => 'Bob', 'email' => 'bob@example.com' }
              ]
            end

    # Find and remove the user
    user_index = users.find_index { |u| u['id'] == id }
    deleted_user = users.delete_at(user_index) if user_index

    # Write back to file
    File.write('users.json', JSON.generate(users))

    # Notify the server that the resource has been updated
    notify_resource_updated('app:///users')

    # Return the deleted user
    deleted_user
  end
end

server.register_tools(IncrementCounterTool, AddUserTool, DeleteUserTool)

# Start the server
# puts 'Starting FastMcp server with resources...'
server.start
