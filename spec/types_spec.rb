# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Composer Types' do
  describe Composer::CheckpointEvent do
    it 'creates event with ip and data' do
      event = Composer::CheckpointEvent.new(ip: '127.0.0.1', data: { key: 'value' })
      expect(event.ip).to eq('127.0.0.1')
      expect(event.data[:key]).to eq('value')
    end

    it 'converts to hash' do
      event = Composer::CheckpointEvent.new(ip: '127.0.0.1', data: { test: 'data' })
      hash = event.to_h
      expect(hash[:ip]).to eq('127.0.0.1')
      expect(hash[:data][:test]).to eq('data')
    end
  end

  describe Composer::TrackEvent do
    it 'creates event with type and data' do
      event = Composer::TrackEvent.new(type: 'TEST_EVENT', data: { key: 'value' })
      expect(event.type).to eq('TEST_EVENT')
      expect(event.data[:key]).to eq('value')
    end

    it 'includes event_time if provided' do
      time = (Time.now.to_f * 1000).to_i
      event = Composer::TrackEvent.new(type: 'TEST', data: {}, event_time: time)
      hash = event.to_h
      expect(hash[:eventTime]).to eq(time)
    end

    it 'excludes event_time if nil' do
      event = Composer::TrackEvent.new(type: 'TEST', data: {})
      hash = event.to_h
      expect(hash).not_to have_key(:eventTime)
    end
  end

  describe Composer::Verification do
    it 'creates verification with all attributes' do
      verification = Composer::Verification.new(
        id: 'ver-123',
        status: 'COMPLETE',
        outcome: 'APPROVED',
        step_data: {}
      )

      expect(verification.id).to eq('ver-123')
      expect(verification.status).to eq('COMPLETE')
      expect(verification.outcome).to eq('APPROVED')
    end
  end

  describe Composer::CheckpointResponse do
    it 'creates response with verification' do
      verification = Composer::Verification.new(
        id: 'ver-123',
        status: 'COMPLETE',
        outcome: 'APPROVED'
      )

      response = Composer::CheckpointResponse.new(
        success: true,
        verification: verification
      )

      expect(response.success).to be true
      expect(response.verification.id).to eq('ver-123')
    end

    describe '#allowed?' do
      it 'returns true for approved complete response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::APPROVED
          )
        )
        expect(response.allowed?).to be true
      end

      it 'returns false for denied response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.allowed?).to be false
      end

      it 'returns false for pending response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::PENDING,
            outcome: Composer::VerificationOutcome::PENDING
          )
        )
        expect(response.allowed?).to be false
      end
    end

    describe '#denied?' do
      it 'returns true for denied complete response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.denied?).to be true
      end

      it 'returns true for denied pending response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::PENDING,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.denied?).to be true
      end

      it 'returns true for denied blocked response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::BLOCKED,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.denied?).to be true
      end

      it 'returns false for unsuccessful denied complete response' do
        response = Composer::CheckpointResponse.new(
          success: false,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.denied?).to be false
      end
    end

    describe '#running?' do
      it 'returns true for pending status' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::PENDING,
            outcome: Composer::VerificationOutcome::PENDING
          )
        )
        expect(response.running?).to be true
      end

      it 'returns true for blocked status' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::BLOCKED,
            outcome: Composer::VerificationOutcome::PENDING
          )
        )
        expect(response.running?).to be true
      end

      it 'returns false for denied blocked response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::BLOCKED,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.running?).to be false
      end

      it 'returns false for denied pending response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::PENDING,
            outcome: Composer::VerificationOutcome::DENIED
          )
        )
        expect(response.running?).to be false
      end

      it 'returns false for approved blocked response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::BLOCKED,
            outcome: Composer::VerificationOutcome::APPROVED
          )
        )
        expect(response.running?).to be false
      end

      it 'returns false for complete status' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::APPROVED
          )
        )
        expect(response.running?).to be false
      end
    end

    describe '#has_error?' do
      it 'returns true for unsuccessful response' do
        response = Composer::CheckpointResponse.new(success: false)
        expect(response.has_error?).to be true
      end

      it 'returns true for error outcome' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::FAILED,
            outcome: Composer::VerificationOutcome::ERROR
          )
        )
        expect(response.has_error?).to be true
      end

      it 'returns false for successful approved response' do
        response = Composer::CheckpointResponse.new(
          success: true,
          verification: Composer::Verification.new(
            id: 'ver-1',
            status: Composer::VerificationStatus::COMPLETE,
            outcome: Composer::VerificationOutcome::APPROVED
          )
        )
        expect(response.has_error?).to be false
      end
    end

    describe '#timeout?' do
      it 'returns true when is_timeout is true' do
        response = Composer::CheckpointResponse.new(success: true, is_timeout: true)
        expect(response.timeout?).to be true
      end

      it 'returns false when is_timeout is false' do
        response = Composer::CheckpointResponse.new(success: true, is_timeout: false)
        expect(response.timeout?).to be false
      end
    end
  end

  describe Composer::ApiError do
    it 'creates error with code and message' do
      error = Composer::ApiError.new(code: 500, message: 'Server error')
      expect(error.code).to eq(500)
      expect(error.message).to eq('Server error')
    end

    it 'creates error with message only' do
      error = Composer::ApiError.new(message: 'Error message')
      expect(error.code).to be_nil
      expect(error.message).to eq('Error message')
    end
  end
end
