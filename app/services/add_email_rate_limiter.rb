# frozen_string_literal: true

# Caps add-email confirmation sends per recipient address and per account, so a signed-in user
# cannot use the add-email or resend flows to flood an arbitrary inbox.
class AddEmailRateLimiter
  def initialize(user:, email:)
    @user = user
    @email = email
  end

  # Records a send unless a limit has been reached. Returns the limiter that blocked the send, or
  # nil when the email may be sent.
  def attempt!
    limited = rate_limiters.find(&:limited?)
    return limited if limited

    rate_limiters.each(&:increment!)
    nil
  end

  private

  attr_reader :user, :email

  def rate_limiters
    @rate_limiters ||= [
      RateLimiter.new(rate_limit_type: :add_email_per_recipient, target: digested_email),
      RateLimiter.new(rate_limit_type: :add_email_per_user, user:),
    ]
  end

  def digested_email
    normalized_email = EmailNormalizer.new(email.to_s.strip.downcase).normalized_email
    OpenSSL::Digest::SHA256.hexdigest(normalized_email)
  end
end
