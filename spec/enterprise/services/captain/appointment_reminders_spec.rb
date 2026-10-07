require 'rails_helper'

RSpec.describe Captain::AppointmentReminders do
  let(:account) { create(:account, locale: 'es') }
  let(:connection) do
    CalendarConnection.create!(
      account: account, provider: 'google', email: 'agenda@example.com', refresh_token: 'refresh',
      access_token: 'access', access_token_expires_at: 1.hour.from_now
    )
  end
  let(:appointments_config) { { 'enabled' => true, 'calendar_connection_id' => connection.id, 'calendar_id' => 'cal-1' } }
  let(:assistant) { create(:captain_assistant, account: account, name: 'Asistente de Ventas', config: { 'appointments' => appointments_config }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Ana Pérez') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:starts_at) { Time.zone.parse('2030-01-15T10:00:00-05:00') }
  let(:event) do
    connection.calendar_events.create!(
      account: account, external_calendar_id: 'cal-1', google_event_id: 'g-1', summary: 'Consulta', appointment_status: 'pending_confirmation',
      start_at: starts_at, end_at: starts_at + 30.minutes, booking_source: 'ai'
    )
  end
  let(:now) { Time.zone.parse('2030-01-10T09:00:00-05:00') }

  before { travel_to(now) }
  after { travel_back }

  # Runs the block at another moment (travel_to with a block cannot be nested inside the one above).
  def at(time)
    travel_to(time)
    yield
  ensure
    travel_to(now)
  end

  before do
    connection.connection_calendars.create!(account: account, external_id: 'cal-1', summary: 'Main', is_enabled: true)
    create(:captain_inbox, captain_assistant: assistant, inbox: inbox)
  end

  def schedule
    Captain::AppointmentReminders::Scheduler.schedule(event, assistant: assistant, conversation: conversation)
  end

  def reminder(kind)
    Captain::AppointmentReminder.find_by!(calendar_event_id: event.id, kind: kind)
  end

  describe Captain::AppointmentReminders::Scheduler do
    it 'schedules the two reminders (24 h and 3 h by default) at the minute' do
      schedule

      expect(reminder('reminder_1')).to have_attributes(scheduled_at: starts_at - 24.hours, status: 'pending')
      expect(reminder('reminder_2')).to have_attributes(scheduled_at: starts_at - 3.hours, status: 'pending')
    end

    it 'schedules each reminder as many hours before as the assistant has configured' do
      assistant.update!(config: { 'appointments' => appointments_config.merge(
        'reminder_1' => { 'enabled' => true, 'hours_before' => 48 }, 'reminder_2' => { 'enabled' => true, 'hours_before' => 1 }
      ) })

      schedule

      expect(reminder('reminder_1').scheduled_at).to eq(starts_at - 48.hours)
      expect(reminder('reminder_2').scheduled_at).to eq(starts_at - 1.hour)
    end

    it 'is idempotent' do
      schedule

      expect { schedule }.not_to change(Captain::AppointmentReminder, :count)
    end

    it 'only schedules the reminders the assistant has on' do
      assistant.update!(config: { 'appointments' => appointments_config.merge('reminder_2' => { 'enabled' => false, 'hours_before' => 3 }) })

      schedule

      expect(Captain::AppointmentReminder.where(calendar_event_id: event.id).pluck(:kind)).to eq(['reminder_1'])
    end

    it 'does not schedule anything when both reminders are off' do
      assistant.update!(config: { 'appointments' => appointments_config.merge('reminder_2' => { 'enabled' => false, 'hours_before' => 3 },
                                                                              'reminder_1' => {
                                                                                'enabled' => false, 'hours_before' => 24
                                                                              }) })

      expect { schedule }.not_to change(Captain::AppointmentReminder, :count)
    end

    it 'marks a reminder whose time already passed as skipped' do
      at(starts_at - 5.hours) { schedule }

      expect(reminder('reminder_1')).to have_attributes(status: 'skipped', skipped_reason: 'too_close')
      expect(reminder('reminder_2')).to have_attributes(status: 'pending')
    end

    it 'moves the reminders when the appointment is rescheduled' do
      schedule
      reminder('reminder_1').update!(status: 'sent', sent_at: now)

      event.update!(start_at: starts_at + 1.day, end_at: starts_at + 1.day + 30.minutes)

      expect(reminder('reminder_1')).to have_attributes(scheduled_at: starts_at, status: 'pending', sent_at: nil)
      expect(reminder('reminder_2').scheduled_at).to eq(starts_at + 1.day - 3.hours)
    end

    it 'moves the reminders by the lead time the assistant has when the appointment moves' do
      schedule
      assistant.update!(config: { 'appointments' => appointments_config.merge('reminder_2' => { 'enabled' => true, 'hours_before' => 6 }) })

      event.update!(start_at: starts_at + 1.day, end_at: starts_at + 1.day + 30.minutes)

      expect(reminder('reminder_2').scheduled_at).to eq(starts_at + 1.day - 6.hours)
    end

    it 'still handles a reminder scheduled before the lead times were editable (old kinds and old switches)' do
      legacy = Captain::AppointmentReminder.create!(
        account_id: account.id, calendar_event_id: event.id, captain_assistant_id: assistant.id, conversation_id: conversation.id,
        kind: 'reminder_24h', scheduled_at: starts_at - 24.hours
      )
      assistant.update!(config: { 'appointments' => appointments_config.merge('reminder_24h' => true, 'reminder_2h' => false) })

      event.update!(start_at: starts_at + 1.day, end_at: starts_at + 1.day + 30.minutes)

      expect(legacy.reload.scheduled_at).to eq(starts_at + 1.day - 24.hours)
      expect(assistant.appointments.reminder_enabled?('reminder_24h')).to be(true)
      expect(assistant.appointments.reminder_enabled?('reminder_2h')).to be(false)
    end

    it 'drops the pending reminders when the appointment is cancelled' do
      schedule

      event.update!(deleted_at: Time.current)

      expect(Captain::AppointmentReminder.where(calendar_event_id: event.id).pluck(:status).uniq).to eq(['cancelled'])
    end

    it 'leaves events without reminders alone' do
      expect { event.update!(summary: 'Otra') }.not_to change(Captain::AppointmentReminder, :count)
    end
  end

  describe Captain::AppointmentReminders::Dispatcher do
    before { schedule }

    it 'sends nothing before the reminder is due' do
      expect { described_class.new.perform }.not_to change(Message, :count)
    end

    it 'sends each due reminder once, even when it runs again' do
      # Let the error the dispatcher would swallow surface, so a failure here says why.
      allow(ChatwootExceptionTracker).to receive(:new).and_wrap_original { |_original, error, **_options| raise error }
      before_count = Message.count
      at(starts_at - 24.hours + 30.seconds) { described_class.new.perform }

      expect(reminder('reminder_1')).to have_attributes(status: 'sent', skipped_reason: nil)
      expect(Message.count).to eq(before_count + 1)
      at(starts_at - 24.hours + 30.seconds) { described_class.new.perform }
      expect(Message.count).to eq(before_count + 1)
      expect(reminder('reminder_2')).to have_attributes(status: 'pending')
    end

    it 'does not send the reminders of a cancelled appointment' do
      event.update!(deleted_at: Time.current)

      at(starts_at - 3.hours) { expect { described_class.new.perform }.not_to change(Message, :count) }
    end

    it 'skips a reminder instead of failing the batch when sending raises' do
      allow_any_instance_of(Captain::AppointmentReminders::Sender).to receive(:perform).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: nil))

      at(starts_at - 24.hours + 30.seconds) { described_class.new.perform }

      expect(reminder('reminder_1')).to have_attributes(status: 'skipped', skipped_reason: 'error')
    end
  end

  describe Captain::AppointmentReminders::Sender do
    let(:due_at) { starts_at - 24.hours + 30.seconds }

    def send_reminder(kind = 'reminder_1')
      at(due_at) { described_class.new(reminder(kind)).perform }
    end

    context 'when the conversation can be answered freely' do
      it 'sends one free-form message from the assistant with the three buttons' do
        schedule

        expect(send_reminder).to eq(:sent)

        message = conversation.messages.outgoing.last
        expect(message).to have_attributes(sender: assistant, private: false, content_type: 'input_select')
        expect(message.content).to include('Ana Pérez', 'Consulta', 'martes 15 de enero, 10:00')
        expect(message.content).not_to start_with('Asistente')
        expect(message.content).not_to include('Asistente de Ventas')
        expect(message.content_attributes['items'].pluck('title')).to eq(['Confirmo', 'Cambiar hora', 'Cancelar cita'])
      end

      it 'never puts the assistant name in front of what the customer receives (both reminders)' do
        schedule

        at(starts_at - 24.hours + 30.seconds) { described_class.new(reminder('reminder_1')).perform }
        at(starts_at - 3.hours + 30.seconds) { described_class.new(reminder('reminder_2')).perform }

        contents = conversation.messages.outgoing.where(private: false).order(:id).pluck(:content)
        expect(contents.size).to eq(2)
        expect(contents).to all(start_with('Hola Ana Pérez'))
        expect(contents.join).not_to include('Asistente de Ventas')
      end

      it 'words the reminder by how far ahead it goes out' do
        assistant.update!(config: { 'appointments' => appointments_config.merge(
          'reminder_1' => { 'enabled' => true, 'hours_before' => 24 }, 'reminder_2' => { 'enabled' => true, 'hours_before' => 1 }
        ) })
        schedule

        at(starts_at - 24.hours + 30.seconds) { described_class.new(reminder('reminder_1')).perform }
        at(starts_at - 1.hour + 30.seconds) { described_class.new(reminder('reminder_2')).perform }

        far, near = conversation.messages.outgoing.where(private: false).order(:id).pluck(:content)
        expect(far).to include('te recordamos tu cita', 'para el martes 15 de enero, 10:00')
        expect(near).to include('es en aproximadamente una hora', 'martes 15 de enero, 10:00')
      end

      it 'says how many hours ahead a closer reminder is' do
        schedule

        at(starts_at - 3.hours + 30.seconds) { described_class.new(reminder('reminder_2')).perform }

        expect(conversation.messages.outgoing.last.content).to include('es en unas 3 horas')
      end

      it 'puts the date on the buttons as "mar 15 ene · 10:00"' do
        schedule

        send_reminder

        values = conversation.messages.outgoing.last.content_attributes['items'].pluck('value')
        expect(values).to eq(['Confirmo · mar 15 ene · 10:00', 'Cambiar hora · mar 15 ene · 10:00', 'Cancelar cita · mar 15 ene · 10:00'])
      end

      it 'only offers to change or cancel once the customer confirmed' do
        event.update!(appointment_status: 'confirmed')
        schedule

        send_reminder

        expect(conversation.messages.outgoing.last.content_attributes['items'].pluck('title')).to eq(['Cambiar hora', 'Cancelar cita'])
      end

      it 'remembers what each button stands for' do
        schedule

        send_reminder

        value = conversation.messages.outgoing.last.content_attributes['items'].first['value']
        expect(Captain::QuickReplies.choice(conversation, value)).to eq('event_id' => 'g-1')
      end

      it 'sends no template even when paid templates are on' do
        assistant.update!(config: { 'appointments' => appointments_config, 'allow_paid_templates' => true })
        schedule

        send_reminder

        expect(conversation.messages.outgoing.last.additional_attributes).not_to have_key('template_params')
      end

      it 'does not touch the waiting time of the conversation' do
        schedule

        expect { send_reminder }.not_to(change { conversation.reload.waiting_since })
      end
    end

    context 'when the inbox is WhatsApp and the 24 h window is closed' do
      let(:templates) do
        [{ 'name' => 'recordatorio_cita', 'language' => 'es', 'status' => 'approved', 'category' => 'UTILITY', 'namespace' => 'ns',
           'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}, tu cita {{2}} es el {{3}} a las {{4}}.' }] },
         { 'name' => 'cita_con_nombres', 'language' => 'es', 'status' => 'approved', 'category' => 'UTILITY', 'namespace' => 'ns',
           'parameter_format' => 'NAMED',
           'components' => [{ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Cita: {{titulo}}' },
                            { 'type' => 'BODY', 'text' => 'Hola {{nombre}}, te esperamos el {{fecha}} a las {{hora}}. Te atiende {{asistente}}.' }] },
         { 'name' => 'pendiente', 'language' => 'es', 'status' => 'pending', 'components' => [] }]
      end
      let(:channel) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                  message_templates: templates)
      end
      let(:inbox) { channel.inbox }
      let(:template) do
        { 'name' => 'recordatorio_cita', 'language' => 'es',
          'processed_params' => { 'body' => { '1' => '{{ contact.name }}', '2' => '{{ appointment.title }}',
                                              '3' => '{{ appointment.date }}', '4' => '{{ appointment.time }}' } } }
      end
      let(:paid) { { 'allow_paid_templates' => true, 'template_reminder' => template } }

      before do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: now - 3.days)
        assistant.update!(config: { 'appointments' => appointments_config.merge(paid_config.except('allow_paid_templates')),
                                    'allow_paid_templates' => paid_config['allow_paid_templates'] == true })
        schedule
      end

      context 'with paid templates off (the default)' do
        let(:paid_config) { {} }

        it 'sends nothing to the customer and leaves one private note' do
          expect(send_reminder).to eq(:skipped)

          messages = conversation.messages.outgoing.where.not(id: conversation.messages.incoming)
          expect(messages.count).to eq(1)
          expect(messages.last).to have_attributes(private: true, sender: assistant)
          expect(messages.last.content).to include('Asistente de Ventas no envió el recordatorio', 'plantillas de pago están desactivadas')
          expect(reminder('reminder_1')).to have_attributes(status: 'skipped', skipped_reason: 'not_sent_window')
        end
      end

      context 'with paid templates on and an approved template chosen' do
        let(:paid_config) { paid }

        it 'sends the template with the appointment data' do
          expect(send_reminder).to eq(:sent)

          message = conversation.messages.outgoing.last
          expect(message.private).to be(false)
          expect(message.content).to eq('Hola Ana Pérez, tu cita Consulta es el martes 15 de enero a las 10:00.')
          expect(message.additional_attributes['template_params']).to include(
            'name' => 'recordatorio_cita', 'language' => 'es',
            'processed_params' => { 'body' => { '1' => 'Ana Pérez', '2' => 'Consulta', '3' => 'martes 15 de enero', '4' => '10:00' } }
          )
          expect(message.content_attributes.fetch('whatsapp_template')).to include('name' => 'recordatorio_cita', 'category' => 'UTILITY')
          expect(reminder('reminder_1')).to have_attributes(status: 'sent')
        end
      end

      context 'with a mapping of the variables of the template' do
        let(:mapped) do
          { 'header' => { 'titulo' => '{{ appointment.title }}' },
            'body' => { 'nombre' => '{{ contact.name }}', 'fecha' => '{{ appointment.date }}', 'hora' => '{{ appointment.time }}',
                        'asistente' => 'el equipo de {{ assistant.name }}' } }
        end
        let(:template) { { 'name' => 'cita_con_nombres', 'language' => 'es', 'processed_params' => mapped } }
        let(:paid_config) { paid }

        it 'fills named variables of the body and of the header from the mapping' do
          expect(send_reminder).to eq(:sent)

          message = conversation.messages.outgoing.last
          expect(message.content).to eq('Hola Ana Pérez, te esperamos el martes 15 de enero a las 10:00. Te atiende el equipo de Asistente de Ventas.')
          expect(message.content_attributes.dig('whatsapp_template', 'header')).to eq('format' => 'TEXT', 'text' => 'Cita: Consulta')
          expect(message.additional_attributes['template_params']['processed_params']).to eq(
            'header' => { 'titulo' => 'Consulta' },
            'body' => { 'nombre' => 'Ana Pérez', 'fecha' => 'martes 15 de enero', 'hora' => '10:00',
                        'asistente' => 'el equipo de Asistente de Ventas' }
          )
        end

        context 'when the template changed in Meta and a variable is no longer mapped' do
          # Saved settings cannot be like this (the validator rejects them), which is the point: the template changed after.
          before do
            broken = template.merge('processed_params' => mapped.merge('body' => mapped['body'].except('hora')))
            assistant.update_columns(config: { 'appointments' => appointments_config.merge('template_reminder' => broken), # rubocop:disable Rails/SkipsModelValidations
                                               'allow_paid_templates' => true })
          end

          it 'does not send it and leaves a private note' do
            expect(send_reminder).to eq(:skipped)

            expect(reminder('reminder_1')).to have_attributes(status: 'skipped', skipped_reason: 'template_changed')
            expect(conversation.messages.where(private: true).last.content).to include('la plantilla cambió en Meta')
            expect(conversation.messages.outgoing.where(private: false).where.not(id: conversation.messages.incoming).count).to eq(0)
          end
        end
      end

      context 'with paid templates on but no template chosen' do
        let(:paid_config) { { 'allow_paid_templates' => true } }

        it 'skips with a private note' do
          expect(send_reminder).to eq(:skipped)

          expect(conversation.messages.where(private: true).last.content).to include('no hay una plantilla elegida')
          expect(reminder('reminder_1').skipped_reason).to eq('no_template')
        end
      end

      context 'with a template that is not approved' do
        let(:paid_config) { paid.merge('template_reminder' => { 'name' => 'pendiente', 'language' => 'es' }) }

        it 'skips with a private note' do
          expect(send_reminder).to eq(:skipped)

          expect(reminder('reminder_1').skipped_reason).to eq('template_unavailable')
          expect(conversation.messages.where(private: true)).to exist
        end
      end

      context 'when the account reached its daily proactive cap' do
        let(:paid_config) { paid }

        before { account.update!(settings: account.settings.merge('proactive_daily_send_cap' => 0)) }

        it 'waits without sending or marking the reminder' do
          expect { send_reminder }.not_to(change { conversation.messages.count })

          expect(send_reminder).to eq(:waiting)
          expect(reminder('reminder_1')).to have_attributes(status: 'pending')
        end
      end
    end

    context 'when the appointment or the feature is gone' do
      before { schedule }

      it 'skips a reminder of an appointment that already started' do
        expect(at(starts_at + 1.minute) { described_class.new(reminder('reminder_1')).perform }).to eq(:skipped)
        expect(reminder('reminder_1').skipped_reason).to eq('event_gone')
      end

      it 'skips when the assistant turned that reminder off after it was scheduled' do
        assistant.update!(config: { 'appointments' => appointments_config.merge('reminder_1' => { 'enabled' => false, 'hours_before' => 24 }) })

        expect(send_reminder).to eq(:skipped)
        expect(reminder('reminder_1').skipped_reason).to eq('disabled')
      end
    end

    it 'never enqueues the Panel AI follow-up job' do
      schedule

      expect { send_reminder }.not_to have_enqueued_job(Calendar::NotifyPanelAiFollowupJob)
    end
  end
end
