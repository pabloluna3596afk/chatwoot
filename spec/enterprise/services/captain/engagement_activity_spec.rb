require 'rails_helper'

RSpec.describe Captain::EngagementActivity do
  let(:account) { create(:account, locale: locale) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Aurora') }
  let(:conversation) { create(:conversation, account: account) }

  describe 'shared channel labels' do
    let(:locale) { 'en' }

    it 'retains the existing Captain channel catalog including web and Twitter' do
      expected = Conversations::ChannelType::CHANNELS.transform_values { |value| value == 'web_widget' ? 'web' : value }
      expect(described_class::CHANNELS).to eq(expected)
      expect(described_class::CHANNELS.fetch('Channel::TwitterProfile')).to eq('twitter')
    end

    it 'keeps the translated web label after sharing the channel resolver' do
      conversation.update!(additional_attributes: {
                             captain_skip_reason: { reason: 'audience_denied', condition: { attribute_key: 'phone_number' } }
                           })
      service = described_class.new(conversation, assistant)

      expect(service.send(:channel_label)).to eq(I18n.t('captain.engagement.channels.web', locale: locale))
    end
  end

  diagnoses = {
    'audience_denied' => { 'attribute_key' => 'phone_number' },
    'audience_not_allowed' => { 'attribute_key' => 'email' },
    'audience_missing_data' => { 'attribute_key' => 'channel_ids' },
    'audience_scope' => { 'contact_scope' => 'new' }
  }

  %w[es en].each do |language|
    context "with locale #{language}" do
      let(:locale) { language }

      diagnoses.each do |reason, condition|
        it "writes a translated #{reason} activity" do
          conversation.update!(additional_attributes: { captain_skip_reason: { reason: reason, condition: condition } })

          note = described_class.new(conversation, assistant).perform

          expect(note).to be_activity
          expect(note.content).to start_with('Aurora ')
          expect(note.content).not_to include('Translation missing', '%{', 'translation missing')
          expect(note.additional_attributes['captain_skip_reason']).to eq('reason' => reason, 'condition' => condition)
        end
      end

      it 'uses the returning customer description' do
        conversation.update!(additional_attributes: {
                               captain_skip_reason: { reason: 'audience_scope', condition: { contact_scope: 'returning' } }
                             })

        note = described_class.new(conversation, assistant).perform

        expect(note.content).to include(language == 'es' ? 'clientes recurrentes' : 'returning customers')
      end

      it 'escapes the assistant name in activity content' do
        assistant.name = '<b>Aurora</b>'
        conversation.update!(additional_attributes: {
                               captain_skip_reason: { reason: 'audience_denied', condition: { attribute_key: 'phone_number' } }
                             })

        expect(described_class.new(conversation, assistant).perform.content).to include('&lt;b&gt;Aurora&lt;/b&gt;')
      end
    end
  end
end
