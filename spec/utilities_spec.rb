# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Composer::Utilities do
  describe '.null_or_empty?' do
    it 'returns true for nil' do
      expect(Composer::Utilities.null_or_empty?(nil)).to be true
    end

    it 'returns true for empty string' do
      expect(Composer::Utilities.null_or_empty?('')).to be true
    end

    it 'returns true for empty array' do
      expect(Composer::Utilities.null_or_empty?([])).to be true
    end

    it 'returns false for non-empty values' do
      expect(Composer::Utilities.null_or_empty?('test')).to be false
      expect(Composer::Utilities.null_or_empty?([1, 2, 3])).to be false
      expect(Composer::Utilities.null_or_empty?(123)).to be false
    end
  end

  describe '.construct_api_url' do
    it 'adds trailing slash if missing' do
      url = Composer::Utilities.construct_api_url('https://api.test.com', 'v1')
      expect(url).to eq('https://api.test.com/v1/')
    end

    it 'preserves trailing slash' do
      url = Composer::Utilities.construct_api_url('https://api.test.com/', 'v1')
      expect(url).to eq('https://api.test.com/v1/')
    end
  end

  describe '.construct_api_headers' do
    it 'includes required headers' do
      headers = Composer::Utilities.construct_api_headers('secret-key')

      expect(headers['Dodgeball-Secret-Key']).to eq('secret-key')
      expect(headers['Composer-SDK-Version']).to eq(Composer::VERSION)
      expect(headers['Composer-SDK-Source']).to eq('ruby-sdk')
      expect(headers['Content-Type']).to eq('application/json')
    end

    it 'includes optional headers when provided' do
      headers = Composer::Utilities.construct_api_headers(
        'secret-key',
        'ver-123',
        'source-token',
        'customer-id',
        'session-id'
      )

      expect(headers['Dodgeball-Verification-Id']).to eq('ver-123')
      expect(headers['Dodgeball-Source-Token']).to eq('source-token')
      expect(headers['Dodgeball-Customer-Id']).to eq('customer-id')
      expect(headers['Dodgeball-Session-Id']).to eq('session-id')
    end

    it 'excludes optional headers when nil or empty' do
      headers = Composer::Utilities.construct_api_headers('secret-key', nil, '', nil, '')

      expect(headers).not_to have_key('Dodgeball-Verification-Id')
      expect(headers).not_to have_key('Dodgeball-Source-Token')
      expect(headers).not_to have_key('Dodgeball-Customer-Id')
      expect(headers).not_to have_key('Dodgeball-Session-Id')
    end
  end

  describe '.parse_verification' do
    it 'parses verification from response data' do
      data = {
        'verification' => {
          'id' => 'ver-123',
          'status' => 'COMPLETE',
          'outcome' => 'APPROVED',
          'stepData' => { 'customMessage' => 'approved' }
        }
      }

      verification = Composer::Utilities.parse_verification(data)

      expect(verification).to be_a(Composer::Verification)
      expect(verification.id).to eq('ver-123')
      expect(verification.status).to eq('COMPLETE')
      expect(verification.outcome).to eq('APPROVED')
      expect(verification.step_data).to eq({ 'customMessage' => 'approved' })
      expect(verification.next_steps).to eq([])
    end

    it 'parses nextSteps from a blocked verification' do
      step = { 'id' => 'step-1', 'name' => 'MFA', 'url' => 'https://example.com/mfa.js', 'config' => {} }
      data = { 'verification' => { 'id' => 'ver-123', 'status' => 'BLOCKED', 'outcome' => 'PENDING',
                                   'nextSteps' => [step] } }

      expect(Composer::Utilities.parse_verification(data).next_steps).to eq([step])
    end

    it 'returns nil when verification is missing' do
      verification = Composer::Utilities.parse_verification({})
      expect(verification).to be_nil
    end

    it 'handles empty stepData' do
      data = {
        'verification' => {
          'id' => 'ver-123',
          'status' => 'COMPLETE',
          'outcome' => 'APPROVED'
        }
      }

      verification = Composer::Utilities.parse_verification(data)
      expect(verification.step_data).to eq({})
    end

    it 'handles object-shaped stepData from core-api' do
      data = {
        'verification' => {
          'id' => 'ver-123',
          'status' => 'COMPLETE',
          'outcome' => 'APPROVED',
          'stepData' => { 'customMessage' => '{"message":"hello"}' }
        }
      }

      verification = Composer::Utilities.parse_verification(data)
      expect(verification.step_data).to eq({ 'customMessage' => '{"message":"hello"}' })
    end

    it 'ignores non-object stepData shapes' do
      data = {
        'verification' => {
          'id' => 'ver-123',
          'status' => 'COMPLETE',
          'outcome' => 'APPROVED',
          'stepData' => [{ 'id' => 'step-1', 'name' => 'Step 1', 'data' => {} }]
        }
      }

      verification = Composer::Utilities.parse_verification(data)
      expect(verification.step_data).to eq({})
    end
  end

  describe '.parse_checkpoint_response' do
    it 'parses successful response' do
      data = {
        'success' => true,
        'version' => 'v1',
        'verification' => {
          'id' => 'ver-123',
          'status' => 'COMPLETE',
          'outcome' => 'APPROVED',
          'stepData' => {}
        },
        'isTimeout' => false
      }

      response = Composer::Utilities.parse_checkpoint_response(data)

      expect(response).to be_a(Composer::CheckpointResponse)
      expect(response.success).to be true
      expect(response.verification.id).to eq('ver-123')
      expect(response.is_timeout).to be false
    end

    it 'parses error response' do
      data = {
        'success' => false,
        'errors' => [
          { 'code' => 500, 'message' => 'Server error' }
        ],
        'version' => 'v1'
      }

      response = Composer::Utilities.parse_checkpoint_response(data)

      expect(response.success).to be false
      expect(response.errors.length).to eq(1)
      expect(response.errors.first.code).to eq(500)
      expect(response.errors.first.message).to eq('Server error')
    end
  end

  describe '.make_request' do
    it 'makes GET request' do
      stub_request(:get, 'https://api.test.com/test')
        .to_return(status: 200, body: { result: 'success' }.to_json)

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/test',
        method: :get,
        headers: { 'Authorization' => 'Bearer token' }
      )

      expect(response[:status]).to eq(200)
      expect(response[:body]['result']).to eq('success')
    end

    it 'makes POST request' do
      stub_request(:post, 'https://api.test.com/test')
        .with(body: { key: 'value' }.to_json)
        .to_return(status: 201, body: { created: true }.to_json)

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/test',
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: { key: 'value' }
      )

      expect(response[:status]).to eq(201)
      expect(response[:body]['created']).to be true
    end

    it 'parses JSON when the response declares Content-Type application/json' do
      stub_request(:post, 'https://api.test.com/v1/checkpoint')
        .to_return(
          status: 200,
          body: { success: true, version: 'v1' }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/v1/checkpoint',
        method: :post,
        headers: { 'Content-Type' => 'application/json' },
        body: { event: { type: 'TEST' } }
      )

      expect(response[:status]).to eq(200)
      expect(response[:body]['success']).to be true
    end

    it 'handles network errors' do
      stub_request(:get, 'https://api.test.com/error')
        .to_raise(Faraday::ConnectionFailed.new('Connection failed'))

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/error',
        method: :get,
        headers: {}
      )

      expect(response[:status]).to eq(500)
      expect(response[:body]['success']).to be false
      expect(response[:body]['errors']).to eq([{ 'code' => 500, 'message' => 'Internal Server Error' }])
    end

    it 'returns the standard failure body when the response is not valid JSON' do
      stub_request(:get, 'https://api.test.com/html')
        .to_return(status: 502, body: '<html>Bad Gateway</html>')

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/html',
        method: :get,
        headers: {}
      )

      expect(response[:status]).to eq(502)
      expect(response[:body]['success']).to be false
      expect(response[:body]['errors']).to eq([{ 'code' => 500, 'message' => 'Internal Server Error' }])
    end

    %w[null [] 5].each do |body|
      it "returns the standard failure body when the response is the JSON #{body}" do
        stub_request(:get, 'https://api.test.com/not-an-object').to_return(status: 200, body: body)

        response = Composer::Utilities.make_request(url: 'https://api.test.com/not-an-object', method: :get,
                                                    headers: {})

        expect(response[:body]).to eq(Composer::Utilities.request_failed_body)
      end
    end

    it 'returns the standard failure response when a request times out' do
      stub_request(:get, 'https://api.test.com/slow').to_timeout

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/slow',
        method: :get,
        headers: {}
      )

      expect(response[:status]).to eq(500)
      expect(response[:body]['success']).to be false
      expect(response[:body]['errors'].first['code']).to eq(500)
    end

    it 'bounds every request by the 30 second default when no override is provided' do
      stub_request(:get, 'https://api.test.com/test').to_return(status: 200, body: '{}')
      options = nil
      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |conn| options = conn.options }
      end

      Composer::Utilities.make_request(url: 'https://api.test.com/test', method: :get, headers: {})

      expect(options.timeout).to eq(30.0)
      expect(options.open_timeout).to eq(30.0)
    end

    it 'applies a custom request_timeout_ms' do
      stub_request(:get, 'https://api.test.com/test').to_return(status: 200, body: '{}')
      options = nil
      allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |conn| options = conn.options }
      end

      Composer::Utilities.make_request(url: 'https://api.test.com/test', method: :get, headers: {},
                                       request_timeout_ms: 1500)

      expect(options.timeout).to eq(1.5)
      expect(options.open_timeout).to eq(1.5)
    end

    it 'raises error for unsupported HTTP method' do
      expect do
        Composer::Utilities.make_request(
          url: 'https://api.test.com/test',
          method: :delete,
          headers: {}
        )
      end.to raise_error(ArgumentError, /Unsupported HTTP method/)
    end

    ["sk_test_FAKE\n123", "sk_test_FAKE\r123"].each do |secret|
      it "rejects a header value #{secret.inspect} without leaking it" do
        Composer::Logger.filter_level = Composer::Severity::ERROR

        response = nil
        expect do
          response = Composer::Utilities.make_request(
            url: 'https://api.test.com/test',
            method: :post,
            headers: { 'Dodgeball-Secret-Key' => secret },
            body: { key: 'value' }
          )
        end.to output(satisfy { |logged|
          logged.include?("A request header has a character that can't be sent, such as a newline.") &&
            !logged.include?('sk_test_FAKE')
        }).to_stdout

        expect(response[:status]).to eq(500)
        expect(response[:request_failed]).to be true
        expect(response[:body]).to eq(Composer::Utilities.request_failed_body)
      end
    end

    it 'sends a header value that only has a trailing newline' do
      stub_request(:post, 'https://api.test.com/test')
        .to_return(status: 200, body: { result: 'ok' }.to_json)

      response = Composer::Utilities.make_request(
        url: 'https://api.test.com/test',
        method: :post,
        headers: { 'Dodgeball-Secret-Key' => "sk_test_FAKE123\n" },
        body: { key: 'value' }
      )

      expect(response[:status]).to eq(200)
      expect(WebMock).to have_requested(:post, 'https://api.test.com/test')
    end
  end
end
