# frozen_string_literal: true

module Composer
  # Custom error classes
  class ComposerError < StandardError; end
  class MissingParameterError < ComposerError; end
  class MissingConfigError < ComposerError; end
  class InvalidConfigError < ComposerError; end

  # Checkpoint event structure
  class CheckpointEvent
    attr_accessor :ip, :data

    def initialize(ip: nil, data: {})
      @ip = ip
      @data = data
    end

    def to_h
      {
        ip: @ip,
        data: @data
      }
    end
  end

  # Track event structure
  class TrackEvent
    attr_accessor :type, :data, :event_time

    def initialize(type:, data: {}, event_time: nil)
      @type = type
      @data = data
      @event_time = event_time
    end

    def to_h
      result = {
        type: @type,
        data: @data
      }
      result[:eventTime] = @event_time if @event_time
      result
    end
  end

  # Verification step data
  class VerificationStepData
    attr_accessor :id, :name, :data

    def initialize(id:, name:, data: {})
      @id = id
      @name = name
      @data = data
    end
  end

  # Verification object
  class Verification
    attr_accessor :id, :status, :outcome, :step_data, :next_steps

    def initialize(id:, status:, outcome:, step_data: {}, next_steps: [])
      @id = id
      @status = status
      @outcome = outcome
      @step_data = step_data
      @next_steps = next_steps
    end
  end

  # API error structure
  class ApiError
    attr_accessor :code, :message

    def initialize(message:, code: nil)
      @code = code
      @message = message
    end
  end

  # Checkpoint response
  class CheckpointResponse
    attr_accessor :success, :errors, :version, :verification, :is_timeout

    def initialize(success:, errors: [], version: ApiVersion::V1, verification: nil, is_timeout: false)
      @success = success
      @errors = errors
      @version = version
      @verification = verification
      @is_timeout = is_timeout
    end

    # Helper methods for checking response status
    def allowed?
      @success && @verification&.status == VerificationStatus::COMPLETE &&
        @verification&.outcome == VerificationOutcome::APPROVED
    end

    def denied?
      @success && @verification&.outcome == VerificationOutcome::DENIED
    end

    def running?
      @success && @verification &&
        [VerificationStatus::PENDING, VerificationStatus::BLOCKED].include?(@verification.status) &&
        @verification.outcome == VerificationOutcome::PENDING
    end

    def undecided?
      @success && @verification&.status == VerificationStatus::COMPLETE &&
        @verification&.outcome == VerificationOutcome::PENDING
    end

    def error?
      !@success || @verification&.outcome == VerificationOutcome::ERROR
    end

    # rubocop:disable Naming/PredicatePrefix
    def has_error?
      error?
    end
    # rubocop:enable Naming/PredicatePrefix

    def timeout?
      @is_timeout
    end
  end
end
