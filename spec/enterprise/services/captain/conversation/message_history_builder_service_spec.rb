require 'rails_helper'

RSpec.describe Captain::Conversation::MessageHistoryBuilderService do
  let(:account) { create(:account, locale: 'en') }
  let(:conversation) { create(:conversation, account: account) }

  describe 'pilot context' do
    subject(:history) { described_class.new(conversation: conversation).perform }

    let(:attributes) do
      { account_id: account.id, inbox_id: conversation.inbox_id, conversation_id: conversation.id, private: false,
        message_type: :incoming, content: 'Customer message', created_at: 1.hour.ago, updated_at: 1.hour.ago }
    end

    it 'builds the full history on a non-pilot account' do
      Message.create!([attributes] * 300)

      expect(history).to eq([{ role: 'user', content: 'Customer message' }] * 300)
    end

    context 'with a pilot account' do
      before { account.enable_features!('captain_pilot') }

      it 'builds the windowed history on a pilot account' do
        Message.create!([attributes] * 300)

        expect(history).to eq([{ role: 'user', content: 'Customer message' }] * 40)
      end

      it 'replaces older images with the placeholder on a pilot account' do
        Message.create!([attributes] * 6)
        conversation.messages.order(:id).each do |message|
          message.attachments.create!(account_id: account.id, file_type: :image, external_url: "https://example.com/#{message.id}.jpg")
        end

        expect(history.first(3).map { |entry| entry[:content].last }).to eq(
          [{ type: 'text', text: '[Image sent earlier, not shown again]' }] * 3
        )
        expect(history.last(3).map { |entry| entry[:content].last[:type] }).to eq(['image_url'] * 3)
      end

      it 'prefixes human agent messages on a pilot account' do
        message = create(:message, conversation: conversation, account: account, message_type: :outgoing,
                                   content: 'Confirmed', additional_attributes: { agent_name: 'Sales' })

        expect(history).to eq([{ role: 'assistant', content: '[Human agent]: Confirmed', agent_name: 'Sales' }])
        expect(message.reload.content).to eq('Confirmed')
      end

      it 'prefixes the first text part of multimodal human messages' do
        message = create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'Photo')
        message.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://example.com/photo.jpg')

        expect(history.first[:content].first).to eq(type: 'text', text: '[Human agent]: Photo')
        expect(message.reload.content).to eq('Photo')
      end

      it 'adds a text part when a human multimodal message has none' do
        create(:message, conversation: conversation, account: account, message_type: :outgoing)
        builder = instance_double(Captain::OpenAiMessageBuilderService,
                                  generate_content: [{ type: 'image_url', image_url: { url: 'https://example.com/photo.jpg' } }])
        allow(Captain::OpenAiMessageBuilderService).to receive(:new).and_return(builder)

        expect(history.first[:content].first).to eq(type: 'text', text: '[Human agent]: (attachment)')
      end

      it 'does not prefix Captain messages' do
        assistant = create(:captain_assistant, account: account)
        create(:message, conversation: conversation, account: account, message_type: :outgoing, sender: assistant, content: 'Bot reply')

        expect(history).to eq([{ role: 'assistant', content: 'Bot reply' }])
      end

      it 'does not prefix outgoing messages without a sender' do
        Message.create!([attributes.merge(message_type: :outgoing, content: 'Automation')])

        expect(history).to eq([{ role: 'assistant', content: 'Automation' }])
      end

      it 'logs total, kept, image messages and capped' do
        Message.create!([attributes] * 300)
        allow(Rails.logger).to receive(:info)

        history

        expect(Rails.logger).to have_received(:info).with(
          "[CAPTAIN][Context] event=history_built conversation_id=#{conversation.id} total=300 kept=40 image_messages=0 capped=true"
        )
      end

      it 'keeps the full unprefixed history for Copilot on a pilot account' do
        Message.create!([attributes.merge(message_type: :outgoing, sender_type: 'User', sender_id: create(:user, account: account).id)] * 300)
        message = conversation.messages.order(:id).first
        message.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://example.com/photo.jpg')
        expected = [{ role: 'assistant', content: [{ type: 'text', text: 'Customer message' },
                                                   { type: 'image_url', image_url: { url: 'https://example.com/photo.jpg' } }] }] +
                   ([{ role: 'assistant', content: 'Customer message' }] * 299)

        expect(described_class.new(conversation: conversation, pilot_rules: false).perform).to eq(expected)
        account.disable_features!('captain_pilot')
        expect(described_class.new(conversation: conversation, pilot_rules: false).perform).to eq(expected)
      end
    end

    it 'does not prefix on a non-pilot account' do
      create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'Human reply')

      expect(history).to eq([{ role: 'assistant', content: 'Human reply' }])
    end

    it 'keeps non-pilot history identical to V1 except resolution markers' do
      create(:message, conversation: conversation, account: account, content: 'Question')
      create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'Answer',
                       additional_attributes: { agent_name: 'Support' })
      message = create(:message, conversation: conversation, account: account, content: 'Photo')
      message.attachments.create!(account_id: account.id, file_type: :image, external_url: 'https://example.com/photo.jpg')
      create(:message, conversation: conversation, account: account, private: true, content: 'Private')
      job = Captain::Conversation::ResponseBuilderJob.new
      job.instance_variable_set(:@conversation, conversation)

      expect(history.to_json).to eq(job.send(:collect_previous_messages).to_json)
    end
  end

  %w[v1 v2].each do |version|
    context "with Captain #{version} history" do
      let(:history) do
        if version == 'v1'
          job = Captain::Conversation::ResponseBuilderJob.new
          job.instance_variable_set(:@conversation, conversation)
          job.send(:collect_previous_messages)
        else
          described_class.new(conversation: conversation).perform
        end
      end

      it 'annotates only the changed choice and keeps every original message' do
        create(:message, conversation: conversation, account: account, message_type: :outgoing, content: 'Choose a department')
        create(:message, conversation: conversation, account: account, content: 'Support')
        changed = create(:message, conversation: conversation, account: account, content: 'Sales',
                                   content_attributes: { button_choice_changed: true, previous_button_choice: 'Support' })
        create(:message, conversation: conversation, account: account, content: 'Thank you')

        expect(history).to eq([
                                { role: 'assistant', content: 'Choose a department' },
                                { role: 'user', content: 'Support' },
                                { role: 'user', content: "[The customer changed their choice from «Support» to «Sales»]\nSales" },
                                { role: 'user', content: 'Thank you' }
                              ])
        expect(changed.reload.content).to eq('Sales')
      end
    end
  end
end
