## Claude Desktop
Edit claude_desktop_config.json

### STDIO
For stdio transports, we should first install the gem globally
`gem install fast-mcp`
Then, use the absolute path to your ruby install for the `command` as well as for the file path in `args`.

```json
{
  "mcpServers": {
    "fast-mcp": {
      // Add the absolute path to your ruby install, for instance
      "command": "/Users/username/.rbenv/shims/ruby", 
      "args": [
        // You can also clone this repo and use examples/server_with_stdio_transport.rb
        "/Users/username/path/to/your_fast_mcp_server_with_stdio_transport.rb"
      ]
    }
  }
}
```

### HTTP & SSE
❌ Unfortunately, as of writing this, Anthropic hasn't released support for remote hosts and only acccept STDIO transports.


## Cursor
In MacOS, Edit ~/.cursor/mcp.json

### STDIO
```json
{
  "mcpServers": {
    "server-name": {
      // Add the absolute path to your ruby install, for instance
      "command": "/Users/username/.rbenv/shims/ruby",
      // You can also clone this repo and use examples/server_with_stdio_transport.rb
      "args": ["/Users/username/path/to/your_fast_mcp_server_with_stdio_transport.rb"]
    }
  }
}
```

### HTTP & SSE

```json
{
  "mcpServers": {
    "server-name": {
      // You need to input the url to your SSE endpoint
      "url": "http://localhost:3000/mcp/sse"
    }
  }
}
```
