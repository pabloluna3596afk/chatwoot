require 'rails_helper'

RSpec.describe 'Super Admin extra credits', type: :request do
  let(:admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:pack) { ExtraPack.create!(bucket: :internal, units: 500, price_usd: 6) }

  it 'requires Super Admin authentication for both writes' do
    patch "/super_admin/extra_packs/#{pack.id}", params: { extra_pack: { price_usd: 10 } }
    expect(response).to have_http_status(:redirect)
    expect(pack.reload.price_usd).to eq(6)
    post '/super_admin/account_extra_balances', params: { account_extra_balance: { account_id: account.id, bucket: 'internal', units_total: '50' } }
    expect(response).to have_http_status(:redirect)
    expect(account.account_extra_balances.count).to eq(0)
  end

  it 'creates, edits, lists and deletes an unused pack' do
    sign_in(admin, scope: :super_admin)
    post '/super_admin/extra_packs', params: { extra_pack: { bucket: 'internal', units: 500, price_usd: 6, active: true } }
    expect(response).to have_http_status(:redirect)
    created = ExtraPack.find_by!(bucket: :internal, units: 500)
    patch "/super_admin/extra_packs/#{created.id}", params: { extra_pack: { price_usd: '7', active: '0' } }
    expect(created.reload).to have_attributes(price_usd: 7, active: false)
    get '/super_admin/extra_packs'
    expect(response).to have_http_status(:ok)
    get "/super_admin/extra_packs/#{created.id}/edit"
    expect(response.body).to include('extra_pack[price_usd]')
    delete "/super_admin/extra_packs/#{created.id}"
    expect(ExtraPack.exists?(created.id)).to be(false)
  end

  it 'grants courtesy units with a server-owned source and expiration and displays them on the account' do
    sign_in(admin, scope: :super_admin)
    travel_to(Time.current.change(usec: 0)) do
      get "/super_admin/account_extra_balances/new?account_id=#{account.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('account_extra_balance[units_total]')
      post '/super_admin/account_extra_balances', params: {
        account_extra_balance: { account_id: account.id, bucket: 'internal', units_total: '50', source: 'purchase', units_remaining: 999 }
      }
      expect(response).to have_http_status(:redirect)
      balance = account.account_extra_balances.sole
      expect(balance).to have_attributes(source: 'courtesy', units_remaining: 50, expires_at: 90.days.from_now)
      get "/super_admin/accounts/#{account.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Grant courtesy units', '50 / 50')
      get "/super_admin/account_extra_balances/#{balance.id}"
      expect(response).to have_http_status(:ok)
    end
  end

  it 'rejects unsupported buckets and malformed courtesy amounts' do
    sign_in(admin, scope: :super_admin)
    ['-1', '1.5', '1junk', '0'].each do |units|
      post '/super_admin/account_extra_balances', params: { account_extra_balance: { account_id: account.id, bucket: 'internal', units_total: units } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post '/super_admin/account_extra_balances', params: { account_extra_balance: { account_id: account.id, bucket: 'other', units_total: '1' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.account_extra_balances.count).to eq(0)
  end

  it 'edits all monthly add-on prices through the plan form' do
    sign_in(admin, scope: :super_admin)
    plan = Plan.create!(name: 'Extras', slug: 'extras')
    patch "/super_admin/plans/#{plan.id}", params: {
      plan: { addon_inbox_price: '13', addon_storage_100mb_price: '2', addon_storage_250mb_price: '3' }
    }
    expect(response).to have_http_status(:redirect)
    expect(plan.reload).to have_attributes(addon_inbox_price: 13, addon_storage_100mb_price: 2, addon_storage_250mb_price: 3)
    get "/super_admin/plans/#{plan.id}/edit"
    expect(response.body).to include('plan[addon_inbox_price]', 'plan[addon_storage_100mb_price]', 'plan[addon_storage_250mb_price]')
  end
end
