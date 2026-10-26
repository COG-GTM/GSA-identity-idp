# frozen_string_literal: true

module AttemptsApi
  class RedisClient
    KEY_PREFIX = 'attempts-api-events'
    HOUR_FORMAT = /\d{4}-\d{2}-\d{2}T\d{2}:00:00Z/
    HOUR_LENGTH = '2000-01-01T00:00:00Z'.length

    attr_reader :redis_pool
    def initialize
      @redis_pool = REDIS_ATTEMPTS_API_POOL
    end

    def write_event(event_key:, jwe:, timestamp:, issuer:)
      key = key(timestamp, issuer)
      @redis_pool.with do |client|
        client.hset(key, event_key, jwe)
        client.expire(key, event_ttl_seconds)
      end
    end

    def read_events(issuer:, batch_size: 1000)
      events = {}
      hourly_keys(issuer).each do |hourly_key|
        @redis_pool.with do |client|
          client.hscan_each(hourly_key, count: batch_size) do |k, v|
            break if events.keys.count == batch_size

            events[k] = v
          end
        end
      end
      events
    end

    def delete_events(issuer:, keys:)
      total_deleted = 0
      hourly_keys(issuer).each do |hourly_key|
        @redis_pool.with do |client|
          total_deleted += client.hdel(hourly_key, keys)
        end
      end

      total_deleted
    end

    private

    def event_ttl_seconds
      IdentityConfig.store.attempts_api_event_ttl_seconds
    end

    # Oldest bucket first, so batches return the oldest events.
    def hourly_keys(issuer)
      (
        buckets_with_prefix(issuer_prefix(issuer)) +
        buckets_with_prefix(legacy_issuer_prefix(issuer))
      ).uniq.sort_by { |hourly_key| [hourly_key.last(HOUR_LENGTH), hourly_key] }
    end

    def buckets_with_prefix(prefix)
      bucket_format = /\A#{Regexp.escape(prefix)}#{HOUR_FORMAT}\z/
      @redis_pool.with do |client|
        client.scan_each(match: "#{escape_glob(prefix)}*").select do |hourly_key|
          bucket_format.match?(hourly_key)
        end
      end
    end

    def key(timestamp, issuer)
      formatted_time = timestamp.in_time_zone('UTC').change(min: 0, sec: 0).iso8601
      "#{issuer_prefix(issuer)}#{formatted_time}"
    end

    # The raw issuer can contain ':' and glob characters, so it is hashed to keep
    # one partner's buckets from matching another partner's prefix.
    def issuer_prefix(issuer)
      "#{KEY_PREFIX}:#{Digest::SHA256.hexdigest(issuer)}:"
    end

    # Buckets written before issuers were hashed. They expire after
    # attempts_api_event_ttl_seconds; remove once no legacy buckets remain.
    def legacy_issuer_prefix(issuer)
      "#{KEY_PREFIX}:#{issuer}:"
    end

    def escape_glob(value)
      value.gsub(/[\\*?\[\]^]/) { |char| "\\#{char}" }
    end
  end
end
