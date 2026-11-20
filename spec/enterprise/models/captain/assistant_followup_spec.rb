require 'rails_helper'

RSpec.describe Captain::Assistant, type: :model do
  let(:account) { create(:account, locale: 'es') }
  let(:assistant) { create(:captain_assistant, account: account) }

  def assign(followup)
    assistant.config = assistant.config.merge('followup' => followup)
  end

  it 'has the follow-up defaults when nothing is configured' do
    expect(assistant.followup).to have_attributes(inactivity_enabled?: true, max_nudges: 1, inactivity_after_minutes: 10,
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

  describe 'follow-up inactivity threshold validation' do
    let(:inactive_followup) { { 'inactivity_after_minutes' => 30 } }

    before { account.enable_features('captain_integration_v2') }

    %w[legacy evaluated].each do |mode|
      it "rejects asking at the inactivity threshold in #{mode} mode" do
        assistant.config = assistant.config.merge(
          'auto_resolve_mode' => mode,
          'auto_resolve_after' => 30,
          'followup' => { 'inactivity_after_minutes' => 30 }
        )

        expect(assistant).not_to be_valid
        expect(assistant.errors[:config]).to include('followup inactivity_after_minutes must be shorter than auto_resolve_after')
      end
    end

    it 'allows asking at the inactivity threshold when resolution is disabled' do
      assistant.config = assistant.config.merge(
        'auto_resolve_mode' => 'disabled',
        'auto_resolve_after' => 30,
        'followup' => { 'inactivity_after_minutes' => 30 }
      )

      expect(assistant).to be_valid
    end

    [{ 'inactivity_enabled' => false }, { 'max_nudges' => 0 }].each do |settings|
      it "accepts a five minute closure without active reminders: #{settings.inspect}" do
        assistant.config = assistant.config.merge(
          'auto_resolve_mode' => 'legacy', 'auto_resolve_after' => 5,
          'followup' => inactive_followup.merge(settings)
        )

        expect(assistant).to be_valid
      end
    end
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
      expect(assistant.send(:conversation_prompt_context,
                            state)[:followup]).to eq('continue_text' => 'Sí, sigo aquí', 'stop_text' => 'Ya no, gracias')
    end

    it 'leaves it out when the follow-up is off or sends no nudges' do
      assign('inactivity_enabled' => false)
      expect(assistant.send(:conversation_prompt_context, state)).not_to have_key(:followup)

      assign('max_nudges' => 0)
      expect(assistant.send(:conversation_prompt_context, state)).not_to have_key(:followup)
    end
  end
end
