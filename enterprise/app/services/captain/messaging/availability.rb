require 'digest'

# The sole current policy for which Captain messaging resources are usable in an inbox.
class Captain::Messaging::Availability
  Item = Struct.new(:resource, :state, :missing, :processed_params, :note, :reason, keyword_init: true) do
    def available?
      state == 'available'
    end
  end

  def initialize(assistant, inbox)
    @assistant = assistant
    @inbox = inbox
    @settings = assistant.messaging
    @entry = @settings.entry_for(inbox.id)
    @channel = inbox.channel
  end

  def templates
    return [] unless whatsapp?

    Array(@channel.message_templates).map { |template| template_item(template) }
  end

  def flows
    return [] unless whatsapp?

    eligible = eligible_flows.index_by(&:id)
    @assistant.account.whatsapp_flows.order(:name).map do |flow|
      key = flow.id.to_s
      resource = { 'id' => flow.id, 'name' => flow.name }
      state = if @entry&.fetch('enabled', false) != true
                'disabled'
              elsif !eligible.key?(flow.id)
                'not_published_here'
              elsif excluded_flow?(flow.id)
                'excluded'
              else
                reviewed_flow_state(flow)
              end
      note = if @settings.mode(@inbox.id) == 'list'
               @settings.flow(@inbox.id, flow.id)&.fetch('purpose', nil)
             else
               @settings.note_for(@inbox.id, "#{waba_id}:flow:#{key}")
             end
      Item.new(resource: resource, state: state, note: note)
    end
  rescue Whatsapp::Flows::SendFlowService::Error
    []
  end

  def eligible_flows
    return WhatsappFlow.none unless cloud_whatsapp?

    Whatsapp::Flows::SendFlowService.eligible_for(@inbox)
  end

  private

  def template_item(template)
    name = template['name'].to_s
    language = template['language'].to_s
    scoped_identity = "#{waba_id}:#{name}|#{language}"
    resource = { 'name' => name, 'language' => language, 'category' => template['category'] }
    state = template_state(template, scoped_identity)
    processed_params = nil
    missing = []
    if state == 'available'
      if @settings.mode(@inbox.id) == 'list'
        processed_params = @settings.template(@inbox.id, name, language)&.fetch('processed_params', nil)
        missing = Captain::TemplateMessage.unmapped(template, processed_params)
      else
        processed_params, missing = Captain::Messaging::TemplateParams.new(@assistant, @inbox, template).resolve
      end
      state = 'needs_data' if missing.any?
    end
    note = if @settings.mode(@inbox.id) == 'list'
             @settings.template(@inbox.id, name, language)&.fetch('purpose', nil)
           else
             @settings.note_for(@inbox.id, "template:#{scoped_identity}")
           end
    Item.new(resource: resource, state: state, missing: missing, processed_params: processed_params, note: note)
  end

  def template_state(template, scoped_identity)
    return 'disabled' unless @entry&.fetch('enabled', false) == true

    category = template['category'].to_s.upcase
    return 'authentication' if category == 'AUTHENTICATION'

    status = template['status'].to_s.upcase
    return 'pending' if %w[PENDING IN_APPEAL].include?(status)
    return 'rejected' if %w[REJECTED PAUSED DISABLED].include?(status)
    return 'unavailable' unless status == 'APPROVED'
    return 'unsupported' unless Captain::TemplateSupport.supported?(template)

    identity = "#{template['name']}|#{template['language']}"
    return 'excluded' if excluded_template?(scoped_identity)
    return 'marketing_off' if category == 'MARKETING' && !marketing_included?(scoped_identity)
    return 'unavailable' if quality_red?
    return 'needs_review' if @settings.mode(@inbox.id) == 'auto' && Captain::TemplateSupport.url_button?(template)
    return 'available' if @settings.mode(@inbox.id) == 'list' && @settings.template(@inbox.id, template['name'], template['language'])
    return 'new' if @settings.mode(@inbox.id) == 'auto' && !reviewed_templates.key?(scoped_identity)

    return 'unavailable' unless @settings.mode(@inbox.id) == 'auto'
    return 'changed' if reviewed_templates[scoped_identity] != template_fingerprint(template)

    'available'
  end

  def template_fingerprint(template)
    Digest::SHA256.hexdigest({ category: template['category'], components: template['components'],
                               parameter_format: template['parameter_format'] }.to_json)
  end

  def reviewed_templates
    @entry.dig('reviewed', 'templates').to_h
  end

  def reviewed_flow_state(flow)
    key = "#{waba_id}:#{flow.id}"
    return 'available' if @settings.mode(@inbox.id) == 'list' && @settings.flow(@inbox.id, flow.id)
    return 'new' unless @entry.dig('reviewed', 'flows').to_h.key?(key)

    publication = flow.whatsapp_flow_publications.find_by(waba_id: waba_id, status: 'published')
    return 'changed' unless publication && @entry.dig('reviewed', 'flows')[key] == publication.published_version
    return 'unavailable' unless @settings.mode(@inbox.id) == 'auto'

    'available'
  end

  def excluded_template?(scoped_identity)
    excluded = Array(@entry.dig('excluded', 'templates'))
    excluded.include?(scoped_identity)
  end

  def marketing_included?(scoped_identity)
    included = Array(@entry['included_marketing'])
    included.include?(scoped_identity)
  end

  def excluded_flow?(id)
    excluded = Array(@entry.dig('excluded', 'flows'))
    excluded.include?("#{waba_id}:#{id}")
  end

  def quality_red?
    @channel.phone_number_health.to_h['quality_rating'].to_s.upcase == 'RED'
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
