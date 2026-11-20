class Captain::DecisionSerializer
  PUBLIC_FIELDS = %w[id version anchor_message_id kind outcome origin trigger reason_code reason_text reason_locale occurred_at due_at].freeze

  def initialize(decision, user_context)
    @decision = decision
    @context = user_context
  end

  def as_json
    decision.attributes.slice(*PUBLIC_FIELDS).merge(
      evidence: safe_evidence, afterwards: Captain::Decisions::Afterwards.build(decision),
      technical: technical, can_change_setting: can_change_setting?
    ).merge(setting_destination)
  end

  private

  attr_reader :decision

  def safe_evidence
    facts = decision.evidence.slice(*Captain::Decisions::PayloadValidator::FLAGS, *Captain::Decisions::PayloadValidator::ENUMS.keys, 'tools')
    facts.merge(settings: decision.settings_snapshot.slice(*Captain::Decisions::PayloadValidator::SETTINGS),
                sources: Captain::Decisions::Sources.build(account: @context[:account], assistant_id: decision.assistant_id,
                                                           evidence: decision.evidence))
  end

  def technical
    details = decision.technical_details
    details = details.merge({ 'model' => decision.agent_session.llm_model }.compact) if decision.agent_session
    Captain::Decisions::TechnicalSummary.build(user: @context[:user], account_user: @context[:account_user], details: details,
                                               applicable: %w[rule time].exclude?(decision.origin))
  end

  def can_change_setting?
    @context[:account_user]&.administrator? == true && decision.assistant.present? &&
      decision.assistant.account_id == @context[:account].id && Captain::AssistantPolicy.new(@context, decision.assistant).update?
  end

  def setting_destination
    return {} unless can_change_setting?

    { setting_destination: "/app/accounts/#{decision.account_id}/captain/#{decision.assistant_id}/settings" }
  end
end
