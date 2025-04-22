# frozen_string_literal: true

require_relative '../lib/mcp'
require 'active_record'

# Set up a simple in-memory database for the example
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')

# Create a users table
ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :name
    t.string :email
    t.integer :age
    t.timestamps
  end
end

# Define a User model
class User < ActiveRecord::Base
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  # Define a class method for finding popular users
  def self.popular
    order(created_at: :desc).limit(5)
  end
end

# Create some sample users
User.create!(name: 'John Doe', email: 'john@example.com', age: 30)
User.create!(name: 'Jane Smith', email: 'jane@example.com', age: 25)
User.create!(name: 'Bob Johnson', email: 'bob@example.com', age: 40)

# Create custom adapter for find_user tool with annotations
find_user_tool = FastMcp::AutoDerive::BaseAdapter.create_subclass(
  name: 'find_user',
  class_name: 'User',
  method_name: 'find',
  description: 'Find a user by ID',
  read_only: true,
  title: 'Find User',
  idempotent: true,
  open_world: false
)

# Create custom adapter for create_user tool with annotations
create_user_tool = FastMcp::AutoDerive::BaseAdapter.create_subclass(
  name: 'create_user',
  class_name: 'User',
  method_name: 'create!',
  description: 'Create a new user',
  read_only: false,
  destructive: false,
  idempotent: false,
  open_world: false,
  parameters: {
    name: { type: :string, description: 'User name' },
    email: { type: :string, description: 'User email' },
    age: { type: :integer, description: 'User age', optional: true }
  },
  finder_key: nil
)

# Create custom adapter for delete_user tool with annotations
delete_user_tool = FastMcp::AutoDerive::BaseAdapter.create_subclass(
  name: 'delete_user',
  class_name: 'User',
  method_name: 'destroy',
  description: 'Delete a user by ID',
  read_only: false,
  title: 'Delete User',
  destructive: true,
  idempotent: true,
  open_world: false
)

# Create adapter for finding all users (no finder_key)
all_users_tool = FastMcp::AutoDerive::BaseAdapter.create_subclass(
  name: 'list_users',
  class_name: 'User',
  method_name: 'all',
  description: 'List all users',
  read_only: true,
  title: 'List All Users',
  idempotent: true,
  open_world: false,
  finder_key: nil
)

# Implement call methods for each adapter class
find_user_tool.class_eval do
  def call(id:)
    result = handle_errors do
      model_class = self.class.class_name.constantize
      record = model_class.public_send(self.class.method_name, id)
      serialize_result(record)
    end

    if result.is_a?(Hash) && result[:isError]
      result
    else
      { content: [{ type: 'text', text: "Found user: #{result.inspect}" }] }
    end
  end
end

create_user_tool.class_eval do
  def call(**params)
    result = handle_errors do
      model_class = self.class.class_name.constantize
      record = model_class.public_send(self.class.method_name, params)
      serialize_result(record)
    end

    if result.is_a?(Hash) && result[:isError]
      result
    else
      { content: [{ type: 'text', text: "Created user: #{result.inspect}" }] }
    end
  end
end

delete_user_tool.class_eval do
  def call(id:)
    result = handle_errors do
      model_class = self.class.class_name.constantize
      record = model_class.find(id)
      record.public_send(self.class.method_name)
      "User with ID #{id} deleted successfully"
    end

    if result.is_a?(Hash) && result[:isError]
      result
    else
      { content: [{ type: 'text', text: result }] }
    end
  end
end

all_users_tool.class_eval do
  def call(**_params)
    result = handle_errors do
      model_class = self.class.class_name.constantize
      records = model_class.public_send(self.class.method_name)
      serialize_result(records)
    end

    if result.is_a?(Hash) && result[:isError]
      result
    else
      { content: [{ type: 'text', text: "All users: #{result.inspect}" }] }
    end
  end
end

# Create and start the server
server = FastMcp::Server.new(name: 'auto-derived-tools-example', version: '1.0.0')

# Register the auto-derived tools
server.register_tools(
  find_user_tool,
  create_user_tool,
  delete_user_tool,
  all_users_tool
)

# Start the server
server.start
