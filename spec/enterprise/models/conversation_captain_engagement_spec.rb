require 'rails_helper'

RSpec.describe Conversation, type: :model do
  describe 'Captain engagement activity' do
    let(:account) { create(:account, locale: locale) }
    let(:inbox) { create(:inbox, account: account) }
    let(:contact) { create(:contact, account: account, phone_number: nil) }
    let(:condition) { { 'attribute_key' => 'phone_number', 'filter_operator' => 'contains', 'values' => ['+593'] } }
    let(:assistant) { create(:captain_assistant, account: account, name: 'Aurora', config: { 'audience' => condition }) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    before do
      create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
      allow(assistant).to receive(:paused_reason).and_return(nil)
    end

    %w[es en].each do |language|
      context "with account locale #{language}" do
        let(:locale) { language }
        let(:prefix) do
          language == 'es' ? "Aurora no atendi\u00f3 esta conversaci\u00f3n:" : 'Aurora did not take this conversation:'
        end

        it 'creates one activity at creation and persists the diagnosis' do
          expect(conversation).to be_open
          notes = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'")
          expect(notes.count).to eq(1)
          expect(notes.first.content).to start_with(prefix)
          expect(notes.first.content).to include(language == 'es' ? 'Chat web' : 'Web chat')
          expect(conversation.reload.additional_attributes['captain_skip_reason']).to eq(
            'reason' => 'audience_missing_data', 'condition' => condition
          )
          expect(conversation.messages.outgoing).to be_empty
          expect(conversation.messages.chat).to be_empty
        end

        it 'records one note per reopening and no duplicates on subsequent incoming messages or saves' do
          conversation.resolved!
          create(:message, message_type: :incoming, conversation: conversation)
          create(:message, message_type: :incoming, conversation: conversation)
          conversation.update!(updated_at: Time.current)

          notes = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'")
          expect(conversation.reload).to be_open
          expect(notes.count).to eq(2)
          expect(notes.last.content).to start_with(prefix)
          expect(conversation.messages.outgoing).to be_empty

          conversation.resolved!
          create(:message, message_type: :incoming, conversation: conversation)
          expect(notes.count).to eq(3)
        end

        it 'records a present attribute rejection' do
          contact.update!(phone_number: '+14155552671')

          note = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'").sole
          expect(note.content).to include(language == 'es' ? 'no cumple la regla' : 'does not match the rule')
          expect(note.content).to include('+593')
          expect(conversation.additional_attributes['captain_skip_reason']['reason']).to eq('audience_no_match')
        end

        it 'records a schedule rejection' do
          assistant.update!(config: { 'response_window' => 'business_hours' })
          inbox.update!(working_hours_enabled: true)
          inbox.working_hours.each { |hours| hours.update!(closed_all_day: true) }

          note = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'").sole
          expect(note.content).to include(language == 'es' ? 'fuera de su horario' : 'outside its working hours')
          expect(conversation.additional_attributes['captain_skip_reason']['reason']).to eq('out_of_hours')
        end

        it 'creates no skip activity when Captain accepts the opening' do
          assistant.update!(config: {})

          expect(conversation).to be_pending
          expect(conversation.additional_attributes).not_to have_key('captain_skip_reason')
          expect(conversation.messages.activity).to be_empty
        end

        it 'uses Captain for a legacy assistant without a name' do
          assistant.update_column(:name, '') # rubocop:disable Rails/SkipsModelValidations

          note = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'").sole
          expect(note.content).to start_with('Captain ')
        end

        it 'does not broadcast the activity to the contact' do
          note = conversation.messages.activity.where("additional_attributes ? 'captain_skip_reason'").sole

          expect(ActionCableListener.instance.send(:contact_tokens, conversation.contact_inbox, note)).to be_empty
        end
      end
    end
  end
end
