require 'rails_helper'

RSpec.describe MessageTemplates::HookExecutionService do
  let(:account) { create(:account, locale: 'es', custom_attributes: { plan_name: 'startups' }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Asistente de Ventas') }
  let(:status) { :pending }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact, status: status) }

  def customer_message
    create(:message, conversation: conversation, message_type: :incoming, account: account)
  end

  def private_notes
    conversation.messages.where(private: true).pluck(:content)
  end

  def remove_installation_key
    allow(Llm::Config).to receive(:api_key_configured?).and_call_original
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
  end

  def exhaust_responses
    account.update!(
      limits: { 'captain_responses' => 100 },
      custom_attributes: account.custom_attributes.merge('captain_responses_usage' => 100)
    )
  end

  before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  context 'when the AI key is missing' do
    before { remove_installation_key }

    context 'with a conversation Captain never took' do
      let(:status) { :open }

      it 'leaves one note on the first customer message, in Spanish, with the assistant name' do
        customer_message

        expect(private_notes).to eq(['Asistente de Ventas no pudo responder: falta configurar la llave de IA.'])
        expect(conversation.reload.status).to eq('open')
      end

      it 'does not repeat the note on later messages' do
        customer_message
        customer_message

        expect(private_notes.size).to eq(1)
      end

      it 'sends no message to the customer' do
        customer_message

        expect(conversation.messages.outgoing.where(private: false)).to be_empty
      end
    end

    context 'with a conversation already handed to the team' do
      let(:status) { :open }

      it 'does not add a note when it is not the first message' do
        create(:message, conversation: conversation, message_type: :incoming, account: account)
        conversation.messages.where(private: true).destroy_all

        customer_message

        expect(private_notes).to be_empty
      end
    end

    context 'with a pending conversation' do
      it 'hands it off and explains why' do
        customer_message

        expect(conversation.reload.status).to eq('open')
        expect(private_notes).to include('Asistente de Ventas no pudo responder: falta configurar la llave de IA.')
      end
    end
  end

  context 'when the monthly responses ran out' do
    before { exhaust_responses }

    it 'explains the quota on a pending conversation that gets handed off' do
      customer_message

      expect(conversation.reload.status).to eq('open')
      expect(private_notes).to include('Asistente de Ventas no pudo responder: se agotaron las respuestas del mes.')
    end

    context 'with a conversation Captain never took' do
      let(:status) { :open }

      it 'leaves the note on the first customer message' do
        customer_message

        expect(private_notes).to eq(['Asistente de Ventas no pudo responder: se agotaron las respuestas del mes.'])
      end
    end
  end

  context 'when Captain can answer' do
    it 'adds no note' do
      allow(Captain::Conversation::ResponseBuilderJob).to receive(:perform_later)

      customer_message

      expect(private_notes).to be_empty
      expect(Captain::Conversation::ResponseBuilderJob).to have_received(:perform_later)
    end
  end

  context 'with an English account' do
    let(:account) { create(:account, locale: 'en', custom_attributes: { plan_name: 'startups' }) }
    let(:status) { :open }

    it 'writes the note in English' do
      remove_installation_key

      customer_message

      expect(private_notes).to eq(['Asistente de Ventas could not respond: the AI key is not configured.'])
    end
  end
end
