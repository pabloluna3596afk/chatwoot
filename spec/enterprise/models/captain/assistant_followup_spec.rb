require 'rails_helper'

RSpec.describe Captain::FollowupSettings do
  describe '.normalize' do
    it 'returns the defaults: inactivity on, one nudge after 30 minutes, close after 120, re-engagement off' do
      expect(described_class.normalize(nil)).to eq(
        'inactivity_enabled' => true, 'inactivity_after_minutes' => 30, 'max_nudges' => 1, 'close_after_minutes' => 120,
        'reengagement_enabled' => false, 'reengagement_template' => nil
      )
    end

    it 'casts strings, drops unknown keys and keeps only name and language of a template' do
      result = described_class.normalize(
        'inactivity_enabled' => 'false', 'inactivity_after_minutes' => '45', 'max_nudges' => '2', 'close_after_minutes' => 60,
        'reengagement_enabled' => 'true', 'reengagement_template' => { 'name' => 'volver', 'language' => 'es', 'extra' => 'x' }, 'other' => 1
      )

      expect(result).to eq(
        'inactivity_enabled' => false, 'inactivity_after_minutes' => 45, 'max_nudges' => 2, 'close_after_minutes' => 60,
        'reengagement_enabled' => true, 'reengagement_template' => { 'name' => 'volver', 'language' => 'es' }
      )
    end

    it 'reads "no" as off, not as true' do
      expect(described_class.normalize('inactivity_enabled' => 'no')['inactivity_enabled']).to be(false)
    end

    it 'keeps values that are not numbers so the validator can reject them' do
      expect(described_class.normalize('max_nudges' => 'many')['max_nudges']).to eq('many')
    end
  end
end

RSpec.describe Captain::Assistant, 'follow-up settings', type: :model do
  let(:account) { create(:account, locale: 'es') }
  let(:assistant) { create(:captain_assistant, account: account) }

  def assign(followup)
    assistant.config = assistant.config.merge('followup' => followup)
  end

  it 'has the follow-up defaults when nothing is configured' do
    expect(assistant.followup).to have_attributes(inactivity_enabled?: true, max_nudges: 1, inactivity_after_minutes: 30,
                                                  close_after_minutes: 120, reengagement_enabled?: false)
  end

  it 'accepts a valid configuration and normalizes it' do
    assign('max_nudges' => '2', 'inactivity_after_minutes' => '15')

    expect(assistant).to be_valid
    expect(assistant.config['followup']).to include('max_nudges' => 2, 'inactivity_after_minutes' => 15)
  end

  it 'accepts zero nudges' do
    assign('max_nudges' => 0)

    expect(assistant).to be_valid
  end

  it 'rejects numbers out of range' do
    { 'max_nudges' => 3, 'inactivity_after_minutes' => 4, 'close_after_minutes' => 1441 }.each do |key, value|
      assign(key => value)

      expect(assistant).not_to be_valid, "#{key} #{value} should be invalid"
    end
  end

  it 'rejects a template without a language and a followup that is not an object' do
    assign('reengagement_template' => { 'name' => 'volver' })
    expect(assistant).not_to be_valid

    assign('yes')
    expect(assistant).not_to be_valid
  end

  describe 'paid templates' do
    it 'are off unless the owner turned them on' do
      expect(assistant).not_to be_allow_paid_templates
    end

    it 'are on only for a real true' do
      assistant.config = assistant.config.merge('allow_paid_templates' => true)

      expect(assistant).to be_allow_paid_templates
    end

    it 'rejects a value that is not true or false' do
      assistant.config = assistant.config.merge('allow_paid_templates' => 'yes')

      expect(assistant).not_to be_valid
    end
  end

  describe 'prompt context' do
    let(:inbox) { create(:inbox, account: account) }
    let(:state) { { conversation: { inbox_id: inbox.id } } }

    before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

    it 'tells the model the texts of the follow-up buttons in the account language' do
      expect(assistant.send(:conversation_prompt_context, state)[:followup]).to eq('continue_text' => 'Sí, sigo aquí', 'stop_text' => 'Ya no, gracias')
    end

    it 'leaves it out when the follow-up is off or sends no nudges' do
      assign('inactivity_enabled' => false)
      expect(assistant.send(:conversation_prompt_context, state)).not_to have_key(:followup)

      assign('max_nudges' => 0)
      expect(assistant.send(:conversation_prompt_context, state)).not_to have_key(:followup)
    end
  end
end

RSpec.describe 'Api::V1::Accounts::Captain::Assistants follow-up settings', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/captain/assistants/#{assistant.id}" }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  it 'returns the follow-up defaults and paid templates off' do
    get url, headers: admin.create_new_auth_token, as: :json

    expect(json_response[:config][:followup]).to eq(
      inactivity_enabled: true, inactivity_after_minutes: 30, max_nudges: 1, close_after_minutes: 120,
      reengagement_enabled: false, reengagement_template: nil
    )
    expect(json_response[:config][:allow_paid_templates]).to be(false)
  end

  it 'saves the follow-up settings and the one paid templates switch' do
    followup = { inactivity_enabled: false, inactivity_after_minutes: 45, max_nudges: 2, close_after_minutes: 240,
                 reengagement_enabled: true, reengagement_template: { name: 'volver', language: 'es' } }

    patch url, params: { assistant: { config: { followup: followup, allow_paid_templates: true } } },
          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(json_response[:config][:followup]).to eq(followup)
    expect(json_response[:config][:allow_paid_templates]).to be(true)
    expect(assistant.reload).to be_allow_paid_templates
  end

  it 'rejects invalid follow-up settings' do
    patch url, params: { assistant: { config: { followup: { max_nudges: 5 } } } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps the paid templates switch when another form saves the config it received' do
    assistant.update!(config: assistant.config.merge('allow_paid_templates' => true))
    get url, headers: admin.create_new_auth_token, as: :json
    received = json_response[:config]

    patch url, params: { assistant: { config: received.merge(response_window: 'always') } }, headers: admin.create_new_auth_token, as: :json

    expect(assistant.reload).to be_allow_paid_templates
  end
end
