# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Composer::Logger do
  before do
    @original_filter_level = Composer::Logger.filter_level
    @output = StringIO.new
    $stdout = @output
  end

  after do
    Composer::Logger.filter_level = @original_filter_level
    $stdout = STDOUT
  end

  describe Composer::Severity do
    it 'has correct numeric values' do
      expect(Composer::Severity::TRACE).to eq(0)
      expect(Composer::Severity::INFO).to eq(1)
      expect(Composer::Severity::ERROR).to eq(2)
      expect(Composer::Severity::NONE).to eq(3)
    end

    it 'converts log level to severity' do
      expect(Composer::Severity.from_log_level(Composer::ComposerLogLevel::TRACE)).to eq(Composer::Severity::TRACE)
      expect(Composer::Severity.from_log_level(Composer::ComposerLogLevel::INFO)).to eq(Composer::Severity::INFO)
      expect(Composer::Severity.from_log_level(Composer::ComposerLogLevel::ERROR)).to eq(Composer::Severity::ERROR)
      expect(Composer::Severity.from_log_level(Composer::ComposerLogLevel::NONE)).to eq(Composer::Severity::NONE)
    end

    it 'defaults to INFO for unknown log level' do
      expect(Composer::Severity.from_log_level('UNKNOWN')).to eq(Composer::Severity::INFO)
    end

    it 'converts severity to string' do
      expect(Composer::Severity.to_string(Composer::Severity::TRACE)).to eq('TRACE')
      expect(Composer::Severity.to_string(Composer::Severity::INFO)).to eq('INFO')
      expect(Composer::Severity.to_string(Composer::Severity::ERROR)).to eq('ERROR')
      expect(Composer::Severity.to_string(Composer::Severity::NONE)).to eq('NONE')
    end

    it 'returns UNKNOWN for invalid severity' do
      expect(Composer::Severity.to_string(999)).to eq('UNKNOWN')
    end
  end

  describe Composer::LogEntry do
    it 'creates a log entry' do
      entry = Composer::LogEntry.new('Test message', Composer::Severity::INFO)
      expect(entry.message).to eq('Test message')
      expect(entry.severity).to eq(Composer::Severity::INFO)
      expect(entry.parameters).to eq({})
    end

    it 'supports method chaining' do
      entry = Composer::LogEntry.new('Test', Composer::Severity::INFO)
                                .set_parameter('key', 'value')
                                .set_severity(Composer::Severity::ERROR)

      expect(entry.parameters['key']).to eq('value')
      expect(entry.severity).to eq(Composer::Severity::ERROR)
    end

    it 'sets parameters' do
      entry = Composer::LogEntry.new('Test', Composer::Severity::INFO)
      entry.set_parameters({ key1: 'value1', key2: 'value2' })
      expect(entry.parameters[:key1]).to eq('value1')
      expect(entry.parameters[:key2]).to eq('value2')
    end

    it 'sets individual parameter' do
      entry = Composer::LogEntry.new('Test', Composer::Severity::INFO)
      entry.set_parameter('key', 'value')
      expect(entry.parameters['key']).to eq('value')
    end

    it 'sets error' do
      entry = Composer::LogEntry.new('Test', Composer::Severity::INFO)
      error = StandardError.new('Test error')
      entry.set_error(error)
      expect(entry.error).to eq(error)
    end
  end

  describe Composer::Logger do
    it 'creates info log entry' do
      entry = Composer::Logger.info('Info message')
      expect(entry.message).to eq('Info message')
      expect(entry.severity).to eq(Composer::Severity::INFO)
    end

    it 'creates trace log entry' do
      entry = Composer::Logger.trace('Trace message')
      expect(entry.message).to eq('Trace message')
      expect(entry.severity).to eq(Composer::Severity::TRACE)
    end

    it 'creates error log entry' do
      error = StandardError.new('Test error')
      entry = Composer::Logger.error('Error message', error)
      expect(entry.message).to eq('Error message')
      expect(entry.severity).to eq(Composer::Severity::ERROR)
      expect(entry.error).to eq(error)
    end

    it 'formats errors' do
      error = StandardError.new('Test error')
      formatted = Composer::Logger.format_error(error)
      expect(formatted).to include('Test error')
      expect(formatted).to include('StandardError')
    end

    it 'returns empty string for nil error' do
      expect(Composer::Logger.format_error(nil)).to eq('')
    end

    it 'filters logs based on severity' do
      Composer::Logger.filter_level = Composer::Severity::ERROR

      Composer::Logger.trace('Should not appear').log
      expect(@output.string).to be_empty

      Composer::Logger.info('Should not appear').log
      expect(@output.string).to be_empty

      Composer::Logger.error('Should appear').log
      expect(@output.string).to include('Should appear')
    end

    it 'logs at TRACE level' do
      Composer::Logger.filter_level = Composer::Severity::TRACE
      Composer::Logger.trace('Trace message').log
      expect(@output.string).to include('Trace message')
      expect(@output.string).to include('TRACE')
    end

    it 'suppresses all logs at NONE level' do
      Composer::Logger.filter_level = Composer::Severity::NONE
      Composer::Logger.trace('Trace').log
      Composer::Logger.info('Info').log
      Composer::Logger.error('Error').log
      expect(@output.string).to be_empty
    end
  end
end
