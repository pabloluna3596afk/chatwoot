require 'rails_helper'

RSpec.describe Captain::Llm::AssistantFalsePromiseService do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:service) { described_class.new(assistant: assistant, conversation: conversation) }
  let(:mock_chat) { instance_double(RubyLLM::Chat) }
  let(:mock_response) do
    instance_double(
      RubyLLM::Message,
      content: { 'decision' => 'safe', 'reason' => 'answer_stays_within_known_context' }
    )
  end

  before do
    put_account_on_plan(account, captain_internal_calls: 1)
    allow(RubyLLM).to receive(:chat).and_return(mock_chat)
    allow(mock_chat).to receive(:with_thinking).and_return(mock_chat)
    allow(mock_chat).to receive(:with_temperature).and_return(mock_chat)
    allow(mock_chat).to receive(:with_schema).and_return(mock_chat)
    allow(mock_chat).to receive(:with_instructions).and_return(mock_chat)
  end

  describe '#detect' do
    let(:message_history) do
      [
        { role: 'user', content: 'Can you fix this later?' },
        { role: 'assistant', content: 'I can help with known troubleshooting steps.' }
      ]
    end

    it 'passes the triggering message to usage instrumentation' do
      message = create(:message, account: account, conversation: conversation)
      contextual_service = described_class.new(assistant: assistant, conversation: conversation, message_id: message.id)

      expect(contextual_service.send(:instrumentation_params, 'prompt')).to include(
        conversation_id: conversation.display_id, message_id: message.id
      )
    end

    it 'uses the detector model even when the assistant feature model is overridden' do
      account.update!(captain_models: { 'assistant' => 'gpt-5-mini' })

      expect(RubyLLM).to receive(:chat).with(model: 'gpt-6-luna', protocol: :responses).and_return(mock_chat)
      allow(mock_chat).to receive(:ask).and_return(mock_response)
      expect(account).to receive(:finish_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_call_original

      result = service.detect(message_history: message_history, assistant_response: 'Try restarting the app.')

      expect(result).to include('model' => 'gpt-6-luna')
    end

    it 'uses the false promise schema and detector prompt' do
      expect(mock_chat).to receive(:with_schema).with(Captain::AssistantFalsePromiseSchema).and_return(mock_chat)
      expect(mock_chat).to receive(:with_instructions).with(
        a_string_including('future work', 'future_work_promise')
      ).and_return(mock_chat)
      expect(mock_chat).to receive(:ask).with(
        a_string_including(
          '<conversation_context>',
          'User: Can you fix this later?',
          '<assistant_response_to_check>',
          'Try restarting the app.'
        )
      ).and_return(mock_response)

      result = service.detect(message_history: message_history, assistant_response: 'Try restarting the app.')

      expect(result).to include('decision' => 'safe', 'reason' => 'answer_stays_within_known_context')
    end

    it 'skips detection when the internal allowance is exhausted' do
      allow(account).to receive(:reserve_captain_ai_usage!).with(bucket: :internal, reservation_id: anything).and_return(false)

      expect(RubyLLM).not_to receive(:chat)
      result = service.detect(message_history: message_history, assistant_response: 'Try restarting the app.')

      expect(result).to include('decision' => nil, 'reason' => nil)
      expect(result).not_to have_key('error')
    end

    it 'releases the reservation when the provider raises' do
      reservation_id = 'promise-detection-reservation'
      allow(SecureRandom).to receive(:uuid).and_return(reservation_id)
      allow(mock_chat).to receive(:ask).and_raise(IOError, 'provider unavailable')
      expect(account).to receive(:reserve_captain_ai_usage!).with(bucket: :internal, reservation_id: reservation_id).and_call_original
      expect(account).to receive(:release_captain_ai_usage!).with(bucket: :internal, reservation_id: reservation_id).and_return(true)
      expect(account).not_to receive(:finish_captain_ai_usage!)

      result = service.detect(message_history: message_history, assistant_response: 'Try restarting the app.')

      expect(result['error']).to eq('provider unavailable')
    end
  end
end
