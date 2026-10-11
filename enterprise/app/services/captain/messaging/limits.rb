# The limits of one conversation for what Captain sends (see Captain::Messaging::SendService): 10 minutes between Flows,
# 3 Flows and 1 template in 24 hours, and a Flow waiting for its answer blocks another one unless the customer asked
# for it again. Everything is counted from the messages Captain sent, which carry `additional_attributes.captain_messaging`.
class Captain::Messaging::Limits
  KEY = 'captain_messaging'.freeze
  FLOW_GAP = 10.minutes
  WINDOW = 24.hours
  MAX_FLOWS = 3
  MAX_TEMPLATES = 1

  Denial = Struct.new(:code, :retry_after)

  # The messages Captain sent in a conversation with the Flow or template tools.
  def self.sent_by_captain(conversation)
    conversation.messages.outgoing.where("additional_attributes -> '#{KEY}' IS NOT NULL")
  end

  def initialize(conversation:, request:, now:)
    @conversation = conversation
    @request = request
    @now = now
  end

  # nil when the send is within the limits, or a Denial.
  def denial
    @request.flow? ? flow_denial : template_denial
  end

  private

  def recent(kind)
    self.class.sent_by_captain(@conversation).where('created_at >= ?', @now - WINDOW)
        .where("additional_attributes -> '#{KEY}' ->> 'kind' = ?", kind)
  end

  def flow_denial
    flows = recent('flow')
    last = flows.order(:created_at).last
    return Denial.new('pending_flow') if last && !@request.resend_requested && unanswered?(last)
    return Denial.new('rate_limit', wait_for(last)) if last && wait_for(last).positive?

    Denial.new('rate_limit') if flows.count >= MAX_FLOWS
  end

  def wait_for(flow_message)
    ((flow_message.created_at + FLOW_GAP) - @now).ceil
  end

  def template_denial
    Denial.new('rate_limit') if recent('template').count >= MAX_TEMPLATES
  end

  # A Flow is answered when the customer's answer was saved after it was sent (Whatsapp::Flows::SaveResponseService).
  def unanswered?(flow_message)
    answers = @conversation.messages.incoming.where('created_at > ?', flow_message.created_at).pluck(:content_attributes)
    answers.none? { |attributes| attributes.is_a?(Hash) && attributes['whatsapp_flow_saved'] }
  end
end
