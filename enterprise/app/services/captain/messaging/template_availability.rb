class Captain::Messaging::TemplateAvailability
  Item = Captain::Messaging::Availability::Item

  def initialize(assistant, inbox, settings, entry, review)
    @assistant = assistant
    @inbox = inbox
    @settings = settings
    @entry = entry
    @review = review
    @channel = inbox.channel
    @waba_id = @channel.provider_config.to_h['business_account_id'].to_s
  end

  def items
    @channel.message_templates.to_a.map { |template| item(template) }
  end

  private

  def item(template)
    identity = "#{@waba_id}:#{template['name']}|#{template['language']}"
    state = state_for(template, identity)
    params, missing, sources = resolved_params(template, state)
    state = 'needs_data' if state == 'available' && missing.any?
    Item.new(resource: resource(template), state: state, missing: missing, processed_params: params, sources: sources,
             note: note_for(template, identity))
  end

  def resource(template)
    { 'name' => template['name'].to_s, 'language' => template['language'].to_s, 'category' => template['category'] }
  end

  def resolved_params(template, state)
    return [nil, [], {}] unless state == 'available'

    if @settings.mode(@inbox.id) == 'list'
      params = @settings.template(@inbox.id, template['name'], template['language'])&.fetch('processed_params', nil)
      [params, Captain::TemplateMessage.unmapped(template, params), legacy_sources(template, params)]
    else
      Captain::Messaging::TemplateParams.new(@assistant, @inbox, template).resolve
    end
  end

  def legacy_sources(template, params)
    Captain::TemplateMessage.variables(template).each_with_object({ 'body' => {}, 'header' => {} }) do |variable, sources|
      next if params&.dig(variable.component, variable.name).blank?

      sources[variable.component][variable.name] = 'legacy'
    end
  end

  def note_for(template, identity)
    if @settings.mode(@inbox.id) == 'list'
      @settings.template(@inbox.id, template['name'], template['language'])&.fetch('purpose', nil)
    else
      @settings.note_for(@inbox.id, "template:#{identity}")
    end
  end

  def state_for(template, identity)
    pre_review_state(template, identity) || review_state(template, identity) || available_state(template, identity)
  end

  def pre_review_state(template, identity)
    return 'disabled' unless @entry&.fetch('enabled', false) == true
    return 'authentication' if template['category'].to_s.upcase == 'AUTHENTICATION'
    return meta_state(template) unless template['status'].to_s.upcase == 'APPROVED'
    return 'unsupported' unless Captain::TemplateSupport.supported?(template)
    return 'excluded' if excluded?(identity)
  end

  def review_state(template, identity)
    return 'changed' if changed?(template, identity)
    return 'needs_review' if needs_review?(template, identity)
    return 'marketing_off' if marketing_off?(template, identity)
    return 'unavailable' if quality_red?
  end

  def available_state(template, identity)
    return 'available' if listed?(template)
    return 'excluded' if @settings.mode(@inbox.id) == 'list'
    return 'new' if new_auto_resource?(identity)

    @settings.mode(@inbox.id) == 'auto' ? 'available' : 'unavailable'
  end

  def meta_state(template)
    status = template['status'].to_s.upcase
    return 'pending' if %w[PENDING IN_APPEAL].include?(status)
    return 'rejected' if %w[REJECTED PAUSED DISABLED].include?(status)

    'unavailable'
  end

  def excluded?(identity)
    Array(@entry.dig('excluded', 'templates')).include?(identity)
  end

  def changed?(template, identity)
    reviewed = reviewed_templates[identity]
    @settings.mode(@inbox.id) == 'auto' && reviewed && reviewed != @review.fingerprint(template)
  end

  def needs_review?(template, identity)
    @settings.mode(@inbox.id) == 'auto' && Captain::TemplateSupport.url_button?(template) && !reviewed_templates.key?(identity)
  end

  def marketing_off?(template, identity)
    @settings.mode(@inbox.id) == 'auto' && template['category'].to_s.upcase == 'MARKETING' &&
      Array(@entry['included_marketing']).exclude?(identity)
  end

  def listed?(template)
    @settings.mode(@inbox.id) == 'list' && @settings.template(@inbox.id, template['name'], template['language'])
  end

  def new_auto_resource?(identity)
    @settings.mode(@inbox.id) == 'auto' && !reviewed_templates.key?(identity)
  end

  def reviewed_templates
    @entry.dig('reviewed', 'templates').to_h
  end

  def quality_red?
    @channel.phone_number_health.to_h['quality_rating'].to_s.upcase == 'RED'
  end
end
