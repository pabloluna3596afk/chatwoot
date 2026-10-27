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

    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to include(
      'plan[coming_soon]', 'plan[feature_keys][]', 'plan[limit_values][captain_copilot_responses]',
      'plan[limit_values][max_flows]', 'plan[limit_values][trial_days]'
    )
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

  it 'saves optional Copilot and internal AI limits' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: {
      plan: { limit_values: { captain_copilot_responses: '25', captain_internal_calls: '100' } }
    }

    expect(response).to have_http_status(:redirect)
    expect(plan.reload).to have_attributes(captain_copilot_responses: 25, captain_internal_calls: 100)
  end

  it 'creates a plan with limits and preserves all limits when an existing plan is saved unchanged' do
    sign_in(super_admin, scope: :super_admin)
    plan.update!(max_human_agents: 4, limits: { 'max_flows' => 3, 'max_calendars' => 2 })
    plan.reload
    original_attributes = plan.attributes
    submitted_limits = plan.limit_values.transform_values(&:to_s)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { coming_soon: '1', limit_values: submitted_limits } }
    expect(response).to have_http_status(:redirect)
    expect(plan.reload.attributes.except('coming_soon', 'updated_at'))
      .to eq(original_attributes.except('coming_soon', 'updated_at'))

    patch "/super_admin/plans/#{plan.id}", params: { plan: { limit_values: { storage_mb: '' } } }
    expect(response).to have_http_status(:redirect)
    expect(plan.reload.limit(:storage_mb)).to be_nil
    expect(plan.storage_mb).to eq(100)

    post '/super_admin/plans', params: {
      plan: { name: 'New catalog', slug: 'new-catalog', limit_values: { max_flows: '12', max_human_agents: '8' } }
    }
    created = Plan.find_by!(slug: 'new-catalog')
    expect(created.limit(:max_flows)).to eq(12)
    expect(created.limit(:max_human_agents)).to eq(8)
  end

  it 'rejects unknown features' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { feature_keys: ['unknown'] } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(plan.reload.feature_keys).to eq([])
  end

  it 'rejects non-string identifiers without raising an exception' do
    sign_in(super_admin, scope: :super_admin)

    patch "/super_admin/plans/#{plan.id}", params: { plan: { feature_keys: [1] } },
                                           headers: { 'ACCEPT' => 'text/html' }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(plan.reload.feature_keys).to eq([])
  end
end
