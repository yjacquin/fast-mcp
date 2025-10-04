# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2025-10-04

### Added

- **MCP Protocol 2025-06-18 Support**: Updated to the latest Model Context Protocol specification
- **OAuth 2.1 Resource Server Implementation**: Full OAuth 2.1 compliance with support for:
  - JWT token validation with JWKS support
  - Opaque token validation with custom validator
  - Scope-based authorization (tools, resources, admin)
  - Audience binding (RFC 8707) for confused deputy prevention
  - Protected Resource Metadata endpoint (RFC 9728)
  - WWW-Authenticate headers in error responses
  - HTTPS enforcement (configurable per environment)
- **StreamableHTTP Transport**: Modern unified transport replacing legacy HTTP+SSE with:
  - Single `/mcp` endpoint for both requests and streaming
  - Improved session management with cryptographically secure session IDs
  - Rack hijacking support for efficient SSE connections
  - DNS rebinding protection
  - Protocol version header validation
- **Fiber-Based Concurrency Support**: Automatic async mode detection with seamless fallback:
  - Auto-detection of Fiber scheduler (Falcon, async gem)
  - Graceful fallback to thread-based concurrency (Puma, Unicorn)
  - Manual override capability via `async_mode` option
- **Enhanced Metadata Handling**: Tool and Resource `_meta` field support with:
  - Reserved prefix validation (`mcp:`, `mcp-`)
  - Metadata sanitization and merging
  - Format validation
- New transports: `OAuthStreamableHttpTransport`, `AuthenticatedStreamableHttpTransport`
- Comprehensive OAuth documentation suite (6 new guides, 4,000+ lines)
- New examples demonstrating OAuth, StreamableHTTP, and authenticated transports

### Changed

- Protocol version updated from `2024-11-05` to `2025-06-18`
- Base transport abstraction introduced for common functionality
- Server metadata response now includes formatted `_meta` field

### Deprecated

- Legacy `RackTransport` (HTTP+SSE with separate endpoints) - still functional but migration recommended
- Old path configuration (`path_prefix`, `messages_route`, `sse_route`) in favor of unified `path` parameter

### Fixed

- Audience binding validation logic in OAuth resource server

### Dependencies

- Added: `jwt` gem (~> 3.1) for OAuth 2.1 support

### Migration Guide

See [docs/migration_guide.md](docs/migration_guide.md) and [docs/rails_migration_guide.md](docs/rails_migration_guide.md) for detailed migration instructions from legacy transports to StreamableHTTP.

## [1.6.0] - 2025-09-28

### Added

