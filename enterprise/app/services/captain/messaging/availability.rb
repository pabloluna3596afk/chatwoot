# The sole current policy for which Captain messaging resources are usable in an inbox.
class Captain::Messaging::Availability
  Item = Struct.new(:resource, :state, :missing, :processed_params, :note, :reason, keyword_init: true) do
    def available?
      state == 'available'
    end
  end

  def initialize(assistant, inbox, request_cache: {})
    @assistant = assistant
    @inbox = inbox
    @settings = assistant.messaging
    @entry = @settings.entry_for(inbox.id)
    @channel = inbox.channel
    @request_cache = request_cache
    @review = Captain::Messaging::Review.new(assistant, inbox)
  end

  def templates
    return [] unless whatsapp?

    Captain::Messaging::TemplateAvailability.new(@assistant, @inbox, @settings, @entry, @review).items
  end

  def flows
    return [] unless whatsapp?

    eligible = eligible_flows.map(&:id)
    all_flows.map { |flow| flow_item(flow, eligible) }
  rescue Whatsapp::Flows::SendFlowService::Error
    []
  end

  def eligible_flows
    return WhatsappFlow.none unless cloud_whatsapp? && waba_id.present?

    @request_cache[[:eligible_flows, @inbox.account_id, waba_id]] ||= Whatsapp::Flows::SendFlowService.eligible_for(@inbox).to_a
  end

  def all_flows
    @request_cache[[:all_flows, @assistant.account_id]] ||= @assistant.account.whatsapp_flows.includes(:whatsapp_flow_publications).order(:name).to_a
  end

  private

  def flow_item(flow, eligible_ids)
    Item.new(resource: { 'id' => flow.id, 'name' => flow.name }, state: flow_state(flow, eligible_ids),
             note: flow_note(flow))
  end

  def flow_state(flow, eligible_ids)
    return 'disabled' unless @entry&.fetch('enabled', false) == true
    return 'not_published_here' unless eligible_ids.include?(flow.id)
    return 'excluded' if excluded_flow?(flow.id)

    reviewed_flow_state(flow)
  end

  def flow_note(flow)
    return @settings.flow(@inbox.id, flow.id)&.fetch('purpose', nil) if @settings.mode(@inbox.id) == 'list'

    @settings.note_for(@inbox.id, "#{waba_id}:flow:#{flow.id}")
  end

  def reviewed_flow_state(flow)
    return list_flow_state(flow) if @settings.mode(@inbox.id) == 'list'

    key = "#{waba_id}:#{flow.id}"
    return 'new' unless @entry.dig('reviewed', 'flows').to_h.key?(key)

    publication = @review.publication_for(flow)
    return 'changed' unless publication && reviewed_flow_version(key) == publication.published_version

    'available'
  end

  def list_flow_state(flow)
    @settings.flow(@inbox.id, flow.id) ? 'available' : 'excluded'
  end

  def reviewed_flow_version(key)
    @entry.dig('reviewed', 'flows', key)
  end

  def excluded_flow?(id)
    excluded = Array(@entry.dig('excluded', 'flows'))
    excluded.include?("#{waba_id}:#{id}")
  end

  def waba_id
    @waba_id ||= @channel.provider_config.to_h['business_account_id'].to_s
  end

  def whatsapp?
    @channel.is_a?(Channel::Whatsapp)
  end

  def cloud_whatsapp?
    whatsapp? && @channel.provider == 'whatsapp_cloud'
  end
end
