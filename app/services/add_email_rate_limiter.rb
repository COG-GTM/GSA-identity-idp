# frozen_string_literal: true

# Caps add-email confirmation sends per recipient address and per account, so a signed-in user
# cannot use the add-email or resend flows to flood an arbitrary inbox.
class AddEmailRateLimiter
  def initialize(user:, email:)
    @user = user
    @email = email
  end

  # Records a send unless a limit has been reached. Returns the limiter that blocked the send, or
  # nil when the email may be sent. The decision uses the atomic Redis increment result, so
  # concurrent requests cannot all slip in under the limit.
  def attempt!
    rate_limiters.each do |rate_limiter|
      attempts = rate_limiter.increment!
      return rate_limiter if attempts.nil? || attempts > max_attempts(rate_limiter)
    end
    nil
  end

  private

  attr_reader :user, :email

  def max_attempts(rate_limiter)
    RateLimiter.max_attempts(rate_limiter.rate_limit_type)
  end

  def rate_limiters
    # The per-user limiter goes first so a limited account cannot use up the recipient quota
    # that is shared with other accounts.
    @rate_limiters ||= [
      RateLimiter.new(rate_limit_type: :add_email_per_user, user:),
      RateLimiter.new(rate_limit_type: :add_email_per_recipient, target: digested_email),
    ]
  end

  def digested_email
    normalized_email = EmailNormalizer.new(email.to_s.strip.downcase).normalized_email
    OpenSSL::Digest::SHA256.hexdigest(normalized_email)
  end
end