- Tool annotations support for providing hints about tool behavior (readOnlyHint, destructiveHint, etc.) [#96 @pauloarruda](https://github.com/yjacquin/fast-mcp/pull/96)
- GitHub Discussions link in README [#139 @jeznicholson](https://github.com/yjacquin/fast-mcp/pull/139)
- GitHub Sponsors funding configuration [#3d5a7e5 @yjacquin](https://github.com/yjacquin/fast-mcp/commit/3d5a7e5)
- Server hook `on_error_result` for handling tool execution errors [#129 @yannickutard](https://github.com/yjacquin/fast-mcp/pull/129)
- Support for transport option in rack_middleware [#149 @josevalim](https://github.com/yjacquin/fast-mcp/pull/149)

### Fixed

- Tool name validation and override for invalid names [#100 @abdelrahmanothman](https://github.com/yjacquin/fast-mcp/pull/100)
- Typo fixes in sinatra_integration.md [#131 @ilyakamenko](https://github.com/yjacquin/fast-mcp/pull/131) [#102 @anton](https://github.com/yjacquin/fast-mcp/pull/102)
- Add trailing comma to generated initializer template for better Ruby style [#123 @zachhaitz](https://github.com/yjacquin/fast-mcp/pull/123)
- Fix missing commas for params hash [#121 @FanaHOVA](https://github.com/yjacquin/fast-mcp/pull/121)
- RuboCop linting issues resolution [fa6af0b @yjacquin](https://github.com/yjacquin/fast-mcp/commit/fa6af0b)

### Changed

- Updated GitHub Actions dependencies: checkout v4→v5, download-artifact v4→v5 [#141 #142 @dependabot](https://github.com/yjacquin/fast-mcp/pull/141)
- Relax Rack version requirements for better compatibility (>= 2.0, < 4.0) [#133 @eproulx](https://github.com/yjacquin/fast-mcp/pull/133)
- Load generators only when necessary for improved performance [#153 @josevalim](https://github.com/yjacquin/fast-mcp/pull/153)
- Drop schema compiler to use Dry's built-in functionality [#152 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/152), thanks @redox for the help !

## [1.5.0] - 2025-06-01

### Added

- Handle filtering tools and resources [#85 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/85)
- Support for resource templates 🥳 Big thanks to @danielcooper for the contribution [#84 co-authored by @danielcooper and @yjacquin](https://github.com/yjacquin/fast-mcp/pull/84)
- Possibility to authorize requests before tool calls [#79 @EuanEdgar](https://github.com/yjacquin/fast-mcp/pull/79)
- Possibility to read request headers in tool calls [#78 @EuanEdgar](https://github.com/yjacquin/fast-mcp/pull/78)

### Changed

- Bump Dependencies [#86 @aothelal](https://github.com/yjacquin/fast-mcp/pull/86)
- ⚠️ Resources are now stateless, meaning that in-memory resources won't work anymore, they require an external data source such as database, file to read and write too, etc. This was needed for a refactoring of the resource class for the [resource template PR](https://github.com/yjacquin/fast-mcp/pull/84)

### Fixed

- Stop overriding log level to info [#91 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/91)
- Properly handle ping request responses from clients [#89 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/89)
- Add Thread Safety to RackTransport sse_clients [#82 @Kevin-K](https://github.com/yjacquin/fast-mcp/pull/82)

## [1.4.0] - 2025-05-10

### Added

- Conditionnally hidden properties for tool calls (#70) [#70 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/70)
- Metadata to tool call results (#69) [#69 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/69)
- Link to official Discord Server in README.md

## [1.3.2] - 2025-05-08

### Changed

- Logs are now less verbose by default [#64 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/64)

### Fixed

- Fix undefined method `call' for an instance of String error log [#61 @radwo](https://github.com/yjacquin/fast-mcp/pull/61)

## [1.3.1] - 2025-04-30

### Fixed

- Allow ipv4 mapped to ipv6 (#56) [#56 @josevalim](https://github.com/yjacquin/fast-mcp/pull/56)
- Add items to array (#55) [#55 @josevalim](https://github.com/yjacquin/fast-mcp/pull/56)
- Ping is a regular message event (#54) [#56 @josevalim](https://github.com/yjacquin/fast-mcp/pull/56)

## [1.3.0] - 2025-04-28

### Added

- Added automatic forwarding of query params from to the messages endpoint [@yjacquin](https://github.com/yjacquin/fast-mcp/commit/011d968ac982d0b0084f7753dcac5789f66339ee)

### Fixed

- Declare rack as an explicit dependency [#49 @subelsky](https://github.com/yjacquin/fast-mcp/pull/49)
- Fix notifications/initialized response [#51 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/51)

## [1.2.0] - 2025-04-21

### Added

- Security enhancement: Bing only to localhost by default [#44 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/44)
- Prevent AuthenticatedRackMiddleware from blocking other rails routes[#35 @JulianPasquale](https://github.com/yjacquin/fast-mcp/pull/35)
- Stop Forcing reconnections after 30 pings [#42 @zoedsoupe](https://github.com/yjacquin/fast-mcp/pull/42)

## [1.1.0] - 2025-04-13

### Added

- Security enhancement: Added DNS rebinding protection by validating Origin headers [#32 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/32/files)
- Added configuration options for allowed origins in rack middleware [#32 @yjacquin](https://github.com/yjacquin/fast-mcp/pull/32/files)
- Allow to change the SSE and Messages route [#23 @pedrofurtado](https://github.com/yjacquin/fast-mcp/pull/23)
- Fix invalid return value when processing notifications/initialized request [#31 @abMatGit](https://github.com/yjacquin/fast-mcp/pull/31)

## [1.0.0] - 2025-03-30

### Added

- Rails integration improvements via enhanced Railtie support
- Automatic tool and resource registration in Rails applications
- Extended Rails autoload paths for tools and resources directories
- Sample generator templates for resources and tools
- MCP Client configuration documentation as reported by [#8 @sivag-csod](https://github.com/yjacquin/fast-mcp/issues/8)
- Example Ruby on Rails app in the documentation
- `FastMcp.server` now exposes the MCP server to apps that may need it to access resources
- Automated Github Releases through Github Workflow

### Fixed

- Fixed bug with Rack middlewares not being initialized properly.
- Fixed bug with STDIO logging preventing a proper connection with clients [# 11 @cs3b](https://github.com/yjacquin/fast-mcp/issues/11)
- Fixed Rails SSE streaming detection and handling
- Improved error handling in client reconnection scenarios
- Namespace consistency correction (FastMCP -> FastMcp) throughout the codebase

### Improved

- ⚠️ [Breaking] Resource content declaration changes

  - Now resources implement `content` over `default_content`
  - `content` is dynamically called when calling a resource, this implies we can declare dynamic resource contents like:

  ```ruby
  class HighestScoringUsersResource < FastMcp::Resource
  ...
    def content
      User.order(score: :desc).last(5).map(&:as_json)
    end
  end
  ```

- More robust SSE connection lifecycle management
- Optimized test suite with faster execution times
- Better logging for debugging connection issues
- Documentation had outdated examples

## [0.1.0] - 2025-03-12

### Added

- Initial release of the Fast MCP library
- FastMcp::Tool class with multiple definition styles
- FastMcp::Server class with STDIO transport and HTTP / SSE transport
- Rack Integration with authenticated and standard middleware options
- Resource management with subscription capabilities
- Binary resource support
- Examples with STDIO Transport, HTTP & SSE, Rack app
- Initialize lifecycle with capabilities
- Comprehensive test suite with RSpec
