require 'rails_helper'

describe MessageTemplates::Template::Greeting do
  context 'when this hook is called' do
    let(:conversation) { create(:conversation) }

    it 'creates the email collect messages' do
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
    end

    it 'creates the greeting messages with template variable' do
      conversation.inbox.update!(greeting_message: 'Hey, {{contact.name}} welcome to our board.')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq("Hey, #{conversation.contact.name} welcome to our board.")
    end

    it 'creates the greeting messages with more than one variable strings' do
      conversation.inbox.update!(greeting_message: 'Hey, {{contact.name}} welcome to our board. - from {{account.name}}')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq("Hey, #{conversation.contact.name} welcome to our board. - from #{conversation.account.name}")
    end

    it 'creates the greeting messages' do
      conversation.inbox.update!(greeting_message: 'Hello welcome to our board.')
      described_class.new(conversation: conversation).perform
      expect(conversation.messages.count).to eq(1)
      expect(conversation.messages.last.content).to eq('Hello welcome to our board.')
    end
  end

  context 'with the shared resolver' do
    let(:conversation) { create(:conversation) }

    it 'omits a greeting with missing data and leaves a private diagnostic' do
      conversation.inbox.update!(greeting_message: 'Hello {{ contact.custom_attribute.absent }}')
      described_class.new(conversation: conversation).perform

      expect(conversation.messages.where(private: false)).to be_empty
      expect(conversation.messages.outgoing.last).to have_attributes(private: true)
      expect(conversation.messages.outgoing.last.content).to include('content: missing')
    end

    it 'does not store invalid Liquid as the greeting' do
      conversation.inbox.update!(greeting_message: '{% if %}')
      described_class.new(conversation: conversation).perform

      expect(conversation.messages.template).to be_empty
      expect(conversation.messages.outgoing.last.content).to include('invalid')
    end

    it 'uses the account timezone and renders inserted data only once' do
      conversation.account.update!(reporting_timezone: 'America/Guayaquil')
      conversation.contact.update!(identifier: '{{ contact.email }}')
      conversation.inbox.update!(greeting_message: '{{ date.today }} / {{ contact.identifier }}')
      travel_to Time.utc(2026, 10, 20, 2) do
        described_class.new(conversation: conversation).perform
        expect(conversation.messages.template.last.content).to eq('2026-10-19 / {{ contact.email }}')
      end
    end
  end
end
