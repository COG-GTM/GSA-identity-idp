# frozen_string_literal: true

require 'ipaddr'
require 'resolv'

module PushNotification
  # Decides whether a service provider's push_notification_url may receive a RISC
  # security event, and pins the delivery to the IP address that was checked so a DNS
  # change between the check and the request cannot redirect it to an internal host.
  class UrlPolicy
    class DisallowedUrlError < StandardError; end
    class UnresolvableHostError < StandardError; end

    Destination = Struct.new(:uri, :ip_address, keyword_init: true)

    BLOCKED_IP_RANGES = %w[
      0.0.0.0/8
      10.0.0.0/8
      100.64.0.0/10
      127.0.0.0/8
      169.254.0.0/16
      172.16.0.0/12
      192.0.0.0/24
      192.0.2.0/24
      192.88.99.0/24
      192.168.0.0/16
      198.18.0.0/15
      198.51.100.0/24
      203.0.113.0/24
      224.0.0.0/4
      240.0.0.0/4
      ::/128
      ::1/128
      ::ffff:0:0/96
      64:ff9b::/96
      64:ff9b:1::/48
      100::/64
      2001::/23
      2001:db8::/32
      2002::/16
      fc00::/7
      fe80::/10
      fec0::/10
      ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    attr_reader :url

    def initialize(url, allow_internal: IdentityConfig.store.risc_notifications_allow_internal_urls)
      @url = url
      @allow_internal = allow_internal
    end

    # Checks the URL without DNS lookups: scheme, host, userinfo and literal IP hosts
    # @return [Boolean]
    def statically_valid?
      validated_uri
      true
    rescue DisallowedUrlError
      false
    end

    # Resolves the host and checks every address it resolves to
    # @raise [DisallowedUrlError] the URL or any resolved address is not allowed
    # @raise [UnresolvableHostError] the host has no addresses
    # @return [Destination] the URI and the checked IP address to connect to
    def destination!(resolver: Resolv)
      uri = validated_uri
      return Destination.new(uri:, ip_address: nil) if allow_internal

      addresses = resolver.getaddresses(uri.hostname).map { |address| IPAddr.new(address) }
      raise UnresolvableHostError, "could not resolve #{uri.hostname}" if addresses.empty?
      addresses.each { |address| check_ip!(address) }

      Destination.new(uri:, ip_address: addresses.first.native.to_s)
    rescue IPAddr::InvalidAddressError
      raise DisallowedUrlError, 'resolved to an invalid address'
    end

    def self.blocked_ip?(ip)
      ip = ip.native
      BLOCKED_IP_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
    end

    private

    attr_reader :allow_internal

    def validated_uri
      uri = parse_uri
      raise DisallowedUrlError, 'scheme must be https' unless allowed_scheme?(uri)
      raise DisallowedUrlError, 'host is missing' if uri.hostname.blank?
      raise DisallowedUrlError, 'userinfo is not allowed' if uri.userinfo.present?
      return uri if allow_internal

      raise DisallowedUrlError, 'host is not allowed' if internal_hostname?(uri.hostname)
      literal_ip = parse_ip(uri.hostname)
      check_ip!(literal_ip) if literal_ip
      uri
    end

    def parse_uri
      uri = URI.parse(url.to_s)
      raise DisallowedUrlError, 'not an absolute URL' unless uri.is_a?(URI::HTTP)
      uri
    rescue URI::InvalidURIError
      raise DisallowedUrlError, 'not a valid URL'
    end

    def allowed_scheme?(uri)
      uri.scheme == 'https' || (allow_internal && uri.scheme == 'http')
    end

    def internal_hostname?(hostname)
      host = hostname.downcase.delete_suffix('.')
      host == 'localhost' || host.end_with?('.localhost')
    end

    def parse_ip(hostname)
      IPAddr.new(hostname)
    rescue IPAddr::InvalidAddressError
      nil
    end

    def check_ip!(ip)
      raise DisallowedUrlError, 'address is not publicly routable' if self.class.blocked_ip?(ip)
    end
  end
end
