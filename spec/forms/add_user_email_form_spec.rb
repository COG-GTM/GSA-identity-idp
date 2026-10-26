require 'rails_helper'

RSpec.describe AddUserEmailForm do
  subject(:form) { AddUserEmailForm.new }

  let(:original_email) { 'original@example.com' }
  let(:user) { User.create(email: original_email) }

  describe '#submit' do
    let(:new_email) { 'new@example.com' }
    let(:request_id) { 'request-id-1' }

    subject(:submit) { form.submit(user, email: new_email, request_id:) }

    it 'returns a successful result' do
      expect(submit.to_h).to eq(
        success: true,
        domain_name: 'example.com',
        in_select_email_flow: false,
        user_id: user.uuid,
      )
    end

    it 'creates a new EmailAddress record for a new email address' do
      expect(EmailAddress.find_with_email(new_email)).to be_nil

      response = submit
      expect(response.success?).to eq(true)

      email_address_record = EmailAddress.find_with_email(new_email)
      expect(email_address_record).to be_present
      expect(email_address_record.confirmed_at).to be_nil
    end

    context 'when the new email address has an expired previous attempt for the same account' do
      before do
        create(
          :email_address,
          email: new_email,
          user: user,
          confirmed_at: nil,
          confirmation_sent_at: 1.month.ago,
        )
      end

      it 'sends a confirmation email, as if it was not previously linked' do
        expect(SendAddEmailConfirmation).to receive(:new).and_call_original

        response = submit
        expect(response.success?).to eq(true)
      end
    end

    context 'when the domain is invalid' do
      let(:new_email) { 'test@çà.com' }

      it 'fails and does not send a confirmation email' do
        expect(SendAddEmailConfirmation).to_not receive(:new)

        response = submit
        expect(response.success?).to eq(false)
      end
    end

    context 'banned domains' do
      before do
        expect(BanDisposableEmailValidator).to receive(:config).and_return(%w[spamdomain.com])
      end

      context 'with the banned domain' do
        let(:new_email) { 'test@spamdomain.com' }

        it 'fails and does not send a confirmation email' do
          expect(SendAddEmailConfirmation).to_not receive(:new)

          response = submit
          expect(response.success?).to eq(false)
        end
      end

      context 'with a subdomain of the banned domain' do
        let(:new_email) { 'test@abc.def.spamdomain.com' }

        it 'fails and does not send a confirmation email' do
          expect(SendAddEmailConfirmation).to_not receive(:new)

          response = submit
          expect(response.success?).to eq(false)
        end
      end
    end

    context 'when the recipient has hit the add email rate limit' do
      before do
        IdentityConfig.store.add_email_per_recipient_max_attempts.times do
          AddEmailRateLimiter.new(user: create(:user), email: new_email).attempt!
        end
      end

      it 'fails with a rate limit error and does not send or save' do
        expect(SendAddEmailConfirmation).to_not receive(:new)

        response = submit

        expect(response.success?).to eq(false)
        expect(form.errors.details[:email]).to include(error: :rate_limited)
        expect(form.rate_limiter.rate_limit_type).to eq(:add_email_per_recipient)
        expect(EmailAddress.find_with_email(new_email)).to be_nil
      end
    end

    context 'when re-adding the same unconfirmed address repeatedly' do
      it 'stops sending once the per-recipient limit is reached' do
        max = IdentityConfig.store.add_email_per_recipient_max_attempts

        results = (max + 2).times.map { AddUserEmailForm.new.submit(user, email: new_email) }

        expect(results.count(&:success?)).to eq(max)
        expect(results.last(2).map(&:success?)).to eq([false, false])
      end
    end

    context 'in select email flow' do
      subject(:form) { AddUserEmailForm.new(in_select_email_flow: true) }

      it 'sends email confirm with parameter value' do
        send_add_email_confirmation = instance_double(SendAddEmailConfirmation)
        expect(SendAddEmailConfirmation).to receive(:new).and_return(send_add_email_confirmation)
        expect(send_add_email_confirmation).to receive(:call).with(
          email_address: kind_of(EmailAddress),
          in_select_email_flow: true,
          request_id:,
        )

        submit
      end

      it 'includes extra analytics in result for flow value' do
        expect(submit.to_h).to eq(
          success: true,
          domain_name: 'example.com',
          in_select_email_flow: true,
          user_id: user.uuid,
        )
      end
    end
  end
end
