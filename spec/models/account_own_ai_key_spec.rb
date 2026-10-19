require 'rails_helper'

RSpec.describe Account do
  let(:account) { create(:account) }

  it 'has no own key by default' do
    expect(account.own_ai_key_configured?).to be(false)
  end

  it 'uses only an enabled OpenAI hook with a nonempty key' do
    hook = build(:integrations_hook, :openai, account: account)
    hook.save!(validate: false)
    expect(account.own_ai_key_configured?).to be(true)
    expect(account.own_ai_key).to eq('api_key')
    hook.update_columns(status: Integrations::Hook.statuses[:disabled]) # rubocop:disable Rails/SkipsModelValidations
    expect(account.own_ai_key_configured?).to be(false)
  end

  it 'does not treat an empty hook key as configured' do
    hook = build(:integrations_hook, :openai, account: account, settings: { api_key: '' })
    hook.save!(validate: false)
    expect(account.own_ai_key_configured?).to be(false)
  end
end
