require 'rails_helper'

RSpec.describe PushNotification::UrlPolicy do
  let(:allow_internal) { false }
  let(:resolver) { class_double(Resolv, getaddresses: resolved_addresses) }
  let(:resolved_addresses) { ['93.184.215.14'] }

  subject(:policy) { described_class.new(url, allow_internal:) }

  describe '#destination!' do
    subject(:destination) { policy.destination!(resolver:) }

    context 'with a public https URL' do
      let(:url) { 'https://push.example.gov/risc?x=1' }

      it 'returns the URI and the checked IP address' do
        expect(destination.uri.to_s).to eq(url)
        expect(destination.ip_address).to eq('93.184.215.14')
        expect(resolver).to have_received(:getaddresses).with('push.example.gov')
      end
    end

    context 'with a host that resolves to an IPv4-mapped IPv6 address' do
      let(:url) { 'https://push.example.gov' }
      let(:resolved_addresses) { ['::ffff:93.184.215.14'] }

      it 'pins the native IPv4 address' do
        expect(destination.ip_address).to eq('93.184.215.14')
      end
    end

    %w[
      0.0.0.0
      10.0.0.1
      100.64.0.1
      127.0.0.1
      169.254.169.254
      172.16.0.1
      192.168.1.1
      198.18.0.1
      224.0.0.1
      255.255.255.255
      ::
      ::1
      ::ffff:127.0.0.1
      64:ff9b::a00:1
      fc00::1
      fd00:ec2::254
      fe80::1
      ff02::1
    ].each do |address|
      context "with a host that resolves to #{address}" do
        let(:url) { 'https://push.example.gov' }
        let(:resolved_addresses) { [address] }

        it 'raises DisallowedUrlError' do
          expect { destination }.to raise_error(
            described_class::DisallowedUrlError,
            'address is not publicly routable',
          )
        end
      end
    end

    context 'with a host that resolves to a public and a private address' do
      let(:url) { 'https://push.example.gov' }
      let(:resolved_addresses) { ['93.184.215.14', '10.0.0.1'] }

      it 'raises DisallowedUrlError' do
        expect { destination }.to raise_error(described_class::DisallowedUrlError)
      end
    end

    context 'with a host that does not resolve' do
      let(:url) { 'https://push.example.gov' }
      let(:resolved_addresses) { [] }

      it 'raises UnresolvableHostError' do
        expect { destination }.to raise_error(described_class::UnresolvableHostError)
      end
    end

    {
      'http://push.example.gov' => 'scheme must be https',
      'ftp://push.example.gov' => 'not an absolute URL',
      '/relative/path' => 'not an absolute URL',
      'not a url' => 'not a valid URL',
      'https://user:pass@push.example.gov' => 'userinfo is not allowed',
      'https://localhost/push' => 'host is not allowed',
      'https://foo.localhost./push' => 'host is not allowed',
      'https://127.0.0.1:6379' => 'address is not publicly routable',
      'https://[::1]/push' => 'address is not publicly routable',
    }.each do |bad_url, message|
      context "with #{bad_url}" do
        let(:url) { bad_url }

        it 'raises DisallowedUrlError without resolving the host' do
          expect { destination }.to raise_error(described_class::DisallowedUrlError, message)
          expect(resolver).not_to have_received(:getaddresses)
        end
      end
    end

    context 'when internal URLs are allowed' do
      let(:allow_internal) { true }
      let(:url) { 'http://localhost:9292/api/push_notifications' }

      it 'returns the URI without resolving or pinning an address' do
        expect(destination.uri.to_s).to eq(url)
        expect(destination.ip_address).to be_nil
        expect(resolver).not_to have_received(:getaddresses)
      end
    end
  end

  describe '#statically_valid?' do
    it 'accepts public https URLs' do
      expect(described_class.new('https://push.example.gov/risc', allow_internal:))
        .to be_statically_valid
    end

    it 'rejects literal internal addresses and non-https URLs' do
      [
        'https://169.254.169.254/latest',
        'https://10.0.0.1',
        'http://push.example.gov',
        nil,
      ].each do |bad_url|
        expect(described_class.new(bad_url, allow_internal:)).not_to be_statically_valid
      end
    end

    it 'defaults to the risc_notifications_allow_internal_urls config' do
      allow(IdentityConfig.store).to receive(:risc_notifications_allow_internal_urls)
        .and_return(true)

      expect(described_class.new('http://localhost:3001/api/security_events'))
        .to be_statically_valid
    end
  end
end
