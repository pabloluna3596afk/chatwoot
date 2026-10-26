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

  it 'marks a translation as failed when the service raises' do
    service = instance_double(Captain::Conversation::ContactMessageTranslationService)
    allow(Captain::Conversation::ContactMessageTranslationService).to receive(:new).and_return(service)
    allow(service).to receive(:perform).and_raise(StandardError, 'provider error')

    expect { described_class.perform_now(message, 'es') }.to raise_error('provider error')
    expect(message.reload.content_attributes['translation_status']).to eq('failed')
  end
end
