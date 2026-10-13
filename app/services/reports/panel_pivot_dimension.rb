class Reports::PanelPivotDimension
  attr_reader :names

  def initialize(account:, pivot:, timezone_offset:)
    @account = account
    @pivot = pivot
    @attribute = pivot.fetch(:row_attribute)
    @timezone_offset = timezone_offset
    @names = system_names
    validate_attributes!
  end

  def ids(conversation)
    case @attribute
    when 'agent' then [conversation.assignee_id || 0]
    when 'inbox' then [conversation.inbox_id].compact
    when 'team' then [conversation.team_id].compact
    when 'label' then label_ids(conversation)
    else [custom_id(conversation)]
    end
  end

  def resolution_ids(event)
    return [event.user_id || 0] if @attribute == 'agent'
    return [event.inbox_id].compact if @attribute == 'inbox'

    ids(event.conversation)
  end

  def column_value(conversation)
    key = @pivot[:column_attribute]&.delete_prefix('ca:')
    key.present? ? normalize(conversation.custom_attributes[key]) : ''
  end

  def column_values(discovered)
    return [] if @pivot[:column_attribute].blank?
    return @pivot[:column_values] if @pivot[:column_values].present?

    definition = definition_for(@pivot[:column_attribute])
    ordered = Array(definition.attribute_values) & discovered
    (ordered + (discovered - ordered)).first(12)
  end

  private

  def validate_attributes!
    if @attribute.start_with?('ca:', 'contact_ca:') && definition_for(@attribute).nil?
      raise CustomExceptions::InvalidPanelPivot, 'unknown_pivot_row_attribute'
    end
    return if @pivot[:column_attribute].blank? || definition_for(@pivot[:column_attribute])

    raise CustomExceptions::InvalidPanelPivot, 'unknown_pivot_attribute'
  end

  def definition_for(attribute)
    contact = attribute.start_with?('contact_ca:')
    key = attribute.delete_prefix(contact ? 'contact_ca:' : 'ca:')
    @account.custom_attribute_definitions.find_by(
      attribute_key: key, attribute_model: contact ? :contact_attribute : :conversation_attribute
    )
  end

  def system_names
    case @attribute
    when 'agent' then @account.users.map { |user| [user.id, user.available_name] }.to_h.merge(0 => I18n.t('reports.panels.unassigned_agent'))
    when 'inbox' then @account.inboxes.pluck(:id, :name).to_h
    when 'team' then @account.teams.pluck(:id, :name).to_h
    when 'label' then @account.labels.pluck(:id, :title).to_h
    else {}
    end
  end

  def label_ids(conversation)
    @labels_by_title ||= @names.invert
    conversation.cached_label_list.to_s.split(',').filter_map { |title| @labels_by_title[title.strip] }
  end

  def custom_id(conversation)
    value = @attribute == 'created_at' ? date_value(conversation) : attribute_value(conversation)
    id = "#{@attribute}:#{value.empty? ? '__blank__' : "value:#{CGI.escape(value)}"}"
    @names[id] = value
    id
  end

  def attribute_value(conversation)
    contact = @attribute.start_with?('contact_ca:')
    record = contact ? conversation.contact : conversation
    key = @attribute.delete_prefix(contact ? 'contact_ca:' : 'ca:')
    normalize(record.custom_attributes[key])
  end

  def date_value(conversation)
    day = conversation.created_at.getlocal((@timezone_offset * 3600).to_i).to_date
    case @pivot.fetch(:row_granularity, 'day')
    when 'week' then day.beginning_of_week(:monday).iso8601
    when 'month' then day.beginning_of_month.iso8601
    else day.iso8601
    end
  end

  def normalize(value)
    return value.map(&:to_s).find(&:present?).to_s if value.is_a?(Array)

    value.to_s
  end
end
