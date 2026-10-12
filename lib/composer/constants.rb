# frozen_string_literal: true

module Composer
  # API version constants
  module ApiVersion
    V1 = 'v1'
  end

  # Verification status constants
  module VerificationStatus
    PENDING = 'PENDING'
    BLOCKED = 'BLOCKED'
    COMPLETE = 'COMPLETE'
    FAILED = 'FAILED'
  end

  # Verification outcome constants
  module VerificationOutcome
    APPROVED = 'APPROVED'
    DENIED = 'DENIED'
    PENDING = 'PENDING'
    ERROR = 'ERROR'
    USAGE_LIMIT = 'USAGE_LIMIT'
    API_LIMIT = 'API_LIMIT'
  end

  DEFAULT_REQUEST_TIMEOUT_MS = 30 * 1000 # 30 seconds

  # Default configuration
  DEFAULT_CONFIG = {
    api_version: ApiVersion::V1,
    api_url: 'https://api.dodgeballhq.com/',
    log_level: ComposerLogLevel::INFO,
    enabled: true,
    request_timeout_ms: DEFAULT_REQUEST_TIMEOUT_MS
  }.freeze

  # Polling constants
  BASE_CHECKPOINT_POLLING_WAIT_MS = 100
  MAX_POLLING_WAIT_MS = 2000
  BASE_CHECKPOINT_MAX_TIMEOUT_MS = 10 * 60 * 1000 # 10 minutes in ms
  MAX_FAILURE_COUNT = 3
end
