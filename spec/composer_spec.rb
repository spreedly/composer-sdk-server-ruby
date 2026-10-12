# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Composer::ComposerClient do
  let(:secret_key) { 'test-secret-key' }
  let(:api_url) { 'https://api.test.com/' }

  describe '#initialize' do
    it 'creates a client with valid secret key' do
      client = Composer::ComposerClient.new(secret_key)
      expect(client.secret_key).to eq(secret_key)
    end

    it 'raises error without secret key' do
      expect do
        Composer::ComposerClient.new(nil)
      end.to raise_error(Composer::MissingConfigError)
    end

    it 'merges custom config with defaults' do
      client = Composer::ComposerClient.new(secret_key, {
                                              api_url: api_url,
                                              log_level: Composer::ComposerLogLevel::ERROR
                                            })
      expect(client.config[:api_url]).to eq(api_url)
      expect(client.config[:log_level]).to eq(Composer::ComposerLogLevel::ERROR)
    end

    it 'validates API version' do
      expect do
        Composer::ComposerClient.new(secret_key, { api_version: 'invalid' })
      end.to raise_error(Composer::InvalidConfigError)
    end

    it 'validates log level' do
      expect do
        Composer::ComposerClient.new(secret_key, { log_level: 'INVALID' })
      end.to raise_error(Composer::InvalidConfigError)
    end

    it 'sets logger filter level' do
      Composer::ComposerClient.new(secret_key, { log_level: Composer::ComposerLogLevel::ERROR })
      expect(Composer::Logger.filter_level).to eq(Composer::Severity::ERROR)
    end

    it 'defaults request_timeout_ms to 30000' do
      client = Composer::ComposerClient.new(secret_key, { log_level: Composer::ComposerLogLevel::NONE })
      expect(client.config[:request_timeout_ms]).to eq(30_000)
    end

    it 'accepts a custom request_timeout_ms' do
      client = Composer::ComposerClient.new(secret_key,
                                            { request_timeout_ms: 5000, log_level: Composer::ComposerLogLevel::NONE })
      expect(client.config[:request_timeout_ms]).to eq(5000)
    end

    [0, -1, 1.5, 'abc'].each do |invalid|
      it "logs an error and falls back to the default for request_timeout_ms #{invalid.inspect}" do
        client = nil
        expect do
          client = Composer::ComposerClient.new(secret_key,
                                                { request_timeout_ms: invalid, log_level: Composer::ComposerLogLevel::ERROR })
        end.to output(/config.request_timeout_ms must be a positive integer/).to_stdout
        expect(client.config[:request_timeout_ms]).to eq(30_000)
      end
    end
  end

  describe '#checkpoint' do
    let(:client) { Composer::ComposerClient.new(secret_key, { api_url: api_url, log_level: Composer::ComposerLogLevel::NONE }) }
    let(:event) { Composer::CheckpointEvent.new(ip: '127.0.0.1', data: { test: 'data' }) }

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
              stepData: []
            }
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
    end

    it 'calls checkpoint with valid parameters' do
      response = client.checkpoint(
        checkpoint_name: 'TEST_CHECKPOINT',
        event: event,
        session_id: 'session-123'
      )

      expect(response).to be_a(Composer::CheckpointResponse)
      expect(response.success).to be true
      expect(response.verification.id).to eq('ver-123')
      expect(response.verification.status).to eq('COMPLETE')
      expect(response.verification.outcome).to eq('APPROVED')
    end

    it 'requires checkpoint_name' do
      expect do
        client.checkpoint(checkpoint_name: nil, event: event, session_id: 'session-123')
      end.to raise_error(Composer::MissingParameterError)
    end

    it 'requires a non-blank checkpoint_name' do
      expect do
        client.checkpoint(checkpoint_name: '   ', event: event, session_id: 'session-123')
      end.to raise_error(Composer::MissingParameterError)
    end

    it 'requires event' do
      expect do
        client.checkpoint(checkpoint_name: 'TEST', event: nil, session_id: 'session-123')
      end.to raise_error(Composer::MissingParameterError)
    end

    [nil, ''].each do |ip|
      it "leaves event.ip out of the request when it's #{ip.inspect}, since the API treats it as optional" do
        response = client.checkpoint(checkpoint_name: 'TEST', event: Composer::CheckpointEvent.new(ip: ip),
                                     session_id: 'session-123')

        expect(response.verification.id).to eq('ver-123')
        expect(WebMock).to(have_requested(:post, "#{api_url}v1/checkpoint")
          .with { |request| JSON.parse(request.body)['event'] == { 'type' => 'TEST', 'data' => {} } })
      end
    end

    it 'returns a failure instead of raising when the API body is the JSON null' do
      stub_request(:post, "#{api_url}v1/checkpoint").to_return(status: 200, body: 'null')

      response = client.checkpoint(checkpoint_name: 'TEST', event: event, session_id: 'session-123')

      expect(response.success).to be false
      expect(response.errors.first.code).to eq(500)
    end

    it 'returns a failure instead of raising when a header value contains a newline' do
      leaky = Composer::ComposerClient.new("sk_test_FAKE\n123",
                                           { api_url: api_url, log_level: Composer::ComposerLogLevel::NONE })

      response = leaky.checkpoint(checkpoint_name: 'TEST', event: event, session_id: 'session-123')

      expect(response.success).to be false
      expect(response.errors.first.code).to eq(500)
    end

    it 'requires either session_id or source_token' do
      expect do
        client.checkpoint(checkpoint_name: 'TEST', event: event)
      end.to raise_error(Composer::MissingParameterError)
    end

    it 'returns approved response when SDK is disabled' do
      disabled_client = Composer::ComposerClient.new(secret_key,
                                                     { enabled: false, log_level: Composer::ComposerLogLevel::NONE })
      response = disabled_client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.success).to be true
      expect(response.verification.id).to eq('COMPOSER_IS_DISABLED')
      expect(response.verification.outcome).to eq(Composer::VerificationOutcome::APPROVED)
    end

    it 'stays enabled when enabled is nil' do
      client = Composer::ComposerClient.new(secret_key,
                                            { api_url: api_url, enabled: nil, log_level: Composer::ComposerLogLevel::NONE })
      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.verification.id).to eq('ver-123')
      expect(WebMock).to have_requested(:post, "#{api_url}v1/checkpoint")
    end

    it 'handles denied response' do
      stub_request(:post, "#{api_url}v1/checkpoint")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-456',
              status: 'COMPLETE',
              outcome: 'DENIED',
              stepData: []
            }
          }.to_json
        )

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.verification.outcome).to eq('DENIED')
      expect(response.denied?).to be true
    end

    it 'polls for pending verification' do
      stub_request(:post, "#{api_url}v1/checkpoint")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-pending',
              status: 'PENDING',
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )

      stub_request(:get, "#{api_url}v1/verification/ver-pending")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-pending',
              status: 'COMPLETE',
              outcome: 'APPROVED',
              stepData: []
            }
          }.to_json
        )

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.verification.status).to eq('COMPLETE')
      expect(response.verification.outcome).to eq('APPROVED')
    end

    it 'handles max failures during polling' do
      stub_request(:post, "#{api_url}v1/checkpoint")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-fail',
              status: 'PENDING',
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )

      stub_request(:get, "#{api_url}v1/verification/ver-fail")
        .to_return(status: 500, body: 'Server error')
        .times(3)

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.success).to be false
      expect(response.errors.first.code).to eq(503)
      expect(response.errors.first.message).to include('Maximum retry count exceeded')
    end

    it 'returns immediately on blocked status without polling' do
      checkpoint_stub = stub_request(:post, "#{api_url}v1/checkpoint")
                        .to_return(
                          status: 200,
                          body: {
                            success: true,
                            version: 'v1',
                            verification: {
                              id: 'ver-blocked',
                              status: 'BLOCKED',
                              outcome: 'PENDING',
                              stepData: []
                            }
                          }.to_json
                        )

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.verification.status).to eq('BLOCKED')
      assert_requested(checkpoint_stub, times: 1)
      assert_not_requested(:get, "#{api_url}v1/verification/ver-blocked")
    end

    it 'returns the still-pending response without is_timeout when the polling budget expires' do
      stub_request(:post, "#{api_url}v1/checkpoint")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-timeout',
              status: 'PENDING',
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )

      stub_request(:get, "#{api_url}v1/verification/ver-timeout")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-timeout',
              status: 'PENDING',
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123',
        options: { timeout: 500 }
      )

      expect(response.success).to be true
      expect(response.is_timeout).to be false
      expect(client.running?(response)).to be true
    end

    it 'handles nil status during polling' do
      stub_request(:post, "#{api_url}v1/checkpoint")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-nil',
              status: 'PENDING',
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )

      stub_request(:get, "#{api_url}v1/verification/ver-nil")
        .to_return(
          status: 200,
          body: {
            success: true,
            version: 'v1',
            verification: {
              id: 'ver-nil',
              status: nil,
              outcome: 'PENDING',
              stepData: []
            }
          }.to_json
        )
        .times(3)

      response = client.checkpoint(
        checkpoint_name: 'TEST',
        event: event,
        session_id: 'session-123'
      )

      expect(response.success).to be false
      expect(response.errors.first.message).to include('Maximum retry count exceeded')
    end
  end

  describe '#event' do
    let(:client) { Composer::ComposerClient.new(secret_key, { api_url: api_url, log_level: Composer::ComposerLogLevel::NONE }) }
    let(:event) { Composer::TrackEvent.new(type: 'TEST_EVENT', data: { test: 'data' }) }

    before do
      stub_request(:post, "#{api_url}v1/track")
        .to_return(status: 200, body: { success: true }.to_json)
    end

    it 'sends tracking event' do
      client.event(event: event, session_id: 'session-123')
      expect(WebMock).to have_requested(:post, "#{api_url}v1/track")
    end

    context 'when logging at the default level' do
      let(:client) { Composer::ComposerClient.new(secret_key, { api_url: api_url }) }

      it 'logs the status when the API does not accept the event' do
        stub_request(:post, "#{api_url}v1/track")
          .to_return(status: 400, body: { success: false, errors: [] }.to_json)

        expect do
          client.event(event: event, session_id: 'session-123')
        end.to output(/Composer event was not accepted by the API \(HTTP 400\)\./).to_stdout
      end

      it 'logs nothing when the API accepts the event' do
        expect do
          client.event(event: event, session_id: 'session-123')
        end.not_to output.to_stdout
      end

      it 'does not report a network failure as an API rejection' do
        stub_request(:post, "#{api_url}v1/track").to_timeout

        expect do
          client.event(event: event, session_id: 'session-123')
        end.to output(satisfy { |logged|
          logged.scan('There was an error making a request.').length == 1 &&
            !logged.include?('not accepted by the API')
        }).to_stdout
      end

      it 'does not raise or leak a secret key that contains a newline' do
        leaky = Composer::ComposerClient.new("sk_test_FAKE\n123", { api_url: api_url })

        expect do
          leaky.event(event: event, session_id: 'session-123')
        end.to output(satisfy { |logged|
          logged.include?("A request header has a character that can't be sent, such as a newline.") &&
            !logged.include?('sk_test_FAKE')
        }).to_stdout
      end
    end

    it 'requires event' do
      client.event(event: nil, session_id: 'session-123')
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'requires event.type without sending the event' do
      event_no_type = Composer::TrackEvent.new(type: nil, data: {})
      client.event(event: event_no_type, session_id: 'session-123')
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'requires a non-empty event.type' do
      event_empty_type = Composer::TrackEvent.new(type: '', data: {})
      client.event(event: event_empty_type, session_id: 'session-123')
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'requires a non-blank event.type' do
      event_blank_type = Composer::TrackEvent.new(type: '   ', data: {})
      client.event(event: event_blank_type, session_id: 'session-123')
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'rejects an empty collection as event.type' do
      [[], {}].each do |empty_type|
        client.event(event: Composer::TrackEvent.new(type: empty_type, data: {}), session_id: 'session-123')
      end
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'requires a session_id or source_token without sending the event' do
      client.event(event: event)
      expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
    end

    it 'sets event_time if not provided' do
      event_without_time = Composer::TrackEvent.new(type: 'TEST', data: {})
      expect(event_without_time.event_time).to be_nil

      client.event(event: event_without_time, session_id: 'session-123')
      expect(event_without_time.event_time).not_to be_nil
    end

    it 'supports notify alias' do
      client.notify(event: event, session_id: 'session-123')
      expect(WebMock).to have_requested(:post, "#{api_url}v1/track")
    end

    it 'supports track alias' do
      client.track(event: event, session_id: 'session-123')
      expect(WebMock).to have_requested(:post, "#{api_url}v1/track")
    end

    it 'applies the configured request_timeout_ms' do
      client = Composer::ComposerClient.new(secret_key, { api_url: api_url, request_timeout_ms: 5000,
                                                          log_level: Composer::ComposerLogLevel::NONE })
      expect(Composer::Utilities).to receive(:make_request)
        .with(hash_including(request_timeout_ms: 5000)).and_call_original

      client.event(event: event, session_id: 'session-123')
    end

    context 'when SDK is disabled' do
      let(:disabled_client) do
        Composer::ComposerClient.new(secret_key,
                                     { api_url: api_url, enabled: false, log_level: Composer::ComposerLogLevel::NONE })
      end

      it 'does not send the event' do
        disabled_client.event(event: event, session_id: 'session-123')
        expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
      end

      it 'still requires event' do
        disabled_client.event(event: nil, session_id: 'session-123')
        expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
      end

      it 'still requires event.type' do
        disabled_client.event(event: Composer::TrackEvent.new(type: nil), session_id: 'session-123')
        expect(WebMock).not_to have_requested(:post, "#{api_url}v1/track")
      end
    end

    it 'sends the event when enabled is nil' do
      client = Composer::ComposerClient.new(secret_key,
                                            { api_url: api_url, enabled: nil, log_level: Composer::ComposerLogLevel::NONE })
      client.event(event: event, session_id: 'session-123')
      expect(WebMock).to have_requested(:post, "#{api_url}v1/track")
    end
  end

  describe 'helper methods' do
    let(:client) { Composer::ComposerClient.new(secret_key, { log_level: Composer::ComposerLogLevel::NONE }) }

    let(:approved_response) do
      Composer::CheckpointResponse.new(
        success: true,
        verification: Composer::Verification.new(
          id: 'ver-1',
          status: Composer::VerificationStatus::COMPLETE,
          outcome: Composer::VerificationOutcome::APPROVED
        )
      )
    end

    let(:denied_response) do
      Composer::CheckpointResponse.new(
        success: true,
        verification: Composer::Verification.new(
          id: 'ver-2',
          status: Composer::VerificationStatus::COMPLETE,
          outcome: Composer::VerificationOutcome::DENIED
        )
      )
    end

    let(:pending_response) do
      Composer::CheckpointResponse.new(
        success: true,
        verification: Composer::Verification.new(
          id: 'ver-3',
          status: Composer::VerificationStatus::PENDING,
          outcome: Composer::VerificationOutcome::PENDING
        )
      )
    end

    let(:error_response) do
      Composer::CheckpointResponse.new(
        success: false,
        errors: [Composer::ApiError.new(code: 500, message: 'Error')]
      )
    end

    it 'identifies allowed responses' do
      expect(client.allowed?(approved_response)).to be true
      expect(client.allowed?(denied_response)).to be false
      expect(Composer::ComposerClient.allowed?(approved_response)).to be true
    end

    it 'identifies denied responses' do
      expect(client.denied?(denied_response)).to be true
      expect(client.denied?(approved_response)).to be false
      expect(Composer::ComposerClient.denied?(denied_response)).to be true
    end

    it 'identifies running responses' do
      expect(client.running?(pending_response)).to be true
      expect(client.running?(approved_response)).to be false
      expect(Composer::ComposerClient.running?(pending_response)).to be true
    end

    it 'identifies error responses' do
      expect(client.has_error?(error_response)).to be true
      expect(client.has_error?(approved_response)).to be false
      expect(Composer::ComposerClient.has_error?(error_response)).to be true
    end

    it 'identifies timeout responses' do
      timeout_response = Composer::CheckpointResponse.new(success: true, is_timeout: true)
      expect(client.timeout?(timeout_response)).to be true
      expect(Composer::ComposerClient.timeout?(timeout_response)).to be true
    end

    it 'identifies undecided responses' do
      undecided_response = Composer::CheckpointResponse.new(
        success: true,
        verification: Composer::Verification.new(
          id: 'ver-1',
          status: Composer::VerificationStatus::COMPLETE,
          outcome: Composer::VerificationOutcome::PENDING
        )
      )
      expect(client.undecided?(undecided_response)).to be true
      expect(Composer::ComposerClient.undecided?(undecided_response)).to be true
    end
  end
end
