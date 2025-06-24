# frozen_string_literal: true

require 'json'
require 'net/http'
require 'securerandom'
require 'uri'

module FastMcp
  module OAuth
    # OAuth 2.1 Dynamic Client Registration
    # RFC 7591: https://tools.ietf.org/html/rfc7591
    class ClientRegistration
      class RegistrationError < StandardError; end

      # Standard client metadata fields
      CLIENT_METADATA_FIELDS = %w[
        redirect_uris
        token_endpoint_auth_method
        grant_types
        response_types
        client_name
        client_uri
        logo_uri
        scope
        contacts
        tos_uri
        policy_uri
        jwks_uri
        jwks
        software_id
        software_version
      ].freeze

      # Default values for client registration
      DEFAULT_GRANT_TYPES = ['authorization_code', 'refresh_token'].freeze
      DEFAULT_RESPONSE_TYPES = ['code'].freeze
      DEFAULT_TOKEN_AUTH_METHOD = 'client_secret_basic'

      attr_reader :logger, :registration_endpoint, :initial_access_token

      def initialize(options = {})
        @logger = options[:logger] || ::Logger.new($stdout).tap { |l| l.level = ::Logger::FATAL }
        @registration_endpoint = options[:registration_endpoint]
        @initial_access_token = options[:initial_access_token]
        @timeout = options.fetch(:timeout, 30)
        @user_agent = options[:user_agent] || "FastMCP/#{FastMcp::VERSION} OAuth Client Registration"

        raise ArgumentError, 'Registration endpoint is required' unless @registration_endpoint
      end

      # Register a new OAuth client
      def register_client(client_metadata = {})
        @logger.debug('Registering new OAuth client')

        # Validate and prepare client metadata
        metadata = prepare_client_metadata(client_metadata)

        # Send registration request
        response = send_registration_request(metadata)
        parse_registration_response(response)
      end

      # Read client registration information
      def read_client(client_id, registration_access_token)
        client_config_endpoint = build_client_config_endpoint(client_id)

        response = send_client_config_request(client_config_endpoint, registration_access_token, :get)
        parse_registration_response(response)
      end

      # Update client registration
      def update_client(client_id, registration_access_token, updated_metadata = {})
        client_config_endpoint = build_client_config_endpoint(client_id)
        metadata = prepare_client_metadata(updated_metadata)

        response = send_client_config_request(client_config_endpoint, registration_access_token, :put, metadata)
        parse_registration_response(response)
      end

      # Delete client registration
      def delete_client(client_id, registration_access_token)
        client_config_endpoint = build_client_config_endpoint(client_id)

        response = send_client_config_request(client_config_endpoint, registration_access_token, :delete)
        response.code == '204' # No Content indicates successful deletion
      end

      # Generate a secure client secret
      def self.generate_client_secret(length = 32)
        SecureRandom.urlsafe_base64(length)
      end

      # Validate redirect URIs
      def self.validate_redirect_uris(uris)
        Array(uris).each do |uri_string|
          uri = URI(uri_string)

          # Must be absolute URI
          raise ArgumentError, "Redirect URI must be absolute: #{uri_string}" unless uri.absolute?

          # Must use HTTPS (except for localhost during development)
          if uri.scheme != 'https' && !localhost_uri?(uri)
            raise ArgumentError, "Redirect URI must use HTTPS: #{uri_string}"
          end

          # Must not contain fragment
          raise ArgumentError, "Redirect URI must not contain fragment: #{uri_string}" if uri.fragment
        end

        true
      end

      # Check if URI is localhost
      def self.localhost_uri?(uri)
        %w[localhost 127.0.0.1].include?(uri.host) || uri.host&.start_with?('127.')
      end

      private

      # Prepare and validate client metadata
      def prepare_client_metadata(metadata)
        # Set defaults
        prepared = {
          'grant_types' => DEFAULT_GRANT_TYPES,
          'response_types' => DEFAULT_RESPONSE_TYPES,
          'token_endpoint_auth_method' => DEFAULT_TOKEN_AUTH_METHOD
        }.merge(metadata.stringify_keys)

        # Validate required fields
        validate_client_metadata(prepared)

        # Filter to only known fields
        prepared.slice(*CLIENT_METADATA_FIELDS)
      end

      # Validate client metadata
      def validate_client_metadata(metadata)
        # Validate redirect URIs if present
        self.class.validate_redirect_uris(metadata['redirect_uris']) if metadata['redirect_uris']

        # Validate grant types
        if metadata['grant_types']
          unknown_grants = metadata['grant_types'] - DEFAULT_GRANT_TYPES
          @logger.warn("Unknown grant types: #{unknown_grants}") unless unknown_grants.empty?
        end

        # Validate response types
        if metadata['response_types']
          unknown_responses = metadata['response_types'] - DEFAULT_RESPONSE_TYPES
          @logger.warn("Unknown response types: #{unknown_responses}") unless unknown_responses.empty?
        end

        true
      end

      # Send client registration request
      def send_registration_request(metadata)
        uri = URI(@registration_endpoint)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        request['User-Agent'] = @user_agent

        # Add initial access token if provided
        request['Authorization'] = "Bearer #{@initial_access_token}" if @initial_access_token

        request.body = JSON.generate(metadata)

        @logger.debug("Sending client registration request to #{@registration_endpoint}")

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise RegistrationError, "Client registration failed: #{response.code} #{response.message}"
        end

        response
      rescue StandardError => e
        raise RegistrationError, "Registration request error: #{e.message}"
      end

      # Send client configuration request (read/update/delete)
      def send_client_config_request(endpoint, access_token, method, body = nil)
        uri = URI(endpoint)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        request_class = case method
                        when :get then Net::HTTP::Get
                        when :put then Net::HTTP::Put
                        when :delete then Net::HTTP::Delete
                        else
                          raise ArgumentError, "Unsupported HTTP method: #{method}"
                        end

        request = request_class.new(uri)
        request['Authorization'] = "Bearer #{access_token}"
        request['User-Agent'] = @user_agent

        if body && [:put, :post].include?(method)
          request['Content-Type'] = 'application/json'
          request.body = JSON.generate(body)
        end

        request['Accept'] = 'application/json' if method != :delete

        @logger.debug("Sending #{method.upcase} request to #{endpoint}")

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise RegistrationError, "Client configuration request failed: #{response.code} #{response.message}"
        end

        response
      rescue StandardError => e
        raise RegistrationError, "Client configuration request error: #{e.message}"
      end

      # Parse registration response
      def parse_registration_response(response)
        begin
          result = JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise RegistrationError, "Invalid JSON response: #{e.message}"
        end

        # Validate required fields in response
        raise RegistrationError, 'Missing client_id in registration response' unless result['client_id']

        @logger.debug("Client registration successful: #{result['client_id']}")

        {
          client_id: result['client_id'],
          client_secret: result['client_secret'],
          registration_access_token: result['registration_access_token'],
          registration_client_uri: result['registration_client_uri'],
          client_id_issued_at: result['client_id_issued_at'],
          client_secret_expires_at: result['client_secret_expires_at'],
          metadata: result.except('client_id', 'client_secret', 'registration_access_token',
                                  'registration_client_uri', 'client_id_issued_at',
                                  'client_secret_expires_at')
        }
      end

      # Build client configuration endpoint URL
      def build_client_config_endpoint(client_id)
        # Standard pattern: registration_endpoint + '/' + client_id
        uri = URI(@registration_endpoint)
        uri.path = "#{uri.path.chomp('/')}/#{client_id}"
        uri.to_s
      end
    end
  end
end
