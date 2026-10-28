require 'rails_helper'

RSpec.describe 'Super Admin Payphone configuration', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    sign_in(super_admin, scope: :super_admin)
  end

  around do |example|
    with_modified_env FRONTEND_URL: 'https://inbox.example.test' do
      example.run
    end
  end

  it 'shows an empty masked field when a token is already stored' do
    InstallationConfig.create!(name: 'PAYPHONE_TOKEN', value: 'saved-token', locked: false)

    get '/super_admin/app_config?config=payphone'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Token saved; leave blank to keep it')
    expect(response.body).not_to include('saved-token')
  end

  it 'tests the submitted configuration locally without saving or calling Payphone' do
    post '/super_admin/app_config/test?config=payphone', params: {
      app_config: {
        PAYPHONE_STORE_ID: 'store-1', PAYPHONE_TOKEN: 'test-token', PAYPHONE_ENVIRONMENT: 'test',
        PAYPHONE_RESPONSE_URL: 'https://inbox.example.test/payphone/response', PAYPHONE_TAX_RATE: '15',
        PAYPHONE_CARD_COMMISSION_RATE: '5.75', PAYPHONE_GRACE_DAYS: '3'
      }
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Configuration is valid. No payment request was sent.')
    expect(InstallationConfig.find_by(name: 'PAYPHONE_TOKEN')).to be_nil
  end

  it 'uses the saved token when the test form leaves the secret blank' do
    ConfigLoader.new.process
    InstallationConfig.find_by!(name: 'PAYPHONE_TOKEN').update!(value: 'saved-token')
    {
      'PAYPHONE_STORE_ID' => 'store-1', 'PAYPHONE_ENVIRONMENT' => 'production',
      'PAYPHONE_RESPONSE_URL' => 'https://inbox.example.test/payphone/response',
      'PAYPHONE_TAX_RATE' => '15', 'PAYPHONE_CARD_COMMISSION_RATE' => '5.75', 'PAYPHONE_GRACE_DAYS' => '3'
    }.each do |name, value|
      InstallationConfig.find_by!(name: name).update!(value: value)
    end

    post '/super_admin/app_config/test?config=payphone', params: {
      app_config: { PAYPHONE_TOKEN: '', ENABLE_PAYPHONE: 'true' }
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Configuration is valid. No payment request was sent.')
    expect(response.body).not_to include('saved-token')
  end

  it 'rejects a response URL from another domain' do
    post '/super_admin/app_config/test?config=payphone', params: {
      app_config: {
        PAYPHONE_STORE_ID: 'store-1', PAYPHONE_TOKEN: 'test-token', PAYPHONE_ENVIRONMENT: 'production',
        PAYPHONE_RESPONSE_URL: 'https://attacker.example/pay', PAYPHONE_TAX_RATE: '15',
        PAYPHONE_CARD_COMMISSION_RATE: '5.75', PAYPHONE_GRACE_DAYS: '3'
      }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('Response URL domain must match FRONTEND_URL')
  end

  it 'does not save Payphone settings when the response URL is invalid' do
    ConfigLoader.new.process
    current_store_id = InstallationConfig.find_by!(name: 'PAYPHONE_STORE_ID').value

    post '/super_admin/app_config?config=payphone', params: {
      app_config: {
        ENABLE_PAYPHONE: 'true', PAYPHONE_STORE_ID: 'changed-store', PAYPHONE_TOKEN: 'test-token',
        PAYPHONE_ENVIRONMENT: 'test', PAYPHONE_RESPONSE_URL: 'http://inbox.example.test/response',
        PAYPHONE_TAX_RATE: '15', PAYPHONE_CARD_COMMISSION_RATE: '5.75', PAYPHONE_GRACE_DAYS: '3'
      }
    }

    expect(response).to redirect_to(super_admin_app_config_path(config: 'payphone'))
    expect(InstallationConfig.find_by!(name: 'PAYPHONE_STORE_ID').value).to eq(current_store_id)
    expect(flash[:alert]).to include('HTTPS')
  end

  it 'validates production settings locally without contacting Payphone' do
    post '/super_admin/app_config/test?config=payphone', params: {
      app_config: {
        ENABLE_PAYPHONE: 'true', PAYPHONE_STORE_ID: 'store-1', PAYPHONE_TOKEN: 'production-token',
        PAYPHONE_ENVIRONMENT: 'production', PAYPHONE_RESPONSE_URL: 'https://inbox.example.test/payphone/response',
        PAYPHONE_TAX_RATE: '15', PAYPHONE_CARD_COMMISSION_RATE: '5.75', PAYPHONE_GRACE_DAYS: '3'
      }
    }

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Configuration is valid. No payment request was sent.')
  end

  it 'preserves the saved token when the form submits an empty value' do
    ConfigLoader.new.process
    token = InstallationConfig.find_by!(name: 'PAYPHONE_TOKEN')
    token.update!(value: 'saved-token')
    config_values = Payphone::ConfigurationCheck::KEYS.index_with { |key| InstallationConfig.find_by!(name: key).value }

    post '/super_admin/app_config?config=payphone', params: {
      app_config: config_values.merge(
        'PAYPHONE_TOKEN' => '',
        'PAYPHONE_RESPONSE_URL' => 'https://inbox.example.test/payphone/response'
      )
    }

    expect(response).to redirect_to(super_admin_settings_path)
    expect(token.reload.value).to eq('saved-token')
    expect(token.serialized_value['value']).not_to include('saved-token')
  end
end
