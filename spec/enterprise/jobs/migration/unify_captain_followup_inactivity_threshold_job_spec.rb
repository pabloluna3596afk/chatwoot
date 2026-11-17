require 'rails_helper'

RSpec.describe Migration::UnifyCaptainFollowupInactivityThresholdJob, type: :job do
  it 'copies the saved follow-up close delay to the assistant timer and is idempotent' do
    account = create(:account)
    config = {
      'auto_resolve_after' => 60,
      'followup' => { 'inactivity_enabled' => true, 'max_nudges' => 1, 'close_after_minutes' => 120 }
    }
    assistant = create(:captain_assistant, account: account, config: config)

    described_class.perform_now
    expect(assistant.reload.config['auto_resolve_after']).to eq(120)

    described_class.perform_now
    expect(assistant.reload.config['auto_resolve_after']).to eq(120)
  end

  it 'leaves assistants without active nudges unchanged' do
    account = create(:account)
    disabled_config = {
      'auto_resolve_after' => 60,
      'followup' => { 'inactivity_enabled' => false, 'close_after_minutes' => 120 }
    }
    zero_nudges_config = {
      'auto_resolve_after' => 60,
      'followup' => { 'inactivity_enabled' => true, 'max_nudges' => 0, 'close_after_minutes' => 120 }
    }
    assistants = [
      create(:captain_assistant, account: account, config: disabled_config),
      create(:captain_assistant, account: account, config: zero_nudges_config),
      create(:captain_assistant, account: account, config: { 'auto_resolve_after' => 60 })
    ]

    described_class.perform_now

    expect(assistants.map { |assistant| assistant.reload.config['auto_resolve_after'] }).to all(eq(60))
  end
end
