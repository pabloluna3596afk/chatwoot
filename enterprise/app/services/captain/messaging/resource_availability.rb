class Captain::Messaging::ResourceAvailability
  def initialize(assistant, inbox, request)
    @availability = Captain::Messaging::Availability.new(assistant, inbox)
    @request = request
  end

  def item
    @request.flow? ? flow_item : template_item
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
end
