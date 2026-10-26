# frozen_string_literal: true

require 'resolv'

# Class to help normalize email addresses for services like Gmail that let users
# add extra things after a +
class EmailNormalizer
  attr_reader :email

  # @param [#to_s] email
  def initialize(email)
    @email = Mail::Address.new(email.to_s)
  end

  # @return [String]
  def normalized_email
    if gmail?
      before_plus, _after_plus = email.local.split('+', 2)
      [before_plus.tr('.', ''), email.domain].join('@')
    else
      email.to_s
    end
  end

  # Mailbox identity used for per-address rate limiting. Unlike #normalized_email (which is
  # persisted in SuspendedEmail digests), this drops any +tag for every domain and ignores case,
  # since most providers deliver user+tag@ and USER@ to the same inbox as user@.
  # @return [String]
  def rate_limit_email
    return normalized_email.downcase if gmail?
    return email.to_s.downcase if email.local.blank? || email.domain.blank?

    before_plus, _after_plus = email.local.split('+', 2)
    local = before_plus.presence || email.local
    [local, email.domain].join('@').downcase
  end

  private

  def gmail?
    return @gmail if defined?(@gmail)
    @gmail = email.domain == 'gmail.com' || google_mx_record?
  end

  def google_mx_record?
    return false if ENV['RAILS_OFFLINE']
    return false if email.domain.blank? || !email.domain.to_s.ascii_only?

    mx_records(email.domain).any? { |domain| domain.end_with?('google.com') }
  end

  def mx_records(domain)
    Resolv::DNS.open do |dns|
      dns.getresources(domain, Resolv::DNS::Resource::IN::MX)
        .map { |r| r.exchange.to_s }
    end
  end
end
