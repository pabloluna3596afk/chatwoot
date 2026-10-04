require 'rails_helper'

RSpec.describe Captain::Assistant, '#reply_limit_reached? and #max_replies' do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def reply(sender: assistant, private_note: false)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing,
                     sender: sender, private: private_note, content: 'respuesta')
  end

  describe '#max_replies' do
    it 'is 20 unless set, and 0 means no limit' do
      expect(assistant.max_replies).to eq(20)

      assistant.config = assistant.config.merge('max_replies_per_conversation' => '5')
      expect(assistant.max_replies).to eq(5)

      assistant.config = assistant.config.merge('max_replies_per_conversation' => 0)
      expect(assistant.max_replies).to eq(0)
    end

    it 'accepts only whole numbers from 0 to 9999' do
      assistant.config = assistant.config.merge('max_replies_per_conversation' => 'muchas')
      expect(assistant).not_to be_valid

      assistant.config = assistant.config.merge('max_replies_per_conversation' => -1)
      expect(assistant).not_to be_valid

      assistant.config = assistant.config.merge('max_replies_per_conversation' => 30)
      expect(assistant).to be_valid
    end
  end

  describe '#reply_limit_reached?' do
    before { assistant.update!(config: assistant.config.merge('max_replies_per_conversation' => 2)) }

    it 'counts the public replies of this assistant in the conversation' do
      reply
      reply(private_note: true)
      reply(sender: create(:user, account: account))
      expect(assistant.reply_limit_reached?(conversation)).to be(false)

      reply
      expect(assistant.reply_limit_reached?(conversation)).to be(true)
    end

    it 'never reaches a limit of 0' do
      assistant.update!(config: assistant.config.merge('max_replies_per_conversation' => 0))
      3.times { reply }

      expect(assistant.reply_limit_reached?(conversation)).to be(false)
    end
  end
end
