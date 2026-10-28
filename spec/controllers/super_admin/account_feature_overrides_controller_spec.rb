require 'rails_helper'

RSpec.describe 'Super Admin account feature overrides', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:plan) { Plan.create!(name: 'Feature plan', slug: 'feature-plan', feature_keys: ['automations']) }
  let(:account) { create(:account, plan: plan) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'creates an account-scoped feature exception with reason and expiry' do
    post "/super_admin/accounts/#{account.id}/feature_override", params: {
      feature_key: 'automations', enabled: 'false', reason: 'Customer request', expires_at: '2026-12-01'
    }

    expect(response).to have_http_status(:redirect)
    expect(account.account_feature_overrides.sole).to have_attributes(
      enabled: false, reason: 'Customer request', created_by_id: super_admin.id
    )
  end

  it 'rejects unknown features and malformed enabled values' do
    post "/super_admin/accounts/#{account.id}/feature_override", params: {
      feature_key: 'unknown', enabled: 'true', reason: 'Invalid key'
    }
    expect(response).to have_http_status(:unprocessable_entity)

    post "/super_admin/accounts/#{account.id}/feature_override", params: {
      feature_key: 'automations', enabled: 'yes', reason: 'Invalid value'
    }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'deletes only the exception belonging to the requested account' do
    other_account = create(:account, plan: plan)
    override = AccountFeatureOverride.create!(account: other_account, created_by: super_admin,
                                              feature_key: 'automations', enabled: false, reason: 'Scoped')

    delete "/super_admin/accounts/#{account.id}/feature_override", params: { feature_key: 'automations' }

    expect(response).to have_http_status(:not_found)
    expect(override.reload).to be_present
  end
end
