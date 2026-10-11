# The one place where Captain sends a Flow or a template to a customer. It checks everything again with the data of the
# moment (what the owner allows, the Flow or template itself, the 24 h window, the paid-messages switch, the limits of
# Captain::Messaging::Limits), so nothing the model says, or an old setting, can widen a permission. Nothing is sent
# unless every check passes. A send takes one place of the account's daily cap (Automations::ProactiveSendCap)
# atomically; it is given back when the message is not created.
#
# What was sent is the record: the message carries `additional_attributes.captain_messaging` (assistant, the customer
# message it answers, kind, resource and a fingerprint), so the same customer message never sends the same thing twice.
class Captain::Messaging::SendService
  KEY = Captain::Messaging::Limits::KEY

  Result = Struct.new(:status, :code, :message, :retry_after, :detail, keyword_init: true) do
    def sent?
      status == :sent
    end

    def duplicate?
      status == :duplicate
    end

    def denied?
      status == :denied
    end
  end

  def initialize(conversation:, assistant:, request:, now: Time.current)
    @conversation = conversation
    @assistant = assistant
    @request = request
    @now = now
  end

  def perform
    return deny('invalid_params') unless request.valid?

    result = nil
    # Locking a record that has unsaved changes is refused, so what is in memory is dropped first.
    conversation.reload.with_lock { result = run }
    result
  end

  # The same checks as #perform, without sending or taking a place of the daily cap: what the tools ask to tell the model
  # early. nil when the send would be allowed now; otherwise a denied result, or a duplicate when it was already sent.
  def precheck
    return deny('invalid_params') unless request.valid?

    conversation.reload
    existing = sent_message
    return Result.new(status: :duplicate, message: existing) if existing

    permission_denial || resource_denial || limit_denial
  end

  private

  attr_reader :conversation, :assistant, :request, :now

  delegate :account, :inbox, to: :conversation
  delegate :flow?, to: :request

  def run
    existing = sent_message
    return Result.new(status: :duplicate, message: existing) if existing

    denied = permission_denial || resource_denial || limit_denial
    denied || deliver
  end

  def fingerprint
    parts = [account.id, assistant.id, inbox.id, conversation.id, request.responding_to_message_id, request.kind, request.resource_key]
    Digest::SHA256.hexdigest(parts.join('|'))
  end

  def sent_message
    Captain::Messaging::Limits.sent_by_captain(conversation).where("additional_attributes -> '#{KEY}' ->> 'fingerprint' = ?", fingerprint).first
  end

  # --- permission: what the owner allows, now

  def settings
    @settings ||= assistant.messaging
  end

  def permission_denial
    return deny('disabled') unless inbox.channel_type == 'Channel::Whatsapp' && linked? && settings.entry_for(inbox.id)

    deny('not_allowed') unless allowed_entry
  end

  def linked?
    assistant.captain_inboxes.exists?(inbox_id: inbox.id)
  end

  def allowed_entry
    if flow?
      settings.flow(inbox.id, request.resource)
    else
      settings.template(inbox.id, request.resource[:name], request.resource[:language])
    end
  end

  # --- the Flow or the template itself, now

  def resource_denial
    flow? ? flow_denial : template_denial
  end

  def flow_denial
    return deny('unavailable') unless published_flow

    deny('window_closed') unless conversation.can_reply?
  end

  def published_flow
    @published_flow ||= Whatsapp::Flows::SendFlowService.new(conversation: conversation, sender: assistant)
                                                        .eligible_flows.find_by(id: request.resource)
  rescue Whatsapp::Flows::SendFlowService::Error
    nil
  end

  def template_denial
    return deny('unavailable') unless template_entry
    return deny('paid_off') unless assistant.allow_paid_templates?

    built
    nil
  rescue Captain::TemplateMessage::MappingMismatch => e
    deny('missing_variables', detail: e.message)
  end

  def template_entry
    @template_entry ||= Captain::TemplateMessage.approved(inbox, allowed_entry)
  end

  # [template_params payload, the text of the message], from the texts the owner saved for each variable.
  def built
    @built ||= Captain::TemplateMessage.build(template_entry, allowed_entry['processed_params'],
                                              Captain::TemplateMessage.drops(conversation, assistant))
  end

  def limit_denial
    limit = Captain::Messaging::Limits.new(conversation: conversation, request: request, now: now).denial
    deny(limit.code, retry_after: limit.retry_after) if limit
  end

  # --- sending

  def cap
    @cap ||= Automations::ProactiveSendCap.new(account)
  end

  def deliver
    return deny('rate_limit') unless cap.reserve!

    message = flow? ? send_flow : send_template
    note
    Result.new(status: :sent, message: message)
  rescue Whatsapp::Flows::SendFlowService::Error
    cap.release!
    deny('unavailable')
  rescue StandardError
    cap.release!
    raise
  end

  def audit
    { 'assistant_id' => assistant.id, 'responding_to_message_id' => request.responding_to_message_id, 'kind' => request.kind,
      'resource' => request.resource_key, 'fingerprint' => fingerprint, 'at' => now.utc.iso8601 }
  end

  def send_flow
    params = { 'whatsapp_flow_id' => request.resource }
    params['body'] = request.intro_text if request.intro_text.present?
    message = Whatsapp::Flows::SendFlowService.new(conversation: conversation, sender: assistant, params: params).perform
    message.update!(additional_attributes: message.additional_attributes.merge(KEY => audit))
    message
  end

  def send_template
    payload, text = built
    create_message(text, additional_attributes: { 'template_params' => payload, KEY => audit })
  end

  # The private note that says what Captain sent, next to the message.
  def note
    name = flow? ? published_flow.name : request.resource[:name]
    content = I18n.t("captain.messaging.note_#{request.kind}", locale: account.locale, name: name)
    create_message(content, private: true, preserve_waiting_since: true)
  end

  def create_message(content, **attributes)
    conversation.messages.create!(message_type: :outgoing, account_id: account.id, inbox_id: inbox.id, sender: assistant,
                                  content: content, **attributes)
  end

  def deny(code, retry_after: nil, detail: nil)
    Result.new(status: :denied, code: code, retry_after: retry_after, detail: detail,
               message: I18n.t("captain.messaging.errors.#{code}", locale: account.locale, default: code))
  end
end
