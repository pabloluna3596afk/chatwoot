require 'rails_helper'

RSpec.describe Conversation do
  let(:conversation) { create(:conversation) }
  let(:agent) { create(:user, account: conversation.account, role: :agent) }

  before do
    conversation.account.enable_features!(:auto_translate, :captain_tasks, :conversation_auto_translate)
    conversation.account.update!(auto_translate: true, translation_provider: 'captain')
    Current.user = agent
  end

  after { Current.reset }

  it 'names the agent in the account language when translation is disabled' do
    conversation.account.update!(locale: 'es')

    expect { conversation.update!(auto_translate_disabled: true) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: "#{agent.name} desactivó la traducción automática para esta conversación"))
  end

  it 'posts an activity when translation is re-enabled' do
    conversation.update!(auto_translate_disabled: true)

    expect { conversation.update!(auto_translate_disabled: false) }
      .to have_enqueued_job(Conversations::ActivityMessageJob)
      .with(conversation, hash_including(content: "#{agent.name} turned on auto-translate for this conversation"))
  end

  it 'does not post for unset to false or unrelated changes' do
    expect { conversation.update!(auto_translate_disabled: false) }.not_to have_enqueued_job(Conversations::ActivityMessageJob)
    expect { conversation.update!(additional_attributes: { conversation_language: 'es' }) }
      .not_to have_enqueued_job(Conversations::ActivityMessageJob)
  end

  it 'does not mark new agent replies for translation while disabled' do
    conversation.update!(auto_translate_disabled: true)
    message = create(:message, conversation: conversation, message_type: :outgoing, sender: agent, content: 'Hello')

    expect(message.content_attributes).not_to have_key('translation_pending')
  end

  it 'ignores the stored switch when the account control is off' do
    conversation.update!(auto_translate_disabled: true)
    conversation.account.disable_features!(:conversation_auto_translate)

    expect(conversation.auto_translate_enabled?).to be(true)
  end
end
