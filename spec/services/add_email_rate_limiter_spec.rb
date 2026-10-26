require 'rails_helper'

RSpec.describe AddEmailRateLimiter do
  let(:user) { create(:user) }
  let(:email) { 'target@example.com' }
  let(:recipient_max) { IdentityConfig.store.add_email_per_recipient_max_attempts }
  let(:user_max) { IdentityConfig.store.add_email_per_user_max_attempts }

  def attempt(user: self.user, email: self.email)
    AddEmailRateLimiter.new(user:, email:).attempt!
  end

  it 'allows sends up to the per-recipient limit, then returns the recipient limiter' do
    recipient_max.times { expect(attempt).to be_nil }

    limiter = attempt
    expect(limiter.rate_limit_type).to eq(:add_email_per_recipient)
    expect(limiter).to be_limited
  end

  it 'applies the per-recipient limit across accounts and address variants' do
    recipient_max.times { attempt(user: create(:user)) }

    expect(attempt(email: '  TARGET@example.com ')&.rate_limit_type)
      .to eq(:add_email_per_recipient)
  end

  it 'applies the per-user limit across recipients' do
    user_max.times { |i| expect(attempt(email: "target#{i}@example.com")).to be_nil }

    expect(attempt(email: 'another@example.com')&.rate_limit_type).to eq(:add_email_per_user)
  end

  it 'refuses a send that races past the limit check' do
    (recipient_max - 1).times { attempt }
    racing = AddEmailRateLimiter.new(user:, email:)
    allow_any_instance_of(RateLimiter).to receive(:limited?).and_return(false)

    expect(attempt).to be_nil
    expect(racing.attempt!&.rate_limit_type).to eq(:add_email_per_recipient)
  end

  it 'does not count attempts refused by the per-user limit against the recipient' do
    user_max.times { |i| attempt(email: "target#{i}@example.com") }
    (recipient_max + 1).times { attempt }

    expect(RateLimiter.new(rate_limit_type: :add_email_per_recipient, target: digest(email)))
      .not_to be_limited
    expect(attempt(user: create(:user))).to be_nil
  end

  def digest(address)
    OpenSSL::Digest::SHA256.hexdigest(EmailNormalizer.new(address).normalized_email)
  end
end
