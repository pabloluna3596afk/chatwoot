require 'rails_helper'

RSpec.describe Captain::Conversation::ContactMessageTranslationJob do
  let(:message) { create(:message) }

  it 'runs the contact message translation service' do
    service = instance_double(Captain::Conversation::ContactMessageTranslationService)
    expect(Captain::Conversation::ContactMessageTranslationService).to receive(:new)
      .with(message: message, target_language: 'es').and_return(service)
    expect(service).to receive(:perform)

    described_class.perform_now(message, 'es')
  end
end
