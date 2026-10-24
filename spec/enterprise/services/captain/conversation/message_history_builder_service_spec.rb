require 'rails_helper'

RSpec.describe Captain::Conversation::MessageHistoryBuilderService do
  let(:account) { create(:account, locale: 'en') }
  let(:conversation) { create(:conversation, account: account) }

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
