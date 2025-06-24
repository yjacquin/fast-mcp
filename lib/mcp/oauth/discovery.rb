# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'

module FastMcp
  module OAuth
    # OAuth 2.1 Authorization Server Discovery
    # RFC 8414: https://tools.ietf.org/html/rfc8414
    class Discovery
      class DiscoveryError < StandardError; end

      # Standard OAuth 2.1 authorization server metadata endpoints
      WELL_KNOWN_PATHS = [
        '/.well-known/oauth-authorization-server',
        '/.well-known/openid-configuration'
      ].freeze

      # Required OAuth 2.1 authorization server metadata fields
      REQUIRED_METADATA = %w[
        issuer
        authorization_endpoint
        token_endpoint
        response_types_supported
        subject_types_supported
        id_token_signing_alg_values_supported
      ].freeze

      # Optional but commonly used metadata fields
      OPTIONAL_METADATA = %w[
        jwks_uri
        registration_endpoint
        scopes_supported
        response_modes_supported
        grant_types_supported
        token_endpoint_auth_methods_supported
        token_endpoint_auth_signing_alg_values_supported
        service_documentation
        ui_locales_supported
        op_policy_uri
        op_tos_uri
        revocation_endpoint
        revocation_endpoint_auth_methods_supported
        revocation_endpoint_auth_signing_alg_values_supported
        introspection_endpoint
        introspection_endpoint_auth_methods_supported
        introspection_endpoint_auth_signing_alg_values_supported
        code_challenge_methods_supported
      ].freeze

      attr_reader :logger, :timeout, :metadata_cache

      def initialize(options = {})
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @timeout = options.fetch(:timeout, 30)
        @metadata_cache = {}
        @cache_mutex = Mutex.new
        @cache_ttl = options.fetch(:cache_ttl, 300) # 5 minutes default
      end

      # Discover authorization server metadata from issuer
      def discover_metadata(issuer_url)
        @cache_mutex.synchronize do
          cache_key = issuer_url
          cached_entry = @metadata_cache[cache_key]

          if cached_entry && (Time.now - cached_entry[:cached_at]) < @cache_ttl
            @logger.debug("Using cached metadata for issuer: #{issuer_url}")
            return cached_entry[:metadata]
          end

          @logger.debug("Discovering metadata for issuer: #{issuer_url}")
          metadata = fetch_metadata(issuer_url)
          validate_metadata(metadata, issuer_url)

          @metadata_cache[cache_key] = {
            metadata: metadata,
            cached_at: Time.now
          }

          metadata
        end
      end

      # Get authorization endpoint from metadata
      def authorization_endpoint(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['authorization_endpoint']
      end

      # Get token endpoint from metadata
      def token_endpoint(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['token_endpoint']
      end

      # Get JWKS URI from metadata
      def jwks_uri(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['jwks_uri']
      end

      # Get supported PKCE methods
      def supported_pkce_methods(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['code_challenge_methods_supported'] || ['plain', 'S256']
      end

      # Check if PKCE is required
      def pkce_required?(issuer_url)
        methods = supported_pkce_methods(issuer_url)
        # If only S256 is supported, PKCE is effectively required
        methods == ['S256'] || methods.include?('S256')
      end

      # Get supported scopes
      def supported_scopes(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['scopes_supported'] || []
      end

      # Get introspection endpoint
      def introspection_endpoint(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['introspection_endpoint']
      end

      # Get revocation endpoint
      def revocation_endpoint(issuer_url)
        metadata = discover_metadata(issuer_url)
        metadata['revocation_endpoint']
      end

      # Clear metadata cache
      def clear_cache(issuer_url = nil)
        @cache_mutex.synchronize do
          if issuer_url
            @metadata_cache.delete(issuer_url)
          else
            @metadata_cache.clear
          end
        end
      end

      private

      # Fetch metadata from well-known endpoints
      def fetch_metadata(issuer_url)
        base_uri = URI(issuer_url)
        base_uri.path = '' if base_uri.path == '/'

        WELL_KNOWN_PATHS.each do |path|
          discovery_uri = base_uri.dup
          discovery_uri.path = path

          begin
            @logger.debug("Trying discovery endpoint: #{discovery_uri}")
            response = fetch_with_timeout(discovery_uri)

            if response.is_a?(Net::HTTPSuccess)
              metadata = JSON.parse(response.body)
              @logger.debug("Successfully discovered metadata from: #{discovery_uri}")
              return metadata
            else
              @logger.debug("Discovery endpoint #{discovery_uri} returned #{response.code}")
            end
          rescue StandardError => e
            @logger.debug("Discovery attempt failed for #{discovery_uri}: #{e.message}")
          end
        end

        raise DiscoveryError, "Failed to discover metadata for issuer: #{issuer_url}"
      end

      # Fetch URL with timeout
      def fetch_with_timeout(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'
        request['User-Agent'] = "FastMCP/#{FastMcp::VERSION} OAuth Discovery"

        http.request(request)
      rescue StandardError => e
        raise DiscoveryError, "HTTP request failed: #{e.message}"
      end

      # Validate discovered metadata
      def validate_metadata(metadata, issuer_url)
        # Check required fields
        missing_fields = REQUIRED_METADATA.select { |field| metadata[field].nil? }
        unless missing_fields.empty?
          raise DiscoveryError, "Missing required metadata fields: #{missing_fields.join(', ')}"
        end

        # Validate issuer matches
        unless metadata['issuer'] == issuer_url
          raise DiscoveryError, "Issuer mismatch: expected #{issuer_url}, got #{metadata['issuer']}"
        end

        # Validate URLs are absolute
        url_fields = %w[authorization_endpoint token_endpoint jwks_uri]
        url_fields.each do |field|
          next unless metadata[field]

          begin
            uri = URI(metadata[field])
            raise DiscoveryError, "#{field} must be an absolute URL" unless uri.absolute?
          rescue URI::InvalidURIError
            raise DiscoveryError, "#{field} is not a valid URL"
          end
        end

        @logger.debug("Metadata validation successful for issuer: #{issuer_url}")
      end
    end
  end
end
