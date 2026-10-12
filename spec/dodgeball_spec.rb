# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Composer::DodgeballClient do
  let(:secret_key) { 'test-secret-key' }

  it 'inherits from ComposerClient' do
    expect(Composer::DodgeballClient).to be < Composer::ComposerClient
  end

  it 'creates a client with valid secret key' do
    client = Composer::DodgeballClient.new(secret_key, { log_level: Composer::ComposerLogLevel::NONE })
    expect(client.secret_key).to eq(secret_key)
  end

  it 'has access to all ComposerClient methods' do
    client = Composer::DodgeballClient.new(secret_key, { enabled: false, log_level: Composer::ComposerLogLevel::NONE })
    event = Composer::CheckpointEvent.new(ip: '127.0.0.1', data: {})

    response = client.checkpoint(
      checkpoint_name: 'TEST',
      event: event,
      session_id: 'session-123'
    )

    expect(response).to be_a(Composer::CheckpointResponse)
    expect(response.success).to be true
  end
end
