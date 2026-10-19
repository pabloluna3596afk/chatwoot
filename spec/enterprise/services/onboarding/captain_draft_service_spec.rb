require 'rails_helper'

RSpec.describe Onboarding::CaptainDraftService do
  let(:plan) { Plan.create!(name: 'Trial', slug: 'onboarding-draft-trial', max_captain_assistants: 1, max_inboxes: 1) }
  let(:account) do
    create(:account, plan: plan, locale: 'es', custom_attributes: {
             'onboarding_version' => 2, 'onboarding_step' => 'assistant', 'business_type' => 'appointments'
           })
  end
  let(:attributes) { { name: 'Asistente de Acme', goal: 'Ayuda a solicitar una cita', tone: 'friendly' } }
  let(:service) { described_class.new(account: account, **attributes) }

  it 'creates one local draft with no inboxes and no AI calls' do
    expect(Captain::Assistant::AgentRunnerService).not_to receive(:new)
    expect(Llm::Config).not_to receive(:api_key_configured?)

    assistant = service.perform

    expect(account.reload.custom_attributes['onboarding_assistant_id']).to eq(assistant.id)
    expect(assistant.inboxes).to be_empty
    expect(assistant.description).to eq(attributes[:goal])
  end

  it 'uses the reviewed Spanish guidance and disables automation on the draft' do
    assistant = service.perform

    expect(assistant.response_guidelines.join(' ')).to include(attributes[:goal], 'es', 'No confirmes reservas', 'tono cercano')
    expect(assistant.guardrails.join(' ')).to include('No inventes precios')
    expect(assistant.config).to include('auto_resolve_mode' => 'disabled', 'allow_paid_templates' => false)
    expect(assistant.appointments.enabled?).to be(false)
    expect(assistant.followup.inactivity_enabled?).to be(false)
    expect(assistant.followup.reengagement_enabled?).to be(false)
  end

  it 'reuses the same draft across separate requests, including when the plan is full' do
    first = service.perform
    second = described_class.new(account: Account.find(account.id), **attributes).perform

    expect(second.id).to eq(first.id)
    expect(account.captain_assistants.count).to eq(1)
  end

  it 'updates the draft in place when the owner keeps editing' do
    first = service.perform
    updated = described_class.new(account: account, **attributes.merge(name: 'Nuevo nombre', goal: 'Nuevo objetivo', tone: 'brief')).perform

    expect(updated.id).to eq(first.id)
    expect(updated.name).to eq('Nuevo nombre')
    expect(updated.config['onboarding']).to eq('goal' => 'Nuevo objetivo', 'tone' => 'brief')
    expect(updated.response_guidelines.join(' ')).to include('Nuevo objetivo', 'tono breve')
    expect(account.captain_assistants.count).to eq(1)
  end

  it 'respects an existing assistant and the trial limit instead of claiming or duplicating it' do
    existing = create(:captain_assistant, account: account)

    expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('Captain::Assistant::LimitExceededError') })
    expect(account.reload.custom_attributes).not_to have_key('onboarding_assistant_id')
    expect(account.captain_assistants.pluck(:id)).to eq([existing.id])
  end

  it 'rolls back creation if saving the pointer fails' do
    allow(account).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(account))

    expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.captain_assistants.count).to eq(0)
    expect(account.reload.custom_attributes).not_to have_key('onboarding_assistant_id')
  end

  it 'never uses an assistant belonging to another account' do
    other = create(:captain_assistant)
    account.update!(custom_attributes: account.custom_attributes.merge('onboarding_assistant_id' => other.id))

    expect { service.perform }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.captain_assistants.count).to eq(0)
    expect(other.reload.name).not_to eq(attributes[:name])
  end

  it 'does not overwrite an activated assistant on replay' do
    assistant = service.perform
    assistant.captain_inboxes.create!(inbox: create(:inbox, account: account))

    updated = described_class.new(account: account, **attributes.merge(name: 'Stale name')).perform

    expect(updated.name).to eq(attributes[:name])
    expect(updated.captain_inboxes.count).to eq(1)
  end

  it 'does not provision outside the version 2 assistant step' do
    account.update!(custom_attributes: { 'onboarding_step' => 'inbox_setup' })

    expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('Onboarding::CaptainDraftService::Unavailable') })
    expect(account.captain_assistants.count).to eq(0)
  end

  it 'requires the Captain features at the shared entry point' do
    account.disable_features!('captain_integration_v2')

    expect { service.perform }.to(raise_error { |error| expect(error.class.name).to eq('Onboarding::CaptainDraftService::Unavailable') })
    expect(account.captain_assistants.count).to eq(0)
  end

  it 'keeps the short description valid without truncating the full goal' do
    long_goal = 'a' * 2000
    assistant = described_class.new(account: account, **attributes.merge(goal: long_goal)).perform

    expect(assistant.description.length).to eq(Captain::Assistant::DESCRIPTION_LENGTH_LIMIT)
    expect(assistant.response_guidelines.join).to include(long_goal)
  end

  %w[appointments commerce services other].each do |business_type|
    it "uses the reviewed #{business_type} template" do
      account.update!(custom_attributes: account.custom_attributes.merge('business_type' => business_type))
      assistant = service.perform

      expect(assistant.response_guidelines.first).to eq(Onboarding::CaptainDraftTemplates::BUSINESS_INSTRUCTIONS.fetch(business_type))
    end
  end
end
