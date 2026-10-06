class Whatsapp::Flows::SaveResponseService
  def initialize(incoming, payload)
    @incoming = incoming
    @payload = payload
    @saved = []
    @skipped = []
  end

  def perform
    outgoing = Whatsapp::Flows::ResponseToken.resolve(@payload['flow_token'], @incoming)
    return unless outgoing

    @incoming.with_lock do
      return if @incoming.content_attributes['whatsapp_flow_saved']

      flow = outgoing.additional_attributes.fetch('whatsapp_flow')
      @contact = outgoing.conversation.contact
      @contact.with_lock { save_fields(flow.fetch('fields')) }
      outgoing.conversation.messages.create!(account_id: outgoing.account_id, inbox_id: outgoing.inbox_id,
                                             message_type: :outgoing, private: true, content: note(flow.fetch('name')))
      @incoming.update!(content_attributes: @incoming.content_attributes.merge('whatsapp_flow_saved' => true))
    end
  end

  private

  def save_fields(fields)
    pending = fields.dup
    (fields.length + 1).times do
      @saved = []
      accepted = pending.select { |field| assign_field(field) }
      return if accepted.empty?

      begin
        Contact.transaction(requires_new: true) { @contact.save! }
        return
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # A concurrent update can claim an email/document after validation. The savepoint keeps the webhook transaction usable.
        @contact.reload
        pending = accepted
      end
    end
    raise ActiveRecord::RecordNotUnique, 'Could not save flow response'
  end

  def assign_field(field)
    target = field.fetch('save_to').fetch('target')
    value = @payload[field.fetch('key')]
    reason = invalid_reason(field, target, value)
    return skip(target, reason) if reason

    value = value.join(', ') if field['type'] == 'checkbox'
    value = BigDecimal(value.to_s) if field['input'] == 'number' && custom_attribute(target)&.number?
    previous = @contact.attributes.slice(*contact_attributes(target, value).keys.map(&:to_s))
    @contact.assign_attributes(contact_attributes(target, value))
    unless @contact.valid?
      @contact.assign_attributes(previous)
      return skip(target, 'invalid')
    end
    @saved << "#{target}: #{value}"
    true
  end

  def skip(target, reason)
    @skipped << "#{target}: #{translate(reason)}"
    false
  end

  def invalid_reason(field, target, value)
    return 'blank' if value != false && value.blank?
    return 'invalid' unless Whatsapp::Flows::SaveTargets.compatible?(field, target, @contact.account)
    return 'invalid' unless valid_value?(field, value)

    column = target.delete_prefix('contact.')
    column = 'phone_number' if column == 'phone'
    if %w[email phone_number document_number].include?(column)
      others = @contact.account.contacts.where.not(id: @contact.id)
      used = column == 'email' ? others.where('LOWER(email) = ?', value.downcase).exists? : others.where(column => value).exists?
      return 'used' if used
    end
    nil
  end

  def valid_value?(field, value)
    case field['type']
    when 'optin' then [true, false].include?(value)
    when 'checkbox' then value.is_a?(Array) && value.all? { |item| field.fetch('options').any? { |option| option['id'] == item } }
    when 'dropdown', 'radio' then value.is_a?(String) && field.fetch('options').any? { |option| option['id'] == value }
    when 'date'
      value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/) && Date.iso8601(value)
    else
      return false unless value.is_a?(String)
      return true unless field['input'] == 'number'

      BigDecimal(value).finite?
    end
  rescue ArgumentError
    false
  end

  def custom_attribute(target)
    Whatsapp::Flows::SaveTargets.attribute(@contact.account, target)
  end

  def contact_attributes(target, value)
    if target.start_with?(Whatsapp::Flows::SaveTargets::CUSTOM_PREFIX)
      { custom_attributes: @contact.custom_attributes.merge(target.delete_prefix(Whatsapp::Flows::SaveTargets::CUSTOM_PREFIX) => value) }
    elsif %w[contact.company_name contact.city].include?(target)
      { additional_attributes: @contact.additional_attributes.merge(target.delete_prefix('contact.') => value) }
    else
      { (target == 'contact.phone' ? 'phone_number' : target.delete_prefix('contact.')) => value }
    end
  end

  def note(name)
    [translate('completed', name: name),
     (@saved.any? ? translate('saved', fields: @saved.join('; ')) : nil),
     (@skipped.any? ? translate('skipped', fields: @skipped.join('; ')) : nil)].compact.join("\n")
  end

  def translate(key, **options)
    I18n.t("conversations.messages.whatsapp.flow_save.#{key}", **options)
  end
end
