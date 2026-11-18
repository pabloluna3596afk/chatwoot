class Captain::Messaging::ResourceAvailability
  def initialize(assistant, inbox, request)
    @inbox = inbox
    @settings = assistant.messaging
    @availability = Captain::Messaging::Availability.new(assistant, inbox)
    @request = request
  end

  def item
    @item ||= @request.flow? ? flow_item : template_item
  end

  def permission_denial
    resource = item
    return ['missing_variables', resource.missing.join(', ')] if resource&.state == 'needs_data'
    return ['unavailable', nil] if listed_resource? && !resource&.available?

    nil
  end

  private

  def flow_item
    @availability.flows.find { |item| item.resource['id'] == @request.resource }
  end

  def template_item
    @availability.templates.find do |item|
      item.resource['name'] == @request.resource[:name] &&
        item.resource['language'].to_s.casecmp?(@request.resource[:language].to_s)
    end
  end

  def listed_resource?
    return false unless @settings.mode(@inbox.id) == 'list'

    if @request.flow?
      @settings.flow(@inbox.id, @request.resource)
    else
      @settings.template(@inbox.id, @request.resource[:name], @request.resource[:language])
    end
  end
end
