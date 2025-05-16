# frozen_string_literal: true

require_relative '../lib/mcp'

# Example tool with MCP annotations
class WebSearchTool < FastMcp::Tool
  tool_name 'web_search'
  description 'Search the web for information'

  # Add MCP annotations
  title 'Web Search'
  read_only true         # Tool does not modify its environment
  open_world true        # Tool interacts with external entities

  arguments do
    required(:query).filled(:string).description('The search query')
    optional(:max_results).filled(:integer, gt?: 0).description('Maximum number of results to return')
  end

  def call(query:, max_results: 10)
    # This would normally call a web search API
    # For demonstration purposes, we'll just return some fake results
    results = [
      "Result 1 for: #{query}",
      "Result 2 for: #{query}",
      "Result 3 for: #{query}"
    ].take(max_results)

    {
      content: [
        {
          type: 'text',
          text: "Search results for: #{query}\n\n#{results.join("\n")}"
        }
      ]
    }
  end
end

# Example of a destructive tool
class DeleteFileTool < FastMcp::Tool
  tool_name 'delete_file'
  description 'Delete a file from the filesystem'

  # Add MCP annotations
  title 'Delete File'
  read_only false        # Tool modifies its environment
  destructive true       # Tool performs destructive updates
  idempotent true        # Calling repeatedly with same arguments has no additional effect
  open_world false       # Tool doesn't interact with external entities

  arguments do
    required(:path).filled(:string).description('File path to delete')
  end

  def call(path:)
    # In a real implementation, this would delete the file
    # For demonstration purposes, we just return a success message
    {
      content: [
        {
          type: 'text',
          text: "File deleted: #{path}"
        }
      ]
    }
  end
end

# Example of a non-destructive update tool
class CreateRecordTool < FastMcp::Tool
  tool_name 'create_record'
  description 'Create a new record in the database'

  # Add MCP annotations
  title 'Create Database Record'
  read_only false         # Tool modifies its environment
  destructive false       # Tool doesn't perform destructive updates
  idempotent false        # Calling repeatedly creates multiple records
  open_world false        # Tool doesn't interact with external entities

  arguments do
    required(:table).filled(:string).description('Table name')
    required(:data).filled(:hash).description('Record data')
  end

  def call(table:, data:)
    # In a real implementation, this would create a record
    # For demonstration purposes, we just return a success message
    {
      content: [
        {
          type: 'text',
          text: "Record created in table #{table} with data: #{data.inspect}"
        }
      ]
    }
  end
end

# Create and start the server
server = FastMcp::Server.new(name: 'annotation-example', version: '1.0.0')

# Register the tools
server.register_tools(WebSearchTool, DeleteFileTool, CreateRecordTool)

# Start the server
server.start
