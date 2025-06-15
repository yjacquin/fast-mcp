# Controller Tools in MCP

This guide explains how to expose your Rails controller actions as MCP tools, allowing AI agents to interact directly with your API.

## Overview

The Controller AutoDerive feature allows you to expose controller actions as MCP tools. This is useful when you want to:

- Allow AI agents to interact with your existing API endpoints
- Reuse your existing API authentication and authorization
- Keep your business logic in controllers as per Rails conventions
- Maintain a single source of truth for your API

## Exposing Controller Actions

Use the `expose_action_to_mcp` method to expose controller actions as tools:

```ruby
class UsersController < ApplicationController
  expose_action_to_mcp :index,
                      description: "List all users",
                      parameters: {}

  expose_action_to_mcp :show,
                      description: "Show user details",
                      parameters: {
                        id: { type: :string, description: "User ID" }
                      }

  expose_action_to_mcp :create,
                      description: "Create a new user",
                      read_only: false,
                      parameters: {
                        name: { type: :string, description: "User name" },
                        email: { type: :string, description: "User email" }
                      }

  # Controller actions
  def index
    @users = User.all
    render json: @users
  end

  def show
    @user = User.find(params[:id])
    render json: @user
  end

  def create
    @user = User.new(user_params)
    if @user.save
      render json: @user, status: :created
    else
      render json: { errors: @user.errors }, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.permit(:name, :email)
  end
end
```

## Configuration Options

The `expose_action_to_mcp` method accepts the following options:

- `description` (required): A description of what the action does
- `parameters` (optional): A hash of parameter definitions
- `read_only` (optional): Whether this action modifies data (default: true)
- `tool_name` (optional): Custom name for the tool (default: `controller_name_without_controller_action_name`)

## Parameter Definitions

Each parameter can have the following properties:

- `type`: The parameter type (`:string`, `:integer`, `:boolean`, etc.)
- `description`: A description of the parameter
- `optional`: Whether the parameter is optional (default: false)

## How It Works

When you expose a controller action as a tool:

1. The MCP server registers a tool that wraps the controller action
2. When the tool is called, it:
   - Creates a new instance of your controller
   - Sets up a mock request with the provided parameters
   - Calls the action method
   - Captures and returns the response

This allows AI agents to interact with your API as if they were making HTTP requests.

## Example Usage

Here's an example of how an AI agent might use these tools:

```javascript
const result = await mcpClient.callTool('users_index');
console.log(result);

const user = await mcpClient.callTool('users_show', { id: '123' });
console.log(user);

const newUser = await mcpClient.callTool('users_create', {
  name: 'John Doe',
  email: 'john@example.com'
});
console.log(newUser);
```

## Handling Authentication and Authorization

The controller adapter uses the same authentication and authorization mechanisms as your regular controller actions. If your controller uses:

- Devise authentication
- Pundit policies
- CanCanCan abilities
- Custom `before_action` filters

They will all work as expected.

## Limitations

- The controller adapter currently simulates GET requests by default
- File uploads are not supported yet
- Session-based authentication may require additional configuration
