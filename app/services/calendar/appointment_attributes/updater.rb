class Calendar::AppointmentAttributes::Updater
  def initialize(contact:)
    @contact = contact
  end

  def perform
    return if @contact.nil?

    @contact.with_lock do
      keys = writable_keys
      return if keys.empty?

      attributes = @contact.custom_attributes.merge(values.slice(*keys))
      @contact.update!(custom_attributes: attributes) unless attributes == @contact.custom_attributes
    end
  end

  private

  def writable_keys
    account = Account.find(@contact.account_id)
    keys = Calendar::AppointmentAttributes::Definitions.enabled_keys(account)
    return [] if keys.empty?

    account.custom_attribute_definitions.contact_attribute.where(attribute_key: keys)
           .pluck(:attribute_key, :attribute_display_type).filter_map do |key, type|
      key if type == Calendar::AppointmentAttributes::Definitions::TYPES.fetch(key)
    end
  end

  def values
    now = Time.current
    events = CalendarEvent.kept.where(account_id: @contact.account_id, contact_id: @contact.id)
    previous = events.where(start_at: ..now).maximum(:start_at)
    upcoming = events.where('start_at > ?', now).order(:start_at, :id).pick(:start_at, :summary)
    {
      'ultima_cita' => previous&.utc&.iso8601,
      'proxima_cita' => upcoming&.first&.utc&.iso8601,
      'proxima_cita_titulo' => upcoming&.last,
      'total_citas' => events.count
    }
  end
end
