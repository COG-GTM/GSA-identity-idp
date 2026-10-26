require 'rails_helper'

RSpec.describe Idv::SendPhoneConfirmationOtp do
  let(:phone) { '+1 225-555-5000' }
  let(:parsed_phone) { Phonelib.parse(phone) }
  let(:delivery_preference) { :sms }
  let(:otp_code) { '777777' }
  let(:user_phone_confirmation_session) do
    Idv::PhoneConfirmationSession.new(
      code: '123456',
      phone: phone,
      sent_at: Time.zone.now,
      delivery_method: delivery_preference,
      user: user,
    )
  end
  let(:idv_session) do
    Idv::Session.new(user_session: {}, current_user: user, service_provider: nil)
  end

  let(:user) { create(:user, :fully_registered) }

  let(:exceeded_otp_send_limit) { false }
  let(:otp_rate_limiter) { OtpRateLimiter.new(user: user, phone: phone, phone_confirmed: true) }

  before do
    # Setup Idv::Session
    idv_session.user_phone_confirmation_session = user_phone_confirmation_session

    allow(Idv::PhoneConfirmationSession).to receive(:generate_code).and_return(otp_code)

    # Mock OtpRateLimiter
    allow(OtpRateLimiter).to receive(:new).with(user: user, phone: phone, phone_confirmed: true)
      .and_return(otp_rate_limiter)
    allow(otp_rate_limiter).to receive(:exceeded_otp_send_limit?)
      .and_return(exceeded_otp_send_limit)
  end

  subject { described_class.new(user: user, idv_session: idv_session) }

  describe '#call' do
    let(:now) { Time.zone.now }

    context 'with sms' do
      it 'sends an sms' do
        allow(Telephony).to receive(:send_confirmation_otp).and_call_original

        result = travel_to(now) { subject.call }

        expect(result.success?).to eq(true)

        phone_confirmation_session = idv_session.user_phone_confirmation_session

        expect(phone_confirmation_session.code).to eq(otp_code)
        expect(phone_confirmation_session.sent_at.to_i).to eq(now.to_i)
        expect(phone_confirmation_session.delivery_method).to eq(:sms)

        expect(Telephony).to have_received(:send_confirmation_otp).with(
          otp: otp_code,
          to: phone,
          expiration: 10,
          channel: :sms,
          otp_format: 'character',
          otp_length: '6',
          domain: IdentityConfig.store.domain_name,
          country_code: 'US',
          extra_metadata: {
            area_code: parsed_phone.area_code,
            phone_fingerprint: Pii::Fingerprinter.fingerprint(parsed_phone.e164),
            resend: nil,
          },
        )
      end
    end

    context 'with voice' do
      let(:delivery_preference) { :voice }

      it 'makes a phone call' do
        allow(Telephony).to receive(:send_confirmation_otp).and_call_original

        result = travel_to(now) { subject.call }

        expect(result.success?).to eq(true)

        phone_confirmation_session = idv_session.user_phone_confirmation_session

        expect(phone_confirmation_session.code).to eq(otp_code)
        expect(phone_confirmation_session.sent_at.to_i).to eq(now.to_i)
        expect(phone_confirmation_session.delivery_method).to eq(:voice)

        expect(Telephony).to have_received(:send_confirmation_otp).with(
          otp: otp_code,
          to: phone,
          expiration: 10,
          channel: :voice,
          otp_format: 'digit',
          otp_length: '10',
          domain: IdentityConfig.store.domain_name,
          country_code: 'US',
          extra_metadata: {
            area_code: parsed_phone.area_code,
            phone_fingerprint: Pii::Fingerprinter.fingerprint(parsed_phone.e164),
            resend: nil,
          },
        )
      end
    end

    context 'when the user has requested too many otps' do
      let(:exceeded_otp_send_limit) { true }

      it 'does not make a phone call or send an sms' do
        expect(Telephony).to_not receive(:send_authentication_otp)
        expect(Telephony).to_not receive(:send_confirmation_otp)

        result = subject.call

        expect(result.success?).to eq(false)
      end
    end
  end

  describe 'when a previous OTP send lockout has expired' do
    let(:max_sends) { IdentityConfig.store.otp_delivery_blocklist_maxretry }

    before do
      allow(otp_rate_limiter).to receive(:exceeded_otp_send_limit?).and_call_original
      user.update!(
        second_factor_locked_at: (IdentityConfig.store.lockout_period_in_minutes + 10).minutes.ago,
        second_factor_attempts_count: 3,
      )
    end

    it 'clears the lockout on the first send so later sends are still rate limited' do
      expect(described_class.new(user:, idv_session:).call.success?).to eq(true)
      expect(user.reload.second_factor_locked_at).to be_nil
      expect(user.second_factor_attempts_count).to eq(0)

      (max_sends - 1).times do
        expect(described_class.new(user:, idv_session:).call.success?).to eq(true)
      end

      service = described_class.new(user:, idv_session:)
      expect(Telephony).not_to receive(:send_confirmation_otp)
      expect(service.call.success?).to eq(false)
      expect(service.user_locked_out?).to eq(true)
      expect(user.reload.second_factor_locked_at).to be_present
    end
  end

  describe '#user_locked_out?' do
    before do
      allow(otp_rate_limiter).to receive(:exceeded_otp_send_limit?)
        .and_return(exceeded_otp_send_limit)
    end

    context 'the user is locked out' do
      let(:exceeded_otp_send_limit) { true }

      it 'returns true' do
        subject.call

        expect(subject.user_locked_out?).to eq(true)
      end
    end

    context 'the user is not locked out' do
      it 'returns false' do
        subject.call

        expect(subject.user_locked_out?).to be_falsey
      end
    end
  end
end
