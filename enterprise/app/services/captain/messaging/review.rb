require 'digest'

class Captain::Messaging::Review
  def initialize(assistant, inbox)
    @assistant = assistant
    @inbox = inbox
    @channel = inbox.channel
    @entry = assistant.messaging.entry_for(inbox.id)
    @waba_id = @channel.provider_config.to_h['business_account_id'].to_s if whatsapp?
  end

  # Marketing, authentication, unsupported and link-bearing templates require a separate choice.
  def activation_snapshot
    return { 'templates' => {}, 'flows' => {} } unless whatsapp? && @waba_id.present?

    templates = @channel.message_templates.to_a.each_with_object({}) do |template, reviewed|
      reviewed[template_key(template)] = fingerprint(template) if activation_template?(template)
    end
    flows = eligible_flows.each_with_object({}) do |flow, reviewed|
      publication = publication_for(flow)
      reviewed["#{@waba_id}:#{flow.id}"] = publication.published_version if publication
    end
    { 'templates' => templates, 'flows' => flows }
  end

  def allow!(kind:, key:)
    return false unless whatsapp? && @waba_id.present? && @entry

    reviewed = @entry.fetch('reviewed', { 'templates' => {}, 'flows' => {} })
    reviewed['templates'] ||= {}
    reviewed['flows'] ||= {}
    return false unless allow_resource(reviewed, kind, key)

    @entry['reviewed'] = reviewed
    true
  end

  def fingerprint(template)
    Digest::SHA256.hexdigest({ category: template['category'], components: template['components'],
                               parameter_format: template['parameter_format'] }.to_json)
  end

  def publication_for(flow)
    flow.whatsapp_flow_publications.to_a.find do |publication|
      publication.waba_id == @waba_id && publication.status == 'published'
    end
  end

  private

  def allow_resource(reviewed, kind, key)
    case kind
    when 'template' then allow_template(reviewed, key)
    when 'flow' then allow_flow(reviewed, key)
    else false
    end
  end

  def allow_template(reviewed, key)
    template = @channel.message_templates.to_a.find { |item| template_key(item) == Captain::Messaging::TemplateKey.normalize(key) }
    return false unless template && allowable_template?(template)

    key = template_key(template)
    reviewed['templates'][key] = fingerprint(template)
    @entry['included_marketing'] = Array(@entry['included_marketing']) | [key] if template['category'].to_s.upcase == 'MARKETING'
    true
  end

  def allow_flow(reviewed, key)
    flow_id = key.to_s.split(':').last.to_i
    return false unless key == "#{@waba_id}:#{flow_id}"

    flow = eligible_flows.find { |item| item.id == flow_id }
    publication = flow && publication_for(flow)
    return false unless publication

    reviewed['flows'][key] = publication.published_version
    true
  end

  def activation_template?(template)
    template['status'].to_s.upcase == 'APPROVED' && template['category'].to_s.upcase == 'UTILITY' &&
      allowable_template?(template) && !Captain::TemplateSupport.url_button?(template) && !quality_red?
  end

  def allowable_template?(template)
    template['status'].to_s.upcase == 'APPROVED' && template['category'].to_s.upcase != 'AUTHENTICATION' &&
      Captain::TemplateSupport.supported?(template)
  end

  def eligible_flows
    return [] unless whatsapp?

    Whatsapp::Flows::SendFlowService.eligible_for(@inbox).includes(:whatsapp_flow_publications).to_a
  rescue Whatsapp::Flows::SendFlowService::Error
    []
  end

  def whatsapp?
    @channel.is_a?(Channel::Whatsapp)
  end

  def template_key(template)
    Captain::Messaging::TemplateKey.for(@waba_id, template)
  end

  def quality_red?
    @channel.phone_number_health.to_h['quality_rating'].to_s.upcase == 'RED'
  end
end
