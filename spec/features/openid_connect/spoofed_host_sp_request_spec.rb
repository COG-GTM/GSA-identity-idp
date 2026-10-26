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
end
