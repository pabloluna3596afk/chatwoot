require 'rails_helper'

RSpec.describe Captain::Followup do
  let(:account) { create(:account, locale: 'es') }
  let(:followup_config) { {} }
  let(:assistant_config) { { 'followup' => followup_config } }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Asistente de Ventas', config: assistant_config) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :pending) }
  let(:now) { Time.zone.parse('2030-01-15T10:00:00-05:00') }

  around { |example| travel_to(now) { example.run } }

  before { create(:captain_inbox, captain_assistant: assistant, inbox: inbox) }

  def say(sender, at, message_type: :outgoing, **attributes)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: message_type, sender: sender,
                       created_at: at }.merge(attributes))
  end

  def captain_says(at)
    say(assistant, at)
  end

  def customer_says(at)
    say(contact, at, message_type: :incoming)
  end

  def nudge(at = now)
    Captain::Followup::Nudger.new(conversation.reload, assistant, now: at).perform
  end

  def public_messages
    conversation.messages.where(private: false, message_type: :outgoing)
  end

  describe Captain::Followup::Nudger do
    before { captain_says(now - 31.minutes) }

    it 'sends nothing before the time is up' do
      expect(nudge(now - 5.minutes)).to be_nil
      expect(public_messages.count).to eq(1)
    end

    it 'sends one short message with the two buttons after 30 minutes without a reply' do
      expect(nudge).to eq(:nudged)

      message = public_messages.order(:id).last
      expect(message).to have_attributes(sender: assistant, content_type: 'input_select')
      expect(message.content).to eq('¿Sigues ahí? Si todavía necesitas ayuda, solo responde.')
      expect(message.content).not_to include('Asistente de Ventas')
      expect(message.content_attributes['items'].pluck('title')).to eq(['Sí, sigo aquí', 'Ya no, gracias'])
      expect(message.content_attributes['captain_followup']).to eq('nudge')
    end

    it 'remembers what each button stands for' do
      nudge

      expect(Captain::QuickReplies.choice(conversation, 'Ya no, gracias')).to eq('followup' => 'stop')
      expect(Captain::QuickReplies.choice(conversation, 'Sí, sigo aquí')).to eq('followup' => 'continue')
    end

    it 'does not send the same nudge twice' do
      nudge
      expect { nudge }.not_to(change { conversation.messages.count })
    end

    it 'sends nothing when the customer replied' do
      customer_says(now - 10.minutes)

      expect(nudge).to be_nil
    end

    it 'sends nothing once a person took the conversation' do
      conversation.update!(status: :open)

      expect(nudge).to be_nil
    end

    it 'sends nothing when the last public message is from a person' do
      say(create(:user, account: account), now - 20.minutes)

      expect(nudge).to be_nil
    end

    it 'ignores private notes when looking for the last message' do
      say(assistant, now - 5.minutes, private: true, content: 'nota')

      expect(nudge).to eq(:nudged)
    end

    it 'sends nothing when the account reached its daily proactive cap' do
      account.update!(settings: account.settings.merge('proactive_daily_send_cap' => 0))

      expect(nudge).to be_nil
    end

    it 'asks in words when the channel has no buttons' do
      api_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
      create(:captain_inbox, captain_assistant: assistant, inbox: api_inbox)
      api_conversation = create(:conversation, account: account, inbox: api_inbox, contact: contact, status: :pending)
      create(:message, account: account, inbox: api_inbox, conversation: api_conversation, message_type: :outgoing, sender: assistant,
                       created_at: now - 31.minutes)

      Captain::Followup::Nudger.new(api_conversation, assistant, now: now).perform

      message = api_conversation.messages.order(:id).last
      expect(message.content_type).to eq('text')
      expect(message.content).to include('Responde "Sí, sigo aquí" o "Ya no, gracias"')
    end

    context 'with a closed 24 h window' do
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
      end
      let(:inbox) { channel.inbox }

      it 'never sends a nudge outside the window' do
        conversation.messages.destroy_all
        customer_says(now - 26.hours)
        captain_says(now - 25.hours)

        expect(nudge).to be_nil
      end
    end

    context 'with two nudges configured' do
      let(:followup_config) { { 'max_nudges' => 2 } }

      it 'sends the second one after another 30 minutes and never a third' do
        expect(nudge).to eq(:nudged)
        expect(nudge(now + 31.minutes)).to eq(:nudged)
        expect(nudge(now + 62.minutes)).to be_nil
        expect(public_messages.count).to eq(3)
      end
    end

    context 'with no nudges configured' do
      let(:followup_config) { { 'max_nudges' => 0 } }

      it 'does nothing, not even close' do
        expect(nudge(now + 1.day)).to be_nil
        expect(conversation.reload).to be_pending
      end
    end

    describe 'closing for inactivity' do
      before { nudge }

      it 'waits the configured time after the last nudge' do
        expect(nudge(now + 119.minutes)).to be_nil
        expect(conversation.reload).to be_pending
      end

      it 'resolves the conversation with a private note that names the assistant' do
        expect(nudge(now + 121.minutes)).to eq(:closed)

        expect(conversation.reload).to be_resolved
        note = conversation.messages.where(private: true).last
        expect(note).to have_attributes(sender: assistant, content: 'Asistente de Ventas cerró la conversación por inactividad.')
      end

      it 'says goodbye to the customer when the assistant sends that message (inside the window)' do
        nudge(now + 121.minutes)

        expect(public_messages.order(:id).last.content).to eq(I18n.t('conversations.activity.auto_resolution_message', locale: 'es'))
      end

      it 'keeps what the re-engagement needs to find the conversation' do
        nudge(now + 121.minutes)

        state = conversation.reload.additional_attributes['captain_followup']
        expect(state).to include('closed_at' => (now + 121.minutes).utc.iso8601, 'assistant_id' => assistant.id)
      end

      it 'does not close when the customer answered the nudge' do
        customer_says(now + 30.minutes)

        expect(nudge(now + 3.hours)).to be_nil
        expect(conversation.reload).to be_pending
      end

      it 'closes only once' do
        nudge(now + 121.minutes)

        expect(nudge(now + 125.minutes)).to be_nil
      end
    end
  end

  describe Captain::Followup::Dispatcher do
    before do
      captain_says(now - 31.minutes)
      conversation.update_columns(last_activity_at: now - 31.minutes) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'nudges the conversations Captain handles in an inbox of the assistant' do
      expect { described_class.new(now: now).perform }.to change { public_messages.count }.by(1)
    end

    it 'does nothing when the assistant turned the follow-up off' do
      assistant.update!(config: { 'followup' => { 'inactivity_enabled' => false } })

      expect { described_class.new(now: now).perform }.not_to(change { conversation.messages.count })
    end

    it 'leaves alone the conversations of an inbox without Captain' do
      CaptainInbox.where(captain_assistant: assistant).destroy_all

      expect { described_class.new(now: now).perform }.not_to(change { conversation.messages.count })
    end

    it 'leaves alone a conversation that an agent bot (Panel AI) handles' do
      conversation.update!(assignee_agent_bot: create(:agent_bot, account: account))

      expect { described_class.new(now: now).perform }.not_to(change { conversation.messages.count })
    end

    it 'keeps going when one conversation fails' do
      allow_any_instance_of(Captain::Followup::Nudger).to receive(:perform).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

      expect { described_class.new(now: now).perform }.not_to raise_error
    end

    it 'never enqueues the Panel AI follow-up job' do
      expect { described_class.new(now: now).perform }.not_to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
    end
  end

  describe Captain::Followup::Reengager do
    let(:templates) do
      [{ 'name' => 'volver_a_hablar', 'language' => 'es', 'status' => 'approved', 'category' => 'MARKETING', 'namespace' => 'ns',
         'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}, soy {{2}}. ¿Seguimos?' }] },
       { 'name' => 'pendiente', 'language' => 'es', 'status' => 'pending', 'components' => [] }]
    end
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                message_templates: templates)
    end
    let(:inbox) { channel.inbox }
    let(:template) { { 'name' => 'volver_a_hablar', 'language' => 'es' } }
    let(:followup_config) { { 'reengagement_enabled' => true, 'reengagement_template' => template } }
    let(:assistant_config) { { 'followup' => followup_config, 'allow_paid_templates' => true } }
    let(:closed_at) { now - 2.days }

    before do
      customer_says(now - 3.days)
      captain_says(now - 3.days + 1.minute)
      # The incoming message above would reopen a resolved conversation, so it is resolved after the messages exist.
      conversation.update!(status: :resolved,
                           additional_attributes: { 'captain_followup' => { 'closed_at' => closed_at.utc.iso8601, 'assistant_id' => assistant.id } })
    end

    def reengage
      described_class.new(conversation.reload, assistant, now: now).perform
    end

    it 'finds the conversations closed by Captain in the last 7 days that were not attempted' do
      expect(described_class.candidates(inbox, now: now)).to contain_exactly(conversation)
    end

    it 'does not look at conversations closed longer ago' do
      conversation.update!(additional_attributes: { 'captain_followup' => { 'closed_at' => (now - 8.days).utc.iso8601 } })

      expect(described_class.candidates(inbox, now: now)).to be_empty
    end

    it 'sends the approved template with the customer and assistant names' do
      expect(reengage).to eq(:sent)

      message = public_messages.order(:id).last
      expect(message.content).to eq('Hola Ana Pérez, soy Asistente de Ventas. ¿Seguimos?')
      expect(message.additional_attributes['template_params']).to include(
        'name' => 'volver_a_hablar', 'language' => 'es', 'processed_params' => { 'body' => { '1' => 'Ana Pérez', '2' => 'Asistente de Ventas' } }
      )
      expect(conversation.reload.additional_attributes['captain_followup']['reengagement']).to include('status' => 'sent')
    end

    it 'tries only once' do
      reengage

      expect(described_class.candidates(inbox, now: now)).to be_empty
      expect(reengage).to be_nil
    end

    it 'waits while the 24 h window is still open' do
      conversation.messages.incoming.update_all(created_at: now - 1.hour)

      expect(reengage).to be_nil
      expect(public_messages.where.not(sender: assistant)).to be_empty
    end

    it 'waits when the account reached its daily proactive cap' do
      account.update!(settings: account.settings.merge('proactive_daily_send_cap' => 0))

      expect(reengage).to be_nil
      expect(conversation.reload.additional_attributes['captain_followup']).not_to have_key('reengagement')
    end

    it 'does not contact the same customer twice in 7 days' do
      other = create(:conversation, account: account, inbox: inbox, contact: contact, status: :resolved)
      other.update!(additional_attributes: { 'captain_followup' => { 'reengagement' => { 'status' => 'sent', 'at' => (now - 2.days).utc.iso8601 } } })

      expect(reengage).to eq(:skipped)
      expect(conversation.reload.additional_attributes['captain_followup']['reengagement']).to include('reason' => 'cooldown')
    end

    context 'with paid messages off (the default)' do
      let(:assistant_config) { { 'followup' => followup_config } }

      it 'sends nothing to the customer and leaves one private note, once' do
        expect(reengage).to eq(:skipped)

        expect(public_messages.where(sender: assistant).count).to eq(1) # only the earlier message
        note = conversation.messages.where(private: true).last
        expect(note.content).to include('Asistente de Ventas no envió el reenganche', 'plantillas de pago están desactivadas')
        expect(described_class.candidates(inbox, now: now)).to be_empty
      end
    end

    context 'without a chosen template' do
      let(:followup_config) { { 'reengagement_enabled' => true } }

      it 'skips with a private note' do
        expect(reengage).to eq(:skipped)

        expect(conversation.messages.where(private: true).last.content).to include('no hay una plantilla elegida')
      end
    end

    context 'with a template that is not approved' do
      let(:template) { { 'name' => 'pendiente', 'language' => 'es' } }

      it 'skips with a private note' do
        expect(reengage).to eq(:skipped)

        expect(conversation.messages.where(private: true).last.content).to include('no está aprobada')
      end
    end

    context 'when run by the dispatcher' do
      it 'sends it only when the re-engagement is turned on' do
        assistant.update!(config: assistant_config.merge('followup' => followup_config.merge('reengagement_enabled' => false)))

        expect { Captain::Followup::Dispatcher.new(now: now).perform }.not_to(change { conversation.messages.count })
      end

      it 'sends it when it is on' do
        expect { Captain::Followup::Dispatcher.new(now: now).perform }.to change { public_messages.count }.by(1)
      end
    end
  end
end
