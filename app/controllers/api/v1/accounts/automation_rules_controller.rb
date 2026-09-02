class Api::V1::Accounts::AutomationRulesController < Api::V1::Accounts::BaseController
  include AttachmentConcern

  before_action :check_authorization
  before_action :fetch_automation_rule, only: [:show, :update, :destroy, :clone]
  before_action :ensure_execution_delay_allowed, only: [:create, :update]

  def index
    @automation_rules = Current.account.automation_rules
  end

  def show; end

  def create
    blobs, actions, error = validate_and_prepare_attachments(params[:actions])
    return render_could_not_create_error(error) if error

    @automation_rule = Current.account.automation_rules.new(automation_rules_permit)
    assign_rule_payload(@automation_rule, actions: actions, conditions: params[:conditions] || [])

    return render_could_not_create_error(@automation_rule.errors.messages) unless @automation_rule.valid?

    lint = lint_for(@automation_rule)
    return render_lint_failed(lint) unless lint.ok?

    @automation_rule.save!
    attach_files(@automation_rule, blobs)
    @lint_warnings = lint.warnings
  end

  def update
    blobs, actions, error = validate_and_prepare_attachments(params[:actions], @automation_rule)
    return render_could_not_create_error(error) if error

    ActiveRecord::Base.transaction { save_updated_rule(blobs, actions) }
  end

  # Lint without saving — lets the editor surface problems while you type.
  def lint
    rule = Current.account.automation_rules.new(automation_rules_permit)
    assign_rule_payload(rule, actions: params[:actions] || [], conditions: params[:conditions] || [])
    rule.id = params[:id] if params[:id].present?

    result = lint_for(rule)
    render json: {
      ok: result.ok?,
      errors: serialize_findings(result.errors),
      warnings: serialize_findings(result.warnings)
    }, status: :ok
  end

  # Dry run: which active rules would fire on this conversation, in what order.
  # Executes nothing.
  def simulate
    conversation = conversation_to_simulate
    return render json: { error: 'Conversation not found' }, status: :not_found if conversation.blank?

    event_name = params[:event_name].to_s
    return render_unsupported_event unless AutomationRules::SimulationService::SIMULATABLE_EVENTS.include?(event_name)

    result = AutomationRules::SimulationService.new(
      account: Current.account,
      conversation: conversation,
      event_name: event_name
    ).perform

    render json: serialize_simulation(result), status: :ok
  end

  def destroy
    @automation_rule.destroy!
    head :ok
  end

  def clone
    automation_rule = Current.account.automation_rules.find_by(id: params[:automation_rule_id])
    # Dropping the delay here would clone a paused wait into a rule that fires instantly on the
    # next matching event, so refuse rather than rewrite what the rule means.
    return render_delayed_automations_error if automation_rule.execution_delay.present? && !delayed_automations_enabled?

    @automation_rule = automation_rule.dup
    @automation_rule.save!
  end

  private

  def save_updated_rule(blobs, actions)
    @automation_rule.assign_attributes(automation_rules_permit)
    # Only what the request actually sent: on an update a missing key means
    # "unchanged", not "clear it".
    assign_rule_payload(@automation_rule,
                        actions: params[:actions] ? actions : nil,
                        conditions: params[:conditions])

    lint = lint_for(@automation_rule)
    unless lint.ok?
      render_lint_failed(lint)
      raise ActiveRecord::Rollback
    end

    @automation_rule.save!
    attach_files(@automation_rule, blobs)
    @lint_warnings = lint.warnings
  rescue ActiveRecord::Rollback
    raise
  rescue StandardError => e
    Rails.logger.error e
    render_could_not_create_error(@automation_rule.errors.messages)
  end

  def assign_rule_payload(rule, actions: nil, conditions: nil)
    rule.actions = actions unless actions.nil?
    rule.conditions = conditions unless conditions.nil?
    rule.schedule = params[:schedule] if params.key?(:schedule)
  end

  def attach_files(rule, blobs)
    blobs.each { |blob| rule.files.attach(blob) }
  end

  def conversation_to_simulate
    Current.account.conversations.find_by(display_id: params[:conversation_display_id]) ||
      Current.account.conversations.find_by(id: params[:conversation_id])
  end

  def render_unsupported_event
    render json: {
      error: 'Unsupported event_name',
      supported: AutomationRules::SimulationService::SIMULATABLE_EVENTS
    }, status: :unprocessable_entity
  end

  def serialize_simulation(result)
    {
      event_name: result.event_name,
      conversation_id: result.conversation_id,
      evaluated_count: result.evaluated_count,
      matches: result.matches.map { |m| { rule_id: m.rule_id, rule_name: m.rule_name, order: m.order, actions: m.actions } }
    }
  end

  def automation_rules_permit
    permitted_attributes = [:name, :description, :event_name, :active]
    permitted_attributes << :execution_delay if delayed_automations_enabled?

    params.permit(
      *permitted_attributes,
      conditions: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }],
      actions: [:action_name, { action_params: [] }],
      schedule: {}
    )
  end

  def ensure_execution_delay_allowed
    return if delayed_automations_enabled?
    return if params[:execution_delay].blank?

    render_delayed_automations_error
  end

  def render_delayed_automations_error
    render json: { error: 'Delayed automations are not enabled for this account.' }, status: :unprocessable_entity
  end

  def delayed_automations_enabled?
    Current.account.feature_enabled?('delayed_automations')
  end

  def lint_for(rule)
    AutomationRules::LintService.new(
      account: Current.account,
      rules: Current.account.automation_rules.to_a,
      subject: rule
    ).perform
  end

  def render_lint_failed(lint)
    render json: {
      error: I18n.t('automation_rules.lint_failed', default: 'Automation rule failed validation'),
      automation_rule_errors: serialize_findings(lint.errors),
      automation_rule_warnings: serialize_findings(lint.warnings)
    }, status: :unprocessable_entity
  end

  def serialize_findings(findings)
    Array(findings).map do |f|
      { rule_id: f.rule_id, rule_name: f.rule_name, code: f.code, message_key: f.message_key, meta: f.meta }
    end
  end

  def fetch_automation_rule
    @automation_rule = Current.account.automation_rules.find_by(id: params[:id])
  end
end
