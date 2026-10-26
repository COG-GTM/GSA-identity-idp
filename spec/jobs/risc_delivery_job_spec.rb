require 'rails_helper'

RSpec.describe RiscDeliveryJob do
  include ActiveJob::TestHelper
  around do |ex|
    REDIS_THROTTLE_POOL.with { |client| client.flushdb }
    ex.run
    REDIS_THROTTLE_POOL.with { |client| client.flushdb }
  end

  describe '#perform' do
    let(:event_type) { PushNotification::IdentifierRecycledEvent::EVENT_TYPE }
    let(:issuer) { 'issuer1' }
    let(:job) { RiscDeliveryJob.new }
    let(:job_analytics) { FakeAnalytics.new }
    let(:jwt) { JWT.encode({ foo: 'bar' }, 'a') }
    let(:now) { 5.hours.ago }
    let(:push_notification_url) { 'https://push.example.gov' }

    let(:risc_event_payload) do
      {
        client_id: issuer,
        event_type: event_type,
        success: false,
      }
    end

    subject(:perform) do
      job.perform(
        push_notification_url: push_notification_url,
        jwt: jwt,
        event_type: event_type,
        issuer: issuer,
        now: now,
      )
    end

    let(:resolved_addresses) { ['93.184.215.14'] }

    before do
      allow(job).to receive(:analytics).and_return(job_analytics)
      ActiveJob::Base.queue_adapter = :test
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('push.example.gov')
        .and_return(resolved_addresses)
    end

    it 'POSTs the jwt to the given URL' do
      req = stub_request(:post, push_notification_url)
        .with(
          body: jwt,
          headers: {
            'Content-Type' => 'application/secevent+jwt',
            'Accept' => 'application/json',
          },
        )

      perform

      expect(req).to have_been_requested
      expect(job_analytics).to have_logged_event(
        :risc_security_event_pushed,
        risc_event_payload.merge(
          success: true,
          status: 200,
        ),
      )
    end

    it 'connects to the IP address that was checked' do
      req = stub_request(:post, push_notification_url)
      pinned_addresses = []
      allow_any_instance_of(Net::HTTP).to receive(:ipaddr=) do |_http, address|
        pinned_addresses << address
      end

      perform

      expect(req).to have_been_requested
      expect(pinned_addresses).to eq(['93.184.215.14'])
      expect(Resolv).to have_received(:getaddresses).with('push.example.gov').once
    end

    it 'does not follow redirects' do
      stub_request(:post, push_notification_url)
        .to_return(status: 307, headers: { 'Location' => 'http://169.254.169.254/latest' })
      internal_req = stub_request(:any, 'http://169.254.169.254/latest')

      perform

      expect(internal_req).not_to have_been_requested
      expect(job_analytics).to have_logged_event(
        :risc_security_event_pushed,
        risc_event_payload.merge(error: 'http_push_error', status: 307),
      )
    end

    context 'with a push_notification_url that is not allowed' do
      [
        'http://169.254.169.254/latest',
        'http://127.0.0.1:6379',
        'https://169.254.169.254/latest',
        'https://127.0.0.1:6379',
        'https://[::1]/push',
        'https://[::ffff:10.0.0.1]/push',
        'https://localhost/push',
        'http://push.example.gov',
        'https://user:pass@push.example.gov',
        'ftp://push.example.gov',
        'not a url',
      ].each do |url|
        context url do
          let(:push_notification_url) { url }

          it 'does not make a request and logs a failure without retrying' do
            expect(Faraday).not_to receive(:new)

            expect { perform }.not_to raise_error

            expect(a_request(:any, /.*/)).not_to have_been_made
            expect(job_analytics).to have_logged_event(
              :risc_security_event_pushed,
              risc_event_payload.merge(
                error: start_with('disallowed_push_notification_url'),
              ),
            )
          end
        end
      end

      context 'with an https URL whose host resolves to a private address' do
        let(:resolved_addresses) { ['10.0.0.1'] }

        it 'does not make a request and logs a failure' do
          expect { perform }.not_to raise_error

          expect(a_request(:any, /.*/)).not_to have_been_made
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'disallowed_push_notification_url: address is not publicly routable',
            ),
          )
        end
      end

      context 'with an https URL whose host resolves to a public and a private address' do
        let(:resolved_addresses) { ['93.184.215.14', '169.254.169.254'] }

        it 'does not make a request' do
          perform

          expect(a_request(:any, /.*/)).not_to have_been_made
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(error: start_with('disallowed_push_notification_url')),
          )
        end
      end
    end

    context 'when the host does not resolve' do
      let(:resolved_addresses) { [] }

      it 'raises a retryable delivery error without making a request' do
        expect { perform }.to raise_error(
          RiscDeliveryJob::DeliveryError,
          'could not resolve push.example.gov',
        )
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end

    context 'when internal push URLs are allowed' do
      let(:push_notification_url) { 'http://localhost:9292/api/push_notifications' }

      before do
        allow(IdentityConfig.store).to receive(:risc_notifications_allow_internal_urls)
          .and_return(true)
      end

      it 'POSTs the jwt to the URL' do
        req = stub_request(:post, push_notification_url)

        perform

        expect(req).to have_been_requested
        expect(job_analytics).to have_logged_event(
          :risc_security_event_pushed,
          risc_event_payload.merge(success: true, status: 200),
        )
      end
    end

    context 'when the job fails due to a Faraday::SSLError' do
      before do
        stub_request(:post, push_notification_url).to_raise(Faraday::SSLError)
        allow_any_instance_of(described_class).to receive(:analytics).and_return(job_analytics)
      end

      context 'when the job fails for the 1st time' do
        it 'raises and retries via ActiveJob' do
          expect { perform }.to raise_error(RiscDeliveryJob::DeliveryError)

          expect(job_analytics).not_to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Exception from WebMock',
            ),
          )
        end
      end

      context 'when the job fails past the configured retry attempts' do
        it 'logs an event' do
          perform_enqueued_jobs do
            RiscDeliveryJob.perform_later(
              push_notification_url: push_notification_url,
              jwt: jwt,
              event_type: event_type,
              issuer: issuer,
            )
          end

          expect(a_request(:post, push_notification_url)).to have_been_made.times(2)
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Exception from WebMock',
            ),
          )
        end
      end
    end

    context 'when the job fails due to a Faraday::ConnectionFailed' do
      before do
        stub_request(:post, push_notification_url).to_raise(Faraday::ConnectionFailed)
        allow_any_instance_of(described_class).to receive(:analytics).and_return(job_analytics)
      end

      context 'when the job fails for the 1st time' do
        it 'raises and retries via ActiveJob' do
          expect { perform }.to raise_error(RiscDeliveryJob::DeliveryError)

          expect(job_analytics).not_to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Exception from WebMock',
            ),
          )
        end
      end

      context 'when the job fails past the configured retry attempts' do
        it 'logs an event' do
          perform_enqueued_jobs do
            RiscDeliveryJob.perform_later(
              push_notification_url: push_notification_url,
              jwt: jwt,
              event_type: event_type,
              issuer: issuer,
            )
          end

          expect(a_request(:post, push_notification_url)).to have_been_made.times(2)
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Exception from WebMock',
            ),
          )
        end
      end
    end

    context 'when the job fails due to an Errno::ECONNREFUSED error' do
      before do
        allow_any_instance_of(described_class).to receive(:analytics).and_return(job_analytics)
        # stub_request().to_raise wraps this in Faraday::ConnectionFailed, but
        # in actual usage, the original error is unwrapped
        @connection = instance_double(Faraday::Connection)
        allow(@connection).to receive(:post).and_raise(Errno::ECONNREFUSED)
        allow(Faraday).to receive(:new).and_return(@connection)
      end

      context 'when the job fails for the 1st time' do
        it 'raises and retries via ActiveJob' do
          expect { perform }.to raise_error(RiscDeliveryJob::DeliveryError)

          expect(job_analytics).not_to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Connection refused',
            ),
          )
        end
      end

      context 'when the job fails past the configured retry attempts' do
        it 'logs an event' do
          perform_enqueued_jobs do
            RiscDeliveryJob.perform_later(
              push_notification_url: push_notification_url,
              jwt: jwt,
              event_type: event_type,
              issuer: issuer,
            )
          end

          expect(@connection).to have_received(:post).exactly(2)
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'Connection refused',
            ),
          )
        end
      end
    end

    context 'non-200 response' do
      before do
        stub_request(:post, push_notification_url).to_return(status: 403)
      end

      it 'logs an event' do
        expect { perform }.to_not raise_error
        expect(job_analytics).to have_logged_event(
          :risc_security_event_pushed,
          risc_event_payload.merge(
            error: 'http_push_error',
            status: 403,
          ),
        )
      end

      context 'it has already failed twice' do
        before do
          allow(job).to receive(:executions).and_return 2
        end

        it 'logs an event' do
          expect { perform }.to_not raise_error

          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'http_push_error',
              status: 403,
            ),
          )
        end
      end
    end

    context 'when the job encounters rate limiting' do
      before do
        allow_any_instance_of(described_class).to receive(:analytics).and_return(job_analytics)
        @redis_rate_limiter = instance_double(RedisRateLimiter)
        allow(@redis_rate_limiter).to receive(:attempt!).and_raise(RedisRateLimiter::LimitError)
        allow(RedisRateLimiter).to receive(:new).and_return(@redis_rate_limiter)
      end

      context 'when the job fails for the 1st time' do
        it 'raises and retries via ActiveJob' do
          expect { perform }.to raise_error(RedisRateLimiter::LimitError)

          expect(job_analytics).not_to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'RedisRateLimiter::LimitError',
            ),
          )
        end
      end

      context 'when the job fails past the configured retry attempts' do
        it 'logs an event' do
          perform_enqueued_jobs do
            RiscDeliveryJob.perform_later(
              push_notification_url: push_notification_url,
              jwt: jwt,
              event_type: event_type,
              issuer: issuer,
            )
          end

          expect(@redis_rate_limiter).to have_received(:attempt!).exactly(10)
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              error: 'RedisRateLimiter::LimitError',
            ),
          )
        end
      end
    end

    context 'rate limiting' do
      before do
        REDIS_THROTTLE_POOL.with do |redis|
          redis.set(job.rate_limiter(push_notification_url).build_key(now), 9999)
        end
      end

      context 'when the rate limit is overridden' do
        before do
          allow(IdentityConfig.store).to receive(:risc_notifications_rate_limit_overrides)
            .and_return({ push_notification_url => { 'max_requests' => 1e6, 'interval' => 500 } })
        end

        it 'allows the request' do
          req = stub_request(:post, push_notification_url)
          perform

          expect(req).to have_been_requested
          expect(job_analytics).to have_logged_event(
            :risc_security_event_pushed,
            risc_event_payload.merge(
              success: true,
              status: 200,
            ),
          )
        end
      end
    end
  end

  describe '.warning_error_classes' do
    it 'is all the network errors and rate limiting errors' do
      expect(described_class.warning_error_classes).to match_array(
        [RiscDeliveryJob::DeliveryError, RedisRateLimiter::LimitError],
      )
    end
  end
end
