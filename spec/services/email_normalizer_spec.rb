require 'rails_helper'

RSpec.describe EmailNormalizer do
  subject(:normalizer) { EmailNormalizer.new(email) }

  describe '#normalized_email' do
    subject(:normalized_email) { normalizer.normalized_email }

    context 'when email is nil' do
      let(:email) { nil }

      it 'is an empty string' do
        expect(normalized_email).to eq(email.to_s)
      end
    end

    context 'with an invalid email' do
      let(:email) { 'invalid_email' }

      it 'is the same string' do
        expect(normalized_email).to eq(email)
      end
    end

    context 'with a non-gmail domain' do
      let(:email) { 'foobar+123@example.com' }

      it 'is the same email' do
        expect(normalized_email).to eq(email)
      end
    end

    context 'with a gmail domain' do
      let(:email) { 'foo.bar+123@gmail.com' }

      it 'removes . and anything after the +' do
        expect(normalized_email).to eq('foobar@gmail.com')
      end
    end

    context 'with a Google Apps domain' do
      let(:email) { 'foo.bar.baz+123@example.com' }
      let(:rails_offline) { false }

      before { stub_const('ENV', 'RAILS_OFFLINE' => (rails_offline ? 'TRUE' : nil)) }

      context 'in offline mode' do
        let(:rails_offline) { true }

        it 'does not make any network requests and assumes non-Google Apps' do
          expect(Resolv::DNS).to_not receive(:open)

          expect(normalized_email).to eq(email)
        end
      end

      context 'with "real DNS" enabled' do
        let(:rails_offline) { false }

        before do
          dns = instance_double(
            'Resolv::DNS',
            getresources: [
              Resolv::DNS::Resource::IN::MX.new(1, Resolv::DNS::Name.new(%w[abcd l google com])),
            ],
          )

          allow(Resolv::DNS).to receive(:open).and_yield(dns)
        end

        it 'still removes . and anything after the +' do
          expect(normalized_email).to eq('foobarbaz@example.com')
        end
      end
    end

    context 'with an internationalized domain name' do
      let(:email) { 'test+1@çà.com' }
      let(:rails_offline) { false }

      before { stub_const('ENV', 'RAILS_OFFLINE' => (rails_offline ? 'TRUE' : nil)) }

      it 'is the same email' do
        expect(normalized_email).to eq(email)
      end
    end
  end

  describe '#rate_limit_email' do
    subject(:rate_limit_email) { normalizer.rate_limit_email }

    context 'when email is nil' do
      let(:email) { nil }

      it 'is an empty string' do
        expect(rate_limit_email).to eq('')
      end
    end

    context 'with an invalid email' do
      let(:email) { 'Invalid_Email' }

      it 'is the downcased string' do
        expect(rate_limit_email).to eq('invalid_email')
      end
    end

    context 'with a non-gmail domain and a +tag' do
      let(:email) { 'Foo.Bar+123@Outlook.com' }

      it 'removes the +tag and downcases but keeps dots' do
        expect(rate_limit_email).to eq('foo.bar@outlook.com')
      end
    end

    context 'with a non-gmail domain and multiple + signs' do
      let(:email) { 'foobar+1+2@example.com' }

      it 'removes everything after the first +' do
        expect(rate_limit_email).to eq('foobar@example.com')
      end
    end

    context 'with a local part that starts with +' do
      let(:email) { '+foobar@example.com' }

      it 'keeps the local part' do
        expect(rate_limit_email).to eq('+foobar@example.com')
      end
    end

    context 'with a gmail domain' do
      let(:email) { 'Foo.Bar+123@gmail.com' }

      it 'removes . and anything after the + and downcases' do
        expect(rate_limit_email).to eq('foobar@gmail.com')
      end
    end

    context 'with an internationalized domain name' do
      let(:email) { 'test+1@çà.com' }

      it 'removes the +tag' do
        expect(rate_limit_email).to eq('test@çà.com')
      end
    end

    it 'does not change #normalized_email for non-gmail domains' do
      expect(EmailNormalizer.new('foobar+123@example.com').normalized_email)
        .to eq('foobar+123@example.com')
    end
  end
end
