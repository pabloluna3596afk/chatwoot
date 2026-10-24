require 'rails_helper'

RSpec.describe Captain::Conversation::ResponseSchedulerService, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:message) { create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming) }

  before do
    allow(message.inbox).to receive(:captain_assistant).and_return(assistant)
  end

  it 'schedules the default reply six seconds later' do
    freeze_time do
      expect { described_class.new(message: message).perform }
        .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
        .with(conversation, assistant, message.id).at(6.seconds.from_now)
    end
  end

  it 'enqueues immediately when the delay is zero' do
    assistant.update!(reply_delay_seconds: 0)

    expect { described_class.new(message: message).perform }
      .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob)
      .with(conversation, assistant, message.id).at(:no_wait)
  end

  it 'uses the configured ten second delay' do
    assistant.update!(reply_delay_seconds: 10)

    freeze_time do
      expect { described_class.new(message: message).perform }
        .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob).at(10.seconds.from_now)
    end
  end

  it 'preserves the five second attachment cap for a V2 burst with zero configured delay' do
    account.enable_features!(:captain_integration_v2)
    assistant.update!(reply_delay_seconds: 0)

    freeze_time do
      create_list(:message, 4, :with_attachment, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)

      expect { described_class.new(message: message).perform }
        .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob).at(5.seconds.from_now)
    end
  end

  [false, true].each do |v2_enabled|
    context "with Captain V2 enabled: #{v2_enabled}" do
      let(:message) do
        create(:message, :with_attachment, conversation: conversation, account: account, inbox: inbox, message_type: :incoming)
      end

      before do
        account.enable_features!(:captain_integration_v2) if v2_enabled
      end

      it 'keeps the attachment wait when the configured delay is smaller' do
        assistant.update!(reply_delay_seconds: 1)

        freeze_time do
          expect { described_class.new(message: message).perform }
            .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob).at(2.seconds.from_now)
        end
      end

      it 'keeps the default delay when the attachment wait is smaller' do
        freeze_time do
          expect { described_class.new(message: message).perform }
            .to have_enqueued_job(Captain::Conversation::ResponseBuilderJob).at(6.seconds.from_now)
        end
      end
    end
  end
end
