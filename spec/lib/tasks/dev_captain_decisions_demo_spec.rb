require 'rails_helper'

RSpec.describe 'dev:captain_decisions_demo' do # rubocop:disable RSpec/DescribeClass -- named Rake entry point
  let(:task) { Rake::Task['dev:captain_decisions_demo'] }
  let(:account) { create(:account) }

  it 'creates isolated, idempotent fictional decisions without enqueuing delivery or AI jobs', :aggregate_failures do
    create(:user, account: account, role: :administrator)
    clear_enqueued_jobs
    with_modified_env ACCOUNT_ID: account.id.to_s do
      expect { task.execute }.to output(/Fictional demo:.*conversations/).to_stdout
      conversation = account.conversations.sole
      expect(conversation.messages.count).to eq(10)
      expect(account.captain_decisions.count).to eq(6)
      expect(conversation.messages.where(private: true).sole.content_attributes).to have_key('captain_handoff')
      expect(conversation.messages.activity.count).to eq(7)
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:reply').content).to eq('We are open from 09:00 to 18:00')
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:human_assignment').content)
        .to eq('Maria assigned this conversation to Alex Rivera')
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:human_assignment')
        .content_attributes.dig('activity', 'names')).to eq(['Maria', 'Alex Rivera'])
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:team_assignment')
        .content_attributes.dig('activity', 'names')).to eq(['Maria', 'Support'])
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:label_added').content)
        .to eq('Maria added the label priority')
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:label_added')
        .content_attributes.dig('activity', 'names')).to eq(['Maria', 'priority'])
      expect(account.captain_decisions.find_by!(decision_key: 'captain-decisions-demo-v1:evaluation')
        .anchor_message.content_attributes.dig('activity', 'names')).to eq(['Captain'])
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:automation')
        .content_attributes.dig('messageSource', 'type')).to eq('automation')
      expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:automation')
        .content_attributes.dig('activity', 'names')).to eq(['Automation'])
      expect(conversation.contact.name).to eq('Alex Rivera')
      expect(account.captain_decisions.find_by!(decision_key: 'captain-decisions-demo-v1:evaluation').reason_text)
        .to eq('No pending questions were detected.')
      expect(account.captain_decisions.where("technical_details ->> 'credits_consumed' = '0'").count).to eq(3)
      expect(account.captain_decisions.where(technical_details: {}).count).to eq(2)
      expect { task.execute }.to output(/Fictional demo/).to_stdout
      expect(account.conversations.count).to eq(1)
      expect(conversation.messages.count).to eq(10)
      expect(account.captain_decisions.count).to eq(6)
      expect(conversation.messages.pluck(:content)).to all(satisfy { |content| !content.end_with?('.') })
      expect(enqueued_jobs).to be_empty
    end
  end

  it 'localizes fictional demo messages and decision reasons for a Spanish account' do
    account.update!(locale: 'es')
    with_modified_env ACCOUNT_ID: account.id.to_s do
      expect { task.execute }.to output(/Fictional demo/).to_stdout
    end

    conversation = account.conversations.sole
    expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:reply').content)
      .to eq('Atendemos de 09:00 a 18:00')
    expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:handoff').content)
      .to eq('El cliente pidió hablar con una persona')
    expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:human_assignment').content)
      .to eq('Maria asignó esta conversación a Alex Rivera')
    expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:label_added').content)
      .to eq('Maria añadió la etiqueta priority')
    expect(conversation.messages.find_by!(source_id: 'captain-decisions-demo-v1:activity:automation').content)
      .to eq('La automatización marcó esta conversación como pendiente')
    expect(conversation.messages.pluck(:content)).to all(satisfy { |content| !content.end_with?('.') })
    decision = account.captain_decisions.find_by!(decision_key: 'captain-decisions-demo-v1:evaluation')
    expect(decision.reason_text).to eq('No se detectaron preguntas pendientes.')
    expect(decision.reason_locale).to eq('es')
    expect(conversation.messages.pluck(:content).grep(/\ADemo:/)).to be_empty
  end

  it 'aborts in production before reading an account' do
    allow(Rails.env).to receive(:production?).and_return(true)
    expect(Account).not_to receive(:find)
    expect { task.execute }.to raise_error(SystemExit, /disabled in production/).and output(/disabled in production/).to_stderr
  end
end
