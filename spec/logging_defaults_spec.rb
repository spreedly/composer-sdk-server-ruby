# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# Regression coverage for the safe logging default: an integrator who passes no
# log level must never see request bodies, response bodies or event IPs in their logs.
RSpec.describe 'default logging' do
  let(:api_url) { 'https://api.test.com/' }
  let(:event_ip) { '203.0.113.7' }
  let(:event_email) { 'shopper@example.com' }

  before do
    stub_request(:post, "#{api_url}v1/checkpoint")
      .to_return(
        status: 200,
        body: {
          success: true,
          version: 'v1',
          verification: {
            id: 'ver-123',
            status: 'COMPLETE',
            outcome: 'APPROVED',
            stepData: { email: event_email }
          }
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  # Runs a checkpoint against a stubbed API and returns everything the SDK logged.
  def run_checkpoint(log_level = nil)
    config = { api_url: api_url }
    config[:log_level] = log_level if log_level
    client = Composer::ComposerClient.new('test-secret-key', config)

    captured = StringIO.new
    original_stdout = $stdout
    $stdout = captured
    begin
      client.checkpoint(
        checkpoint_name: 'CHECKOUT',
        event: Composer::CheckpointEvent.new(ip: event_ip, data: { email: event_email }),
        session_id: 'session-123'
      )
    ensure
      $stdout = original_stdout
    end

    captured.string
  end

  it 'defaults to the INFO log level' do
    expect(Composer::DEFAULT_CONFIG[:log_level]).to eq(Composer::ComposerLogLevel::INFO)
  end

  it 'emits nothing for a checkpoint when no log level is configured' do
    output = run_checkpoint

    expect(Composer::Logger.filter_level).to eq(Composer::Severity::INFO)
    expect(output).to eq('')
  end

  it 'logs redacted request and response payloads when TRACE is opted into' do
    output = run_checkpoint(Composer::ComposerLogLevel::TRACE)

    expect(output).to include('Request body: ')
    expect(output).to include('COMPLETE')
    expect(output).to include('[REDACTED]')
    expect(output).not_to include(event_ip)
    expect(output).not_to include(event_email)
  end

  it 'masks end-user fields anywhere in a payload' do
    redacted = Composer::Utilities.redact_sensitive_fields(
      'event' => { 'type' => 'CHECKOUT', 'ip' => event_ip, 'data' => { 'email' => event_email } },
      'verification' => { 'id' => 'ver-123', 'stepData' => { 'email' => event_email } }
    )

    expect(redacted['event']['type']).to eq('CHECKOUT')
    expect(redacted['event']['ip']).to eq('[REDACTED]')
    expect(redacted['event']['data']).to eq('[REDACTED]')
    expect(redacted['verification']['id']).to eq('ver-123')
    expect(redacted['verification']['stepData']).to eq('[REDACTED]')
  end

  it 'masks the nextSteps a blocked checkpoint returns' do
    redacted = Composer::Utilities.redact_sensitive_fields(
      'verification' => {
        'id' => 'ver-123',
        'status' => 'BLOCKED',
        'nextSteps' => [
          { 'name' => 'STRIPE_IDENTITY',
            'config' => { 'clientSecret' => 'vs_secret_value' },
            'content' => { 'text' => 'console.log("bundle");' } }
        ]
      }
    )

    expect(redacted['verification']['status']).to eq('BLOCKED')
    expect(redacted['verification']['nextSteps']).to eq('[REDACTED]')
    expect(redacted.to_json).not_to include('vs_secret_value')
  end

  it 'reports trace as disabled at the default level' do
    Composer::Logger.filter_level = Composer::Severity::INFO
    expect(Composer::Logger.trace?).to be(false)

    Composer::Logger.filter_level = Composer::Severity::TRACE
    expect(Composer::Logger.trace?).to be(true)
  end
end
