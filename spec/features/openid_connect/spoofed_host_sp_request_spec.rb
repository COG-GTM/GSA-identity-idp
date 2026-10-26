require 'rails_helper'

RSpec.feature 'OIDC request created with a spoofed Host header' do
  include OidcAuthHelper

  it 'does not redirect a newly registered user to the spoofed host' do
    Capybara.using_session(:attacker) do
      page.driver.header('Host', 'evil.example')
      visit_idp_from_ial1_oidc_sp
    end
    sp_request = ServiceProviderRequestProxy.last
    expect(URI(sp_request.url).host).to eq(IdentityConfig.store.domain_name)

    visit root_path(request_id: sp_request.uuid)
    sign_up_and_set_password
    select_2fa_option('backup_code')
    click_continue
    expect(page).to have_current_path(sign_up_completed_path)

    allow(page.driver).to receive(:follow_redirects?).and_return(false)
    click_agree_and_continue

    location = URI(page.driver.response.headers['Location'])
    expect(location.host).to eq(IdentityConfig.store.domain_name)
    expect(location.path).to eq(openid_connect_authorize_path)
  end

  it 'sends an existing user with a previously stored foreign-host request to their account' do
    user = create(:user, :fully_registered)
    sp_request = ServiceProviderRequestProxy.create(
      uuid: SecureRandom.uuid,
      issuer: OidcAuthHelper::OIDC_IAL1_ISSUER,
      url: 'https://evil.example/openid_connect/authorize?client_id=x',
      requested_attributes: ['email'],
      acr_values: Saml::Idp::Constants::IAL1_AUTHN_CONTEXT_CLASSREF,
    )

    visit root_path(request_id: sp_request.uuid)
    fill_in_credentials_and_submit(user.email, user.password)
    fill_in_code_with_last_phone_otp
    click_submit_default
    click_agree_and_continue_optional

    expect(page).to have_current_path(account_path)
  end
end
