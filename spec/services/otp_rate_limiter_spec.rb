require 'rails_helper'

RSpec.describe OtpRateLimiter do
  let(:current_user) { build(:user, :with_phone) }
  let(:phone) { MfaContext.new(current_user).phone_configurations.first.phone }
  subject(:otp_rate_limiter) do
    OtpRateLimiter.new(phone: phone, user: current_user, phone_confirmed: false)
  end
  subject(:otp_rate_limiter_confirmed) do
    OtpRateLimiter.new(phone: phone, user: current_user, phone_confirmed: true)
  end
  let(:phone_fingerprint) { Pii::Fingerprinter.fingerprint(phone) }

  describe '#exceeded_otp_send_limit?' do
    it 'is false by default' do
      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)
    end

    it 'is true after maxretry_times attemps +1 in findtime minutes' do
      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)

      (IdentityConfig.store.otp_delivery_blocklist_maxretry + 1).times do
        otp_rate_limiter.increment
      end

      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(true)
    end

    it 'is is false after maxretry_times attemps in findtime minutes' do
      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)

      IdentityConfig.store.otp_delivery_blocklist_maxretry.times do
        otp_rate_limiter.increment
      end

      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)
    end

    it 'tracks verified phones separately. limiting one does not limit the other' do
      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)

      (IdentityConfig.store.otp_delivery_blocklist_maxretry + 1).times do
        otp_rate_limiter.increment
      end

      expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(true)
      expect(otp_rate_limiter_confirmed.exceeded_otp_send_limit?).to eq(false)
    end
  end

  describe '#increment' do
    it 'updates otp_last_sent_at' do
      otp_rate_limiter.increment
      old_otp_last_sent_at = otp_rate_limiter.otp_last_sent_at
      otp_rate_limiter.increment
      new_otp_last_sent_at = otp_rate_limiter.otp_last_sent_at

      expect(new_otp_last_sent_at).to be > old_otp_last_sent_at
    end

    it 'increments the otp_send_count' do
      otp_rate_limiter.increment

      expect { otp_rate_limiter.increment }
        .to change { otp_rate_limiter.rate_limiter.attempts }.from(1).to(2)
    end
  end

  describe '#reset_count_if_user_no_longer_locked_out' do
    let(:current_user) { create(:user, :with_phone) }

    before do
      (IdentityConfig.store.otp_delivery_blocklist_maxretry + 1).times do
        otp_rate_limiter.increment
      end
    end

    context 'when the user was never locked out' do
      it 'keeps the send count' do
        otp_rate_limiter.reset_count_if_user_no_longer_locked_out

        expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(true)
      end
    end

    context 'when the user is still locked out' do
      before { current_user.update!(second_factor_locked_at: Time.zone.now) }

      it 'keeps the send count and the lockout' do
        otp_rate_limiter.reset_count_if_user_no_longer_locked_out

        expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(true)
        expect(current_user.reload.second_factor_locked_at).to be_present
      end
    end

    context 'when the lockout has expired' do
      before do
        current_user.update!(
          second_factor_locked_at: (IdentityConfig.store.lockout_period_in_minutes + 1).minutes.ago,
          second_factor_attempts_count: 3,
        )
      end

      it 'resets the send count and clears the lockout' do
        otp_rate_limiter.reset_count_if_user_no_longer_locked_out

        expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(false)
        expect(current_user.reload.second_factor_locked_at).to be_nil
        expect(current_user.second_factor_attempts_count).to eq(0)
      end

      it 'only resets the send count once per lockout' do
        otp_rate_limiter.reset_count_if_user_no_longer_locked_out
        otp_rate_limiter.increment
        otp_rate_limiter.reset_count_if_user_no_longer_locked_out

        expect(otp_rate_limiter.rate_limiter.attempts).to eq(1)
      end

      it 'does not clear a lockout set by a concurrent request after this user was loaded' do
        User.where(id: current_user.id).update_all(second_factor_locked_at: Time.zone.now)

        otp_rate_limiter.reset_count_if_user_no_longer_locked_out

        expect(otp_rate_limiter.exceeded_otp_send_limit?).to eq(true)
        expect(current_user.reload.second_factor_locked_at).to be_present
      end
    end
  end

  describe '#lock_out_user' do
    it 'sets the second_factor_locked_at' do
      expect(current_user.second_factor_locked_at).to be_nil

      otp_rate_limiter.lock_out_user

      expect(current_user.second_factor_locked_at).to be_within(1.second).of(Time.zone.now)
    end
  end
end
