require 'rails_helper'

describe CsatSurveyService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, csat_survey_enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '+1234567890') }
  let(:closed_at) { 2.hours.ago }
  let(:conversation) do
    create(:conversation, contact_inbox: contact_inbox, inbox: inbox, account: account, status: :resolved,
                          additional_attributes: { Captain::Followup::Reengager::STATE_KEY => { 'closed_at' => closed_at.utc.iso8601 } })
  end
  let(:csat_template) { instance_double(MessageTemplates::Template::CsatSurvey, perform: nil) }

  before do
    allow(MessageTemplates::Template::CsatSurvey).to receive(:new).and_return(csat_template)
    allow(conversation).to receive(:can_reply?).and_return(true)
  end

  describe '#perform for a conversation Captain closed for inactivity' do
    it 'does not send the survey while the customer has not replied' do
      described_class.new(conversation: conversation).perform

      expect(MessageTemplates::Template::CsatSurvey).not_to have_received(:new)
    end

    it 'sends the survey once the customer wrote after the close and it is resolved again' do
      create(:message, conversation: conversation, account: account, inbox: inbox, message_type: :incoming, created_at: 1.hour.ago)

      described_class.new(conversation: conversation).perform

      expect(MessageTemplates::Template::CsatSurvey).to have_received(:new).with(conversation: conversation)
    end

    it 'sends the survey for conversations Captain did not close' do
      conversation.update!(additional_attributes: {})

      described_class.new(conversation: conversation).perform

      expect(MessageTemplates::Template::CsatSurvey).to have_received(:new).with(conversation: conversation)
    end
  end
end
