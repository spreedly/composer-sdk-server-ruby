# frozen_string_literal: true

require 'json'
require 'time'

module Composer
  # Log levels for Composer SDK
  module ComposerLogLevel
    TRACE = 'TRACE'
    INFO = 'INFO'
    ERROR = 'ERROR'
    NONE = 'NONE'
  end

  # Backward compatibility alias
  DodgeballLogLevel = ComposerLogLevel

  # Logger severity enum
  module Severity
    TRACE = 0
    INFO = 1
    ERROR = 2
    NONE = 3

    def self.from_log_level(level)
      case level
      when ComposerLogLevel::TRACE then TRACE
      when ComposerLogLevel::INFO then INFO
      when ComposerLogLevel::ERROR then ERROR
      when ComposerLogLevel::NONE then NONE
      else INFO # rubocop:disable Lint/DuplicateBranch
      end
    end

    def self.to_string(severity)
      case severity
      when TRACE then 'TRACE'
      when INFO then 'INFO'
      when ERROR then 'ERROR'
      when NONE then 'NONE'
      else 'UNKNOWN'
      end
    end
  end

  # Log entry class for structured logging
  class LogEntry
    attr_accessor :message, :severity, :error, :date
    attr_reader :parameters

    def initialize(message, severity, error = nil)
      @message = message
      @severity = severity
      @error = error
      @parameters = {}
      @date = Time.now
    end

    def parameters=(params)
      @parameters = params || {}
    end

    # rubocop:disable Naming/AccessorMethodName
    def set_parameters(params)
      self.parameters = params
      self
    end
    # rubocop:enable Naming/AccessorMethodName

    def set_parameter(key, value)
      @parameters[key] = value
      self
    end

    # rubocop:disable Naming/AccessorMethodName
    def set_severity(sev)
      @severity = sev
      self
    end

    def set_error(err)
      @error = err
      self
    end
    # rubocop:enable Naming/AccessorMethodName

    def log
      Logger.log(self)
    end
  end

  # Main logger class
  class Logger
    @filter_level = Severity::INFO

    class << self
      attr_accessor :filter_level

      # Callers check this before assembling an expensive trace message, because the
      # message is built before log gets a chance to discard it
      def trace?
        @filter_level <= Severity::TRACE
      end

      def info(message, parameters = nil)
        entry = LogEntry.new(message, Severity::INFO)
        entry.set_parameters(parameters) if parameters
        entry
      end

      def trace(message, parameters = nil)
        entry = LogEntry.new(message, Severity::TRACE)
        entry.set_parameters(parameters) if parameters
        entry
      end

      def error(message, error = nil)
        LogEntry.new(message, Severity::ERROR, error)
      end

      def format_error(error)
        return '' unless error

        result = {
          message: error.message,
          name: error.class.name
        }

        result[:stack] = error.backtrace.join("\n") if error.backtrace

        result.to_json
      end

      def log(log_entry)
        return if log_entry.severity < @filter_level

        output = {
          severity: Severity.to_string(log_entry.severity),
          date: log_entry.date.utc.iso8601(6),
          message: log_entry.message
        }

        output[:parameters] = log_entry.parameters unless log_entry.parameters.empty?
        output[:error] = format_error(log_entry.error) if log_entry.error

        puts output.to_json
      end
    end
  end
end
