require 'rails_helper'

RSpec.describe Captain::InboxPendingConversationsResolutionJob, type: :job do
  let(:account) { create(:account, locale: 'es') }
  let(:inbox) { create(:inbox, account: account) }
  let(:assistant) do
    create(:captain_assistant, account: account, name: 'Asistente de Ventas', config: { 'auto_resolve_mode' => 'evaluated' })
  end
  let!(:conversation) { create(:conversation, account: account, inbox: inbox, last_activity_at: 2.hours.ago, status: :pending) }
  let(:service) { instance_double(Captain::ConversationCompletionService) }

  def note
    conversation.messages.where(private: true).last.content
  end

  before do
    create(:captain_inbox, inbox: inbox, captain_assistant: assistant)
    inbox.reload
    allow(inbox.account).to receive(:feature_enabled?).and_call_original
    allow(inbox.account).to receive(:feature_enabled?).with('captain_tasks').and_return(true)
    allow(Captain::ConversationCompletionService).to receive(:new).and_return(service)
  end

  it 'writes the resolution note in the account language with the assistant name' do
    allow(service).to receive(:perform).and_return({ complete: true, reason: 'Pregunta resuelta' })

    described_class.perform_now(inbox)

    expect(conversation.reload.status).to eq('resolved')
    expect(note).to eq('Asistente de Ventas cerró la conversación por inactividad (Pregunta resuelta).')
  end

  it 'writes the handoff note in the account language with the assistant name' do
    allow(service).to receive(:perform).and_return({ complete: false, reason: 'El cliente debe confirmar el pedido' })

    described_class.perform_now(inbox)

    expect(conversation.reload.status).to eq('open')
    expect(note).to eq('Asistente de Ventas pasó la conversación al equipo (El cliente debe confirmar el pedido).')
  end

  it 'explains a missing AI key instead of showing the technical error' do
    allow(service).to receive(:perform).and_return({ complete: false, reason: 'Captain AI API key is not configured.', error: :missing_key })

    described_class.perform_now(inbox)

    expect(conversation.reload.status).to eq('open')
    expect(note).to eq('Asistente de Ventas no pudo responder: falta configurar la llave de IA.')
    expect(note).not_to include('API key')
  end

  it 'explains any other evaluation failure without the technical reason' do
    allow(service).to receive(:perform).and_return({ complete: false, reason: 'RubyLLM::Error boom', error: :failed })

    described_class.perform_now(inbox)

    expect(note).to eq('Asistente de Ventas no pudo revisar la conversación y la pasó al equipo.')
  end

  it 'keeps English notes for an English account' do
    account.update!(locale: 'en')
    allow(service).to receive(:perform).and_return({ complete: false, reason: 'x', error: :missing_key })

    described_class.perform_now(inbox)

    expect(note).to eq('Asistente de Ventas could not respond: the AI key is not configured.')
  end

  it 'has Spanish activity messages for Captain status changes' do
    %w[resolved resolved_with_reason resolved_by_tool open open_with_reason auto_opened_after_agent_reply].each do |key|
      spanish = I18n.t("conversations.activity.captain.#{key}", locale: :es, user_name: 'Asistente de Ventas', reason: 'motivo')

      expect(spanish).not_to eq(I18n.t("conversations.activity.captain.#{key}", locale: :en, user_name: 'Asistente de Ventas', reason: 'motivo'))
      expect(spanish).not_to include('Conversation was')
    end
  end
end
