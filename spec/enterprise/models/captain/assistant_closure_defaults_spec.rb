require 'rails_helper'

RSpec.describe Captain::Assistant, type: :model do
  let(:account) { create(:account) }

  before { account.enable_features!('captain_integration_v2') }

  it 'persists the new defaults only when creating an assistant' do
    assistant = create(:captain_assistant, account: account)

    expect(assistant.reload.inactivity_threshold_minutes).to eq(30)
    expect(assistant.followup.inactivity_after_minutes).to eq(10)
    expect(assistant.followup.max_nudges).to eq(1)
    expect(assistant.send_inactivity_resolution_message?).to be(false)
  end

  it 'keeps an existing assistant with a saved 120 minute timer and its other values' do
    assistant = create(:captain_assistant, account: account, config: {
                         auto_resolve_after: 120, send_inactivity_resolution_message: true,
                         followup: { inactivity_after_minutes: 30, max_nudges: 2 }
                       })
    assistant.update!(description: 'Updated description')

    expect(assistant.reload.inactivity_threshold_minutes).to eq(120)
    expect(assistant.followup.inactivity_after_minutes).to eq(30)
    expect(assistant.followup.max_nudges).to eq(2)
    expect(assistant.send_inactivity_resolution_message?).to be(true)
  end

  it 'keeps historical fallbacks on existing rows without saved keys' do
    assistant = create(:captain_assistant, account: account)
    # Reproduce a pre-existing row that predates the new creation defaults.
    assistant.update_column(:config, { auto_resolve_mode: 'evaluated', send_inactivity_resolution_message: true }) # rubocop:disable Rails/SkipsModelValidations
    assistant.reload.update!(description: 'Updated description')

    expect(assistant.reload.inactivity_threshold_minutes).to eq(60)
    expect(assistant.followup.inactivity_after_minutes).to eq(30)
    expect(assistant.send_inactivity_resolution_message?).to be(true)
    expect(assistant.config).not_to have_key('auto_resolve_after')
  end

  [false, true].each do |enabled|
    it "validates the reminder interval only with active reminders (#{enabled})" do
      assistant = build(:captain_assistant, account: account, config: {
                          auto_resolve_after: 30,
                          followup: { inactivity_enabled: enabled, inactivity_after_minutes: 30 }
                        })

      expect(assistant.valid?).to eq(!enabled)
    end
  end

  it 'accepts an unused reminder interval when the reminder count is zero' do
    assistant = build(:captain_assistant, account: account, config: {
                        auto_resolve_after: 30, followup: { inactivity_after_minutes: 30, max_nudges: 0 }
                      })

    expect(assistant).to be_valid
  end

end
