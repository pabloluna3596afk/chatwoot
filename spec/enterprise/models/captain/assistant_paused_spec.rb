require 'rails_helper'

RSpec.describe Captain::Assistant, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:contact) { create(:contact, account: account) }

  # Enterprise specs stub the key as present; these examples exercise the real check.
  def remove_installation_key
    allow(Llm::Config).to receive(:api_key_configured?).and_call_original
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
  end

  def exhaust_responses
    allow(assistant.account).to receive(:usage_limits)
      .and_return(captain: { responses: { current_available: 0 } })
  end

  describe '#paused_reason' do
    it 'is nil when the installation has a key and the account has responses left' do
      expect(assistant.paused_reason).to be_nil
    end

    it 'is :missing_key when the installation has no AI key' do
      remove_installation_key

      expect(assistant.paused_reason).to eq(:missing_key)
    end

    it 'is :quota_exhausted when the account has no responses left' do
      exhaust_responses

      expect(assistant.paused_reason).to eq(:quota_exhausted)
    end

    it 'reports the missing key before the quota' do
      remove_installation_key
      exhaust_responses

      expect(assistant.paused_reason).to eq(:missing_key)
    end

    it 'notices a key saved later, without a restart' do
      remove_installation_key
      expect(assistant.paused_reason).to eq(:missing_key)

      create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'sk-test')

      expect(assistant.paused_reason).to be_nil
    end
  end

  describe 'inbox engagement' do
    before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

    it 'is active and takes new conversations when Captain can answer' do
      expect(inbox.captain_active?).to be(true)
      expect(create(:conversation, account: account, inbox: inbox, contact: contact).status).to eq('pending')
    end

    it 'is not active and sends new conversations to the human queue when the key is missing' do
      remove_installation_key

      expect(inbox.reload.captain_active?).to be(false)
      expect(inbox.captain_paused_reason).to eq(:missing_key)
      expect(create(:conversation, account: account, inbox: inbox, contact: contact).status).to eq('open')
    end

    it 'does not take a conversation either when the account has no responses left' do
      put_account_on_plan(account, monthly_messages: 100, used: 100)

      expect(create(:conversation, account: account, inbox: inbox, contact: contact).status).to eq('open')
    end

    it 'has no paused reason when the inbox has no assistant' do
      expect(create(:inbox, account: account).captain_paused_reason).to be_nil
    end
  end
end
