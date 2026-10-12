# frozen_string_literal: true

module Composer
  # Logs that a tracking event was not sent because a required field was missing.
  module UnsentEvent
    def self.log(reason)
      Logger.error("Composer event was not sent: #{reason}").log
    end
  end

  # Main Composer SDK class
  class ComposerClient
    attr_reader :secret_key, :config

    def initialize(secret_key, config = {})
      # Validate secret key
      raise MissingConfigError, 'Secret API key is required' if Utilities.null_or_empty?(secret_key)

      @secret_key = secret_key

      # Merge with default config
      @config = DEFAULT_CONFIG.merge(config)

      # Validate API version
      unless [ApiVersion::V1].include?(@config[:api_version])
        raise InvalidConfigError, "Invalid API version: #{@config[:api_version]}"
      end

      # Validate log level
      log_level = @config[:log_level] || ComposerLogLevel::INFO
      unless [ComposerLogLevel::TRACE, ComposerLogLevel::INFO, ComposerLogLevel::ERROR, ComposerLogLevel::NONE].include?(log_level)
        raise InvalidConfigError, "Invalid log level: #{log_level}"
      end

      # Set logger filter level
      Logger.filter_level = Severity.from_log_level(log_level)

      # Resolved after the logger is configured so any warning respects log_level.
      @config[:request_timeout_ms] = Utilities.resolve_request_timeout_ms(@config[:request_timeout_ms])
    end

    # Send tracking event
    def event(event:, session_id: nil, user_id: nil, source_token: nil)
      return UnsentEvent.log('no event was provided') if Utilities.null_or_empty?(event)
      return UnsentEvent.log('event.type is missing') if Utilities.null_or_empty?(event.type) || event.type.to_s.strip.empty?
      if session_id.to_s.strip.empty? && source_token.to_s.strip.empty?
        return UnsentEvent.log('Must provide either a sessionId or sourceToken')
      end

      # Only an explicit false disables the SDK. nil must not overwrite the default.
      return nil if @config[:enabled] == false

      # Ensure event has a timestamp
      event.event_time ||= (Time.now.to_f * 1000).to_i

      # Send event to API
      url = "#{Utilities.construct_api_url(@config[:api_url], @config[:api_version])}track"
      headers = Utilities.construct_api_headers(@secret_key, nil, source_token, user_id, session_id)

      response = Utilities.make_request(
        url: url,
        method: :post,
        headers: headers,
        body: event.to_h,
        request_timeout_ms: @config[:request_timeout_ms]
      )
      # make_request already logged a request that never got a response.
      if !response[:request_failed] && !(200..299).cover?(response[:status])
        Logger.error("Composer event was not accepted by the API (HTTP #{response[:status]}).").log
      end

      nil
    end

    # Alias methods for backward compatibility
    alias notify event
    alias track event

    # Submit checkpoint
    def checkpoint(checkpoint_name:, event:, session_id: nil, user_id: nil, source_token: nil,
                   use_verification_id: nil, options: {})
      # Validate required parameters
      raise MissingParameterError, 'checkpoint_name is required' if checkpoint_name.to_s.strip.empty?
      raise MissingParameterError, 'event is required' if Utilities.null_or_empty?(event)

      if session_id.to_s.strip.empty? && source_token.to_s.strip.empty?
        raise MissingParameterError, 'Either session_id or source_token is required'
      end

      # Only an explicit false disables the SDK. nil must not overwrite the default.
      if @config[:enabled] == false
        return CheckpointResponse.new(
          success: true,
          errors: [],
          version: ApiVersion::V1,
          verification: Verification.new(
            id: 'COMPOSER_IS_DISABLED',
            status: VerificationStatus::COMPLETE,
            outcome: VerificationOutcome::APPROVED,
            step_data: {}
          ),
          is_timeout: false
        )
      end

      # Setup timing and polling parameters
      checkpoint_timeout = options[:timeout]&.positive? ? options[:timeout] : BASE_CHECKPOINT_MAX_TIMEOUT_MS
      current_polling_wait = BASE_CHECKPOINT_POLLING_WAIT_MS
      has_never_polled = true
      num_failures = 0
      checkpoint_start_time = Time.now

      # Prepare request options
      request_options = { sync: options[:sync] || false }

      # Submit checkpoint to API
      url = "#{Utilities.construct_api_url(@config[:api_url], @config[:api_version])}checkpoint"
      headers = Utilities.construct_api_headers(@secret_key, use_verification_id, source_token, user_id, session_id)

      event_body = { type: checkpoint_name, data: event.data }
      event_body[:ip] = event.ip unless Utilities.null_or_empty?(event.ip)
      body = { event: event_body, options: request_options }

      http_response = Utilities.make_request(url: url, method: :post, headers: headers, body: body,
                                             request_timeout_ms: @config[:request_timeout_ms])
      response_body = http_response[:body]
      response = Utilities.parse_checkpoint_response(response_body)

      # Handle error or unsuccessful response
      return response unless response.success

      # Log initial response
      if Logger.trace?
        Logger.trace("Initial checkpoint response: #{Utilities.redact_sensitive_fields(response_body).to_json}").log
      end

      # Only poll PENDING; BLOCKED waits on a client action such as MFA.
      is_resolved = response.verification&.status != VerificationStatus::PENDING
      verification_id = response.verification&.id

      # Poll for verification result if needed
      while !is_resolved &&
            ((Time.now - checkpoint_start_time) * 1000 < checkpoint_timeout || has_never_polled) &&
            num_failures < MAX_FAILURE_COUNT

        Utilities.sleep_ms(current_polling_wait)
        current_polling_wait = [current_polling_wait * 2, MAX_POLLING_WAIT_MS].min
        has_never_polled = false

        # Poll verification endpoint
        poll_url = "#{Utilities.construct_api_url(@config[:api_url],
                                                  @config[:api_version])}verification/#{verification_id}"
        poll_response = Utilities.make_request(url: poll_url, method: :get, headers: headers,
                                               request_timeout_ms: @config[:request_timeout_ms])
        response_body = poll_response[:body]
        response = Utilities.parse_checkpoint_response(response_body)

        if response.success && response.verification
          status = response.verification.status
          if status.nil?
            num_failures += 1
          else
            is_resolved = status != VerificationStatus::PENDING
            num_failures = 0 # Reset on successful response
          end
        else
          num_failures += 1
        end
      end

      # Handle max failures
      if num_failures >= MAX_FAILURE_COUNT
        Logger.error('Service Unavailable: Maximum retry count exceeded').log
        return CheckpointResponse.new(
          success: false,
          errors: [ApiError.new(code: 503, message: 'Service Unavailable: Maximum retry count exceeded')],
          version: ApiVersion::V1,
          is_timeout: true
        )
      end

      # Log final response
      Logger.trace("Returning response: #{Utilities.redact_sensitive_fields(response_body).to_json}").log if Logger.trace?

      response
    end

    # Helper methods (can be used as instance or class methods)
    def self.allowed?(response)
      response.allowed?
    end

    def self.denied?(response)
      response.denied?
    end

    def self.running?(response)
      response.running?
    end

    def self.undecided?(response)
      response.undecided?
    end

    def self.error?(response)
      response.error?
    end

    # rubocop:disable Naming/PredicatePrefix
    def self.has_error?(response)
      error?(response)
    end
    # rubocop:enable Naming/PredicatePrefix

    def self.timeout?(response)
      response.timeout?
    end

    # Instance method versions
    def allowed?(response)
      self.class.allowed?(response)
    end

    def denied?(response)
      self.class.denied?(response)
    end

    def running?(response)
      self.class.running?(response)
    end

    def undecided?(response)
      self.class.undecided?(response)
    end

    def error?(response)
      self.class.error?(response)
    end

    # rubocop:disable Naming/PredicatePrefix
    def has_error?(response)
      error?(response)
    end
    # rubocop:enable Naming/PredicatePrefix

    def timeout?(response)
      self.class.timeout?(response)
    end
  end
end
