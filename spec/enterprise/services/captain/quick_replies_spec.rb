require 'rails_helper'

RSpec.describe Captain::QuickReplies do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:items) { [described_class.item('Sí, reservar', 'yes_book:x'), described_class.item('Otra hora', 'other_time')] }

  after { Redis::Alfred.delete(format(Redis::RedisKeys::CAPTAIN_QUICK_REPLIES, conversation_id: conversation.id)) }

  def inbox_double(channel_type, provider: nil)
    channel = provider ? instance_double(Channel::Whatsapp, provider: provider) : nil
    instance_double(Inbox, channel_type: channel_type, channel: channel)
  end

  describe '.supported?' do
    it 'is true for channels that render input_select' do
      %w[Channel::WebWidget Channel::Telegram Channel::FacebookPage Channel::Line].each do |type|
        expect(described_class.supported?(inbox_double(type))).to be(true), "expected #{type} to support buttons"
      end
    end

    it 'is true for WhatsApp Cloud only' do
      expect(described_class.supported?(inbox_double('Channel::Whatsapp', provider: 'whatsapp_cloud'))).to be(true)
      expect(described_class.supported?(inbox_double('Channel::Whatsapp', provider: 'default'))).to be(false)
    end

    it 'is false for channels without interactive messages' do
      %w[Channel::Sms Channel::Email Channel::Api Channel::Instagram Channel::TwilioSms].each do |type|
        expect(described_class.supported?(inbox_double(type))).to be(false), "expected #{type} to have no buttons"
      end
    end
  end

  describe '.item' do
    it 'builds the title/value pair the input_select message expects' do
      expect(described_class.item('jue 16 · 10:00', '2030-01-16T10:00:00-05:00')).to eq(
        'title' => 'jue 16 · 10:00', 'value' => '2030-01-16T10:00:00-05:00'
      )
    end
  end

  describe '.stash and .take' do
    it 'hands the items over once and clears them' do
      described_class.stash(conversation, items, responding_to: 5)

      expect(described_class.take(conversation, responding_to: 5)).to eq(items)
      expect(described_class.take(conversation, responding_to: 5)).to be_nil
    end

    it 'keeps only the latest items' do
      described_class.stash(conversation, items, responding_to: 5)
      described_class.stash(conversation, [described_class.item('Dejarla así', 'keep:1')], responding_to: 5)

      expect(described_class.take(conversation, responding_to: 5)).to eq([{ 'title' => 'Dejarla así', 'value' => 'keep:1' }])
    end

    it 'drops buttons stashed for another customer message instead of leaking them' do
      described_class.stash(conversation, items, responding_to: 5)

      expect(described_class.take(conversation, responding_to: 6)).to be_nil
      expect(described_class.take(conversation, responding_to: 5)).to be_nil
    end

    it 'works without a message id (Captain V1)' do
      described_class.stash(conversation, items)

      expect(described_class.take(conversation)).to eq(items)
    end

    it 'does not mix conversations' do
      other = create(:conversation, account: account)
      described_class.stash(other, items)

      expect(described_class.take(conversation)).to be_nil
      expect(described_class.take(other)).to eq(items)
    end

    it 'keeps at most 10 items, the WhatsApp list limit' do
      many = Array.new(14) { |index| described_class.item("Hora #{index}", "start-#{index}") }
      described_class.stash(conversation, many)

      expect(described_class.take(conversation).size).to eq(10)
    end

    it 'returns nothing when nothing was stashed' do
      expect(described_class.take(conversation)).to be_nil
    end
  end
end
