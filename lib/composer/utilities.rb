# frozen_string_literal: true

require 'faraday'
require 'json'

module Composer
  # Utility methods for HTTP requests, header construction, and response parsing.
  module Utilities
    # Fields that carry end-user information and are masked before anything is logged.
    # nextSteps is included because a blocked checkpoint returns integration config
    # (including provider client secrets) alongside the full client integration bundle.
    SENSITIVE_FIELDS = %w[ip data stepData step_data nextSteps next_steps].freeze
    REDACTED = '[REDACTED]'

    # Return a copy of a payload with end-user fields masked, so verbose logs show the
    # shape of a request or response without exposing PII
    def self.redact_sensitive_fields(payload)
      return payload.map { |entry| redact_sensitive_fields(entry) } if payload.is_a?(Array)
      return payload unless payload.is_a?(Hash)

      payload.to_h do |key, value|
        next [key, REDACTED] if SENSITIVE_FIELDS.include?(key.to_s)

        [key, redact_sensitive_fields(value)]
      end
    end

    # Check if a value is null or empty
    def self.null_or_empty?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end

    # Construct API URL
    def self.construct_api_url(base_url, api_version)
      base_url += '/' unless base_url.end_with?('/')
      "#{base_url}#{api_version}/"
    end

    # Construct API headers
    def self.construct_api_headers(secret_key, verification_id = nil, source_token = nil, customer_id = nil,
                                   session_id = nil)
      headers = {
        'Dodgeball-Secret-Key' => secret_key,
        'Composer-SDK-Version' => Composer::VERSION,
        'Composer-SDK-Source' => 'ruby-sdk',
        'Content-Type' => 'application/json'
      }

      headers['Dodgeball-Verification-Id'] = verification_id unless null_or_empty?(verification_id)
      headers['Dodgeball-Source-Token'] = source_token unless null_or_empty?(source_token)
      headers['Dodgeball-Customer-Id'] = customer_id unless null_or_empty?(customer_id)
      headers['Dodgeball-Session-Id'] = session_id unless null_or_empty?(session_id)

      headers
    end

    # Anything other than a positive integer would fail every request, so fall back to the default
    def self.resolve_request_timeout_ms(value)
      return value if value.is_a?(Integer) && value.positive?

      unless value.nil?
        Logger.error("config.request_timeout_ms must be a positive integer. Ignoring #{value.inspect} " \
                     "and using the #{DEFAULT_REQUEST_TIMEOUT_MS}ms default.").log
      end

      DEFAULT_REQUEST_TIMEOUT_MS
    end

    # Make HTTP request
    def self.make_request(url:, method:, headers:, body: nil, request_timeout_ms: DEFAULT_REQUEST_TIMEOUT_MS)
      # net-http strips, then raises ArgumentError with the header value, which can be the secret key.
      if headers.any? { |_name, value| value.to_s.strip.match?(/[\r\n]/) }
        Logger.error("A request header has a character that can't be sent, such as a newline.").log
        return { status: 500, body: request_failed_body, headers: {}, request_failed: true }
      end

      Logger.trace("Request body: #{redact_sensitive_fields(body).to_json}").log if body && Logger.trace?

      timeout_seconds = request_timeout_ms / 1000.0
      conn = Faraday.new do |f|
        f.request :json
        f.adapter Faraday.default_adapter
        f.options.timeout = timeout_seconds
        f.options.open_timeout = timeout_seconds
      end

      response = case method.to_s.upcase
                 when 'GET'
                   conn.get(url, nil, headers)
                 when 'POST'
                   conn.post(url) do |req|
                     req.headers = headers
                     req.body = body
                   end
                 else
                   raise ArgumentError, "Unsupported HTTP method: #{method}"
                 end

      # Ensure body is parsed as JSON if it's a string
      parsed_body = response.body.is_a?(String) ? JSON.parse(response.body) : response.body
      # A body that isn't a JSON object (such as `null` or an array) can't be read as a response
      raise JSON::ParserError, 'response body is not a JSON object' unless parsed_body.is_a?(Hash)

      {
        status: response.status,
        body: parsed_body,
        headers: response.headers
      }
    rescue Faraday::Error => e
      Logger.error('There was an error making a request.', e).log
      { status: 500, body: request_failed_body, headers: {}, request_failed: true }
    rescue JSON::ParserError => e
      Logger.error('The Composer API returned a response that is not valid JSON.', e).log
      {
        status: response&.status || 500,
        body: request_failed_body,
        headers: response&.headers || {}
      }
    end

    def self.request_failed_body
      { 'success' => false, 'errors' => [{ 'code' => 500, 'message' => 'Internal Server Error' }] }
    end

    # The Composer API returns stepData as an object map (e.g. {} or {"customMessage": "..."}).
    def self.parse_step_data(raw)
      return {} if raw.nil?
      return raw if raw.is_a?(Hash)

      {}
    end

    # Parse verification from response
    def self.parse_verification(data)
      return nil unless data['verification']

      v = data['verification']
      step_data = parse_step_data(v['stepData'])

      Verification.new(
        id: v['id'],
        status: v['status'],
        outcome: v['outcome'],
        step_data: step_data,
        next_steps: v['nextSteps'].is_a?(Array) ? v['nextSteps'] : []
      )
    end

    # Parse checkpoint response
    def self.parse_checkpoint_response(response_data)
      errors = (response_data['errors'] || []).map do |err|
        ApiError.new(
          code: err['code'],
          message: err['message']
        )
      end

      CheckpointResponse.new(
        success: response_data['success'] || false,
        errors: errors,
        version: response_data['version'] || ApiVersion::V1,
        verification: parse_verification(response_data),
        is_timeout: response_data['isTimeout'] || false
      )
    end

    # Sleep utility
    def self.sleep_ms(milliseconds)
      sleep(milliseconds / 1000.0)
    end
  end
end
