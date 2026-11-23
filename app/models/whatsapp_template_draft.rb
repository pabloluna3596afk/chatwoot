class WhatsappTemplateDraft < ApplicationRecord
  MAX_DEFINITION_BYTES = 1.megabyte
  STRING_LIMITS = { title: 100, name: 512, language: 20, category: 20, parameter_format: 20, waba_id: 100, source_remote_id: 100 }.freeze

  belongs_to :account
  belongs_to :preferred_channel, class_name: 'Channel::Whatsapp', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true
  belongs_to :source_draft, class_name: 'WhatsappTemplateDraft', optional: true
  has_many :submissions, class_name: 'WhatsappTemplateSubmission', dependent: :restrict_with_error
  has_many :calendar_template_resources, dependent: :nullify
  has_one_attached :media

  scope :active, -> { where(archived_at: nil) }

  validates :name, uniqueness: { scope: [:account_id, :waba_id, :language], conditions: -> { active } },
                   if: -> { archived_at.nil? && [name, language, waba_id].all?(&:present?) }
  validates :name, length: { maximum: 512 }
  validate :string_types
  validate :definition_shape
  validate :bindings_shape
  validate :account_ownership
  validate :preferred_channel_destination
  validate :destination
  validate :local_media

  private

  def string_types
    errors.add(:title, :invalid) if title.nil?
    STRING_LIMITS.each do |field, limit|
      value = public_send("#{field}_before_type_cast")
      errors.add(field, :invalid) unless value.nil? || valid_string?(value, limit, field)
    end
  end

  def valid_string?(value, limit, field)
    value.is_a?(String) && value.length <= limit && (field == :title || value.present?)
  end

  def definition_shape
    errors.add(:definition, :invalid) unless Whatsapp::TemplateDraftDefinition.valid?(definition)
    errors.add(:definition, :too_long, count: MAX_DEFINITION_BYTES) if definition.to_json.bytesize > MAX_DEFINITION_BYTES
  end

  def bindings_shape
    return if variable_bindings.is_a?(Hash) && variable_bindings.to_json.bytesize <= MAX_DEFINITION_BYTES && variable_bindings.values.all?(String)

    errors.add(:variable_bindings, :invalid)
  end

  def account_ownership
    return unless account

    [:created_by, :updated_by].each do |field|
      errors.add(field, :invalid) if invalid_author?(field)
    end
    errors.add(:source_draft, :invalid) if source_draft && source_draft.account_id != account_id
  end

  def invalid_author?(field)
    user = public_send(field)
    user && public_send("will_save_change_to_#{field}_id?") && !account.account_users.exists?(user_id: user.id)
  end

  def destination
    return if archived_at?
    return unless account
    return if waba_id.nil? || destination_channels.exists?

    errors.add(:waba_id, :invalid)
  end

  def preferred_channel_destination
    return unless preferred_channel_id
    return errors.add(:preferred_channel, :invalid) if preferred_channel&.account_id != account_id

    errors.add(:preferred_channel, :invalid) if archived_at.nil? && !valid_preferred_channel?
  end

  def valid_preferred_channel?
    return false unless preferred_channel

    preferred_channel.account_id == account_id && preferred_channel.provider == 'whatsapp_cloud' &&
      preferred_channel.provider_config['business_account_id'] == waba_id
  end

  public

  def destination_channels
    account.whatsapp_channels.where(provider: 'whatsapp_cloud').where("provider_config ->> 'business_account_id' = ?", waba_id)
  end

  private

  def local_media
    return unless media.attached?

    format = Whatsapp::TemplateHeaderMedia::FORMATS.find { |_key, rules| rules[:content_types].include?(media.blob.content_type) }&.first
    Whatsapp::TemplateHeaderMedia.validate!(format, media.blob.content_type, media.blob.byte_size)
  rescue Whatsapp::TemplateHeaderMedia::InvalidFile
    errors.add(:media, :invalid)
  end
end
