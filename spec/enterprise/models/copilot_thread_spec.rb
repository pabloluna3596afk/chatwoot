require 'rails_helper'

RSpec.describe CopilotThread, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:account) }

    it 'belongs to Captain::Assistant' do
      reflection = described_class.reflect_on_association(:assistant)

      expect(reflection.macro).to eq(:belongs_to)
      expect(reflection.class_name).to eq('Captain::Assistant')
    end

    it { is_expected.to have_many(:copilot_messages).dependent(:destroy_async) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
  end

  describe '#push_event_data' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant, title: 'Test Thread') }

    it 'returns the correct event data' do
      event_data = copilot_thread.push_event_data

      expect(event_data[:id]).to eq(copilot_thread.id)
      expect(event_data[:title]).to eq('Test Thread')
      expect(event_data[:created_at]).to eq(copilot_thread.created_at.to_i)
      expect(event_data[:user]).to eq(user.push_event_data)
      expect(event_data[:account_id]).to eq(account.id)
    end
  end

  describe '#previous_history' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }

    context 'when there are messages in the thread' do
      before do
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'user', message: { 'content' => 'User message' })
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'assistant_thinking', message: { 'content' => 'Thinking...' })
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'assistant', message: { 'content' => 'Assistant message' })
      end

      it 'returns only user and assistant messages in chronological order' do
        history = copilot_thread.previous_history

        expect(history.length).to eq(2)
        expect(history[0][:role]).to eq('user')
        expect(history[0][:content]).to eq('User message')
        expect(history[1][:role]).to eq('assistant')
        expect(history[1][:content]).to eq('Assistant message')
      end
    end

    context 'when there are no messages in the thread' do
      it 'returns an empty array' do
        expect(copilot_thread.previous_history).to eq([])
      end
    end

    it 'keeps at most twenty messages and twelve thousand characters starting with a user message' do
      11.times do
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'user', message: { 'content' => 'u' * 600 })
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'assistant', message: { 'content' => 'a' * 600 })
      end

      history = copilot_thread.previous_history

      expect(history.length).to eq(20)
      expect(history.sum { |item| item[:content].length }).to eq(12_000)
      expect(history.first[:role]).to eq('user')
    end

    it 'trims the oldest messages when the character budget is exceeded' do
      10.times do
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'user', message: { 'content' => 'u' * 601 })
        create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'assistant', message: { 'content' => 'a' * 601 })
      end

      history = copilot_thread.previous_history

      expect(history.length).to eq(18)
      expect(history.sum { |item| item[:content].length }).to be <= Captain::Copilot::Limits::HISTORY_CHARACTERS
      expect(history.first[:role]).to eq('user')
      expect(history.last[:content]).to eq('a' * 601)
    end

    it 'excludes error messages from model history' do
      create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'user', message: { 'content' => 'Question' })
      create(:captain_copilot_message, copilot_thread: copilot_thread, message_type: 'assistant', message: { 'content' => 'Failed', 'error' => true })

      expect(copilot_thread.previous_history).to eq([{ content: 'Question', role: 'user' }])
    end
  end
end
