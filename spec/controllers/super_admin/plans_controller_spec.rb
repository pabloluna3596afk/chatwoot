require 'rails_helper'

RSpec.describe 'Super Admin plans', type: :request do
  let(:plan) { Plan.create!(name: 'Catalog', slug: 'catalog') }
  let(:super_admin) { create(:super_admin) }

  it 'requires a Super Admin session' do
    patch "/super_admin/plans/#{plan.id}", params: { plan: { coming_soon: true } }

    expect(response).to have_http_status(:redirect)
    expect(plan.reload.coming_soon).to be(false)
  end

  it 'renders catalog controls in the edit form' do
    sign_in(super_admin, scope: :super_admin)
    get "/super_admin/plans/#{plan.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('plan[coming_soon]', 'plan[feature_keys][]')
  end

  it 'edits availability and features without changing account flags' do
    account = create(:account, plan: plan)
    original_flags = account.attributes.slice('feature_flags', 'feature_flags_ext_1')
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { coming_soon: '1', feature_keys: ['', 'automations'] } }

    expect(response).to have_http_status(:redirect)
    expect(plan.reload).to have_attributes(coming_soon: true, feature_keys: ['automations'])
    expect(account.reload.attributes.slice('feature_flags', 'feature_flags_ext_1')).to eq(original_flags)
  end

  it 'clears all features using the checkbox sentinel' do
    plan.update!(feature_keys: ['automations'])
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { feature_keys: [''] } }

    expect(response).to have_http_status(:redirect)
    expect(plan.reload.feature_keys).to eq([])
  end

  it 'rejects unknown features' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { feature_keys: ['unknown'] } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(plan.reload.feature_keys).to eq([])
  end

  it 'rejects non-string identifiers without raising an exception' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { feature_keys: [1] } }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(plan.reload.feature_keys).to eq([])
  end

end
