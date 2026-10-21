class Api::V1::Accounts::VariablesController < Api::V1::Accounts::BaseController
  MAX_TEXTS = 100
  MAX_CONTEXTS = 50
  MAX_RENDERS = 500
  MAX_TEXT_BYTES = 150_000
  CONTEXT_KEYS = %w[contact_id conversation_id inbox_id campaign_id flow_run_id].freeze

  before_action :validate_surface
  before_action :prevent_caching

  def index
    render json: Variables::Catalog.new(account: Current.account, surface: surface).as_json
  end

  # IDs are account scoped. conversation_id is the public display_id, as in the conversations API.
  def preview
    validate_batch!
    results = params[:contexts].map do |context|
      drops = context_factory(context).build(surface: surface)
      resolver = Variables::Resolver.new(drops: drops)
      params[:texts].map { |text| resolver.preview(text, protect_code: params[:mode] == 'content') }
    end
    render json: {
      schemaVersion: Variables::Catalog::SCHEMA_VERSION, results: results, timezone: Variables::ContextFactory.timezone(Current.account)
    }
  end

  private

  def surface
    params.fetch(:surface, 'message')
  end

  def validate_surface
    raise ActionController::ParameterMissing, :surface unless Variables::Catalog::SURFACES.key?(surface)
  end

  def prevent_caching
    response.headers['Cache-Control'] = 'no-store, private'
  end

  def validate_batch!
    validate_texts!
    validate_contexts!
    raise ActionController::ParameterMissing, :contexts if params[:texts].size * params[:contexts].size > MAX_RENDERS
    raise ActionController::ParameterMissing, :mode unless params[:mode].nil? || %w[value content].include?(params[:mode])
  end

  def validate_texts!
    texts = params[:texts]
    valid_texts = texts.is_a?(Array) && texts.size.between?(1, MAX_TEXTS) && texts.all?(String)
    raise ActionController::ParameterMissing, :texts unless valid_texts && texts.sum(&:bytesize) <= MAX_TEXT_BYTES
  end

  def validate_contexts!
    contexts = params[:contexts]
    raise ActionController::ParameterMissing, :contexts unless contexts.is_a?(Array) && contexts.size.between?(1, MAX_CONTEXTS)

    contexts.each do |context|
      validate_context!(context)
    end
  end

  def validate_context!(context)
    valid = context.is_a?(ActionController::Parameters) && (context.keys - CONTEXT_KEYS).empty?
    valid &&= context.values.all? { |id| id.is_a?(Integer) && id.positive? }
    raise ActionController::ParameterMissing, :contexts unless valid

    validate_flow_context!(context)
  end

  def validate_flow_context!(context)
    return unless context[:flow_run_id]

    raise ActionController::ParameterMissing, :contexts unless surface == 'flow' && context[:conversation_id]
  end

  def context_factory(context)
    records = load_records(context)
    validate_context_links!(records)
    authorize_records(records)
    records[:agent] = Current.user if surface == 'message'
    Variables::ContextFactory.new(account: Current.account, records: records)
  end

  def load_records(context)
    records = {}
    records[:conversation] = Current.account.conversations.find_by!(display_id: context[:conversation_id]) if context[:conversation_id]
    %i[contact inbox campaign].each do |type|
      id = context["#{type}_id"]
      records[type] = Current.account.public_send(type.to_s.pluralize).find(id) if id
    end
    records[:flow_run] = records.fetch(:conversation).flow_runs.find(context[:flow_run_id]) if context[:flow_run_id]
    records
  end

  def authorize_records(records)
    %i[conversation contact].each { |type| authorize records[type], :show? if records[type] }
    check_admin_authorization? if records[:campaign]
    authorize records[:inbox], :show? if records[:inbox] && !records[:conversation] && !records[:campaign]
  end

  def validate_context_links!(records)
    validate_conversation_links!(records)
    campaign = records[:campaign]
    return unless campaign

    raise ActionController::ParameterMissing, :contexts unless surface == 'campaign' && !records[:conversation]
    raise ActionController::ParameterMissing, :contexts if records[:inbox] && campaign.inbox_id != records[:inbox].id
  end

  def validate_conversation_links!(records)
    conversation = records[:conversation]
    return unless conversation

    %i[contact inbox].each do |type|
      record = records[type]
      next unless record

      raise ActionController::ParameterMissing, :contexts if conversation.public_send("#{type}_id") != record.id
    end
  end
end
