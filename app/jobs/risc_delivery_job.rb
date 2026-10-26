# frozen_string_literal: true

class RiscDeliveryJob < ApplicationJob
  queue_as :low

  class DeliveryError < StandardError; end

  NETWORK_ERRORS = [
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    Faraday::SSLError,
    Errno::ECONNREFUSED,
  ].freeze

  retry_on(
    DeliveryError,
    wait: :polynomially_longer,
    attempts: 2,
  ) do |job, exception|
    args = job.arguments.first
    job.track_event(
      success: false,
      error: exception.message,
      event_type: args[:event_type],
      issuer: args[:issuer],
      user: args[:user],
    )
  end

  retry_on RedisRateLimiter::LimitError,
           wait: :polynomially_longer,
           attempts: 10 do |job, exception|
             args = job.arguments.first
             job.track_event(
               success: false,
               error: exception.message,
               event_type: args[:event_type],
               issuer: args[:issuer],
               user: args[:user],
             )
           end

  def self.warning_error_classes
    [DeliveryError, RedisRateLimiter::LimitError]
  end

  def perform(
    event_type:,
    issuer:,
    jwt:,
    push_notification_url:,
    now: Time.zone.now,
    user: nil
  )
    destination = PushNotification::UrlPolicy.new(push_notification_url).destination!

    response = rate_limiter(push_notification_url).attempt!(now) do
      faraday(destination).post(
        push_notification_url,
        jwt,
        'Accept' => 'application/json',
        'Content-Type' => 'application/secevent+jwt',
      ) do |req|
        req.options.context = {
          service_name: 'risc_http_push_async',
        }
      end
    end

    track_event(
      error: response.success? ? nil : 'http_push_error',
      event_type:,
      issuer:,
      status: response.status,
      success: response.success?,
      user:,
    )
  rescue PushNotification::UrlPolicy::DisallowedUrlError => e
    track_event(
      error: "disallowed_push_notification_url: #{e.message}",
      event_type:,
      issuer:,
      success: false,
      user:,
    )
  rescue PushNotification::UrlPolicy::UnresolvableHostError, *NETWORK_ERRORS => e
    raise DeliveryError.new(e.message)
  end

  def rate_limiter(url)
    url_overrides = IdentityConfig.store.risc_notifications_rate_limit_overrides.fetch(url, {})

    RedisRateLimiter.new(
      key: "push-notification-#{url}",
      max_requests: url_overrides['max_requests'] ||
        IdentityConfig.store.risc_notifications_rate_limit_max_requests,
      interval: url_overrides['interval'] ||
        IdentityConfig.store.risc_notifications_rate_limit_interval,
    )
  end

  def faraday(destination)
    Faraday.new do |f|
      # A proxy would resolve the hostname itself, bypassing the pinned address
      f.proxy = nil if destination.ip_address
      f.request :instrumentation, name: 'request_log.faraday'
      f.adapter :net_http do |http|
        http.ipaddr = destination.ip_address if destination.ip_address
      end
      f.options.timeout = IdentityConfig.store.risc_notifications_request_timeout
    end
  end

  def track_event(event_type:, issuer:, success:, user:, error: nil, status: nil)
    analytics(user).risc_security_event_pushed(
      client_id: issuer,
      error:,
      event_type:,
      status:,
      success:,
    )
  end

  def analytics(user)
    @analytics ||= Analytics.new(
      request: nil,
      session: {},
      sp: nil,
      user: user || AnonymousUser.new,
    )
  end
end
