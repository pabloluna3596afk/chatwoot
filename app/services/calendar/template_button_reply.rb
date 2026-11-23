# What a customer does to an appointment by tapping a quick-reply button of the confirmation template of the activation kit
# (Calendar::ActivationKit): Confirm confirms it, Cancel cancels it (Google included) and Reschedule asks the team for a new
# time without touching it. Called by the WhatsApp incoming flow for `button` messages only.
#
# Which appointment: the one the template message was sent for (`calendar_event_id`, saved by CustomerNotice). Meta says which
# message the button belongs to (`context`); without it, the latest template message of the conversation.
#
# Rules: a button of anything else is ignored; an appointment that already passed or was cancelled is not changed (the team is
# told); the same answer twice does nothing new; and nothing here may break the processing of the incoming message.
class Calendar::TemplateButtonReply
  ANSWERS = %i[confirm reschedule cancel].freeze

  def initialize(message)
    @message = message
    @conversation = message.conversation
  end

  def perform
    notice = template_message
    answer = notice && answer_from(@message.content, notice)
    record = answer && appointment_of(notice)
    return if record.blank? || notice.additional_attributes['customer_answer'] == answer.to_s

    I18n.with_locale(@conversation.account.locale) do
      remember(notice, answer) unless respond(answer, record) == :failed
    end
  rescue StandardError => e
    Rails.logger.error("Calendar template button failed: #{e.class}")
  end

  private

  def answer_from(text, notice)
    label = text.to_s.strip
    return if label.blank?

    snapshot = notice.content_attributes['calendar_template_resource']
    action = snapshot ? snapshot_action(label, snapshot) : legacy_action(label)
    ANSWERS.find { |answer| answer.to_s == action }
  end

  def snapshot_action(label, snapshot)
    snapshot.fetch('actions').find { |button, _answer| button.casecmp?(label) }&.last
  end

  def legacy_action(label)
    index = Calendar::ActivationKit::TEMPLATES.values.filter_map do |template|
      template[:buttons].index { |button| button.casecmp?(label) }
    end.first
    ANSWERS[index]&.to_s if index
  end

  def template_message
    reply_to = @message.content_attributes['in_reply_to']
    scope = @conversation.messages.where(message_type: :outgoing)
    if reply_to.present?
      notice = scope.find_by(id: reply_to)
      return notice if template_notice?(notice)

      return
    end

    scope.where("additional_attributes -> 'template_params' ->> 'name' IN (?) OR " \
                "(content_attributes #>> '{}')::jsonb -> 'calendar_template_resource' ->> 'function' IN (?)",
                Calendar::ActivationKit::REPLY_TEMPLATE_NAMES, %w[confirmation reminder])
         .where("additional_attributes ->> 'calendar_event_id' IS NOT NULL").order(:id).last
  end

  def template_notice?(notice)
    return false unless notice

    identity = notice.content_attributes.dig('calendar_template_resource', 'function')
    (%w[confirmation reminder].include?(identity) ||
      Calendar::ActivationKit::REPLY_TEMPLATE_NAMES.include?(notice.additional_attributes.dig('template_params', 'name'))) &&
      notice.additional_attributes['calendar_event_id'].present?
  end

  def appointment_of(notice)
    CalendarEvent.find_by(id: notice.additional_attributes['calendar_event_id'], account_id: @conversation.account_id,
                          conversation_id: @conversation.id)
  end

  def respond(answer, record)
    return say(:answer_ignored_cancelled, record) if record.discarded?
    return say(:answer_ignored_past, record) if record.start_at.present? && record.start_at < Time.current

    send(:"on_#{answer}", record)
  end

  def on_confirm(record)
    record.with_lock do
      return if record.appointment_status == 'confirmed'

      before = record.appointment_status
      record.update!(appointment_status: 'confirmed')
      record.activities.create!(account_id: record.account_id, user: nil, action: 'updated',
                                details: { 'appointment_status' => [before, 'confirmed'], 'source' => 'customer' })
    end
    say(:customer_confirmed, record)
  end

  def on_cancel(record)
    service(record).cancel_by_customer!(record)
    say(:customer_cancelled, record)
  rescue Integrations::GoogleCalendar::Client::Error => e
    Rails.logger.error("Calendar customer cancel failed in Google: #{e.code}")
    say(:customer_cancel_failed, record)
    :failed
  end

  def on_reschedule(record)
    say(:customer_reschedule_requested, record)
  end

  def service(record)
    Integrations::GoogleCalendar::EventService.new(account: record.account, user: nil, connection: record.calendar_connection)
  end

  def say(key, record)
    content = I18n.t("conversations.activity.calendar.#{key}", event_title: record.summary, contact_name: @conversation.contact&.name)
    @conversation.messages.create!(
      account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :activity,
      content: content,
      content_attributes: ActivityMessageNames.attributes(content, @conversation.contact&.name, record.summary)
    )
  end

  # Saved on the template message so the same tap is not processed again.
  def remember(notice, answer)
    notice.update!(additional_attributes: notice.additional_attributes.merge('customer_answer' => answer.to_s))
  end
end
