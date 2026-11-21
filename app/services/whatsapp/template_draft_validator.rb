class Whatsapp::TemplateDraftValidator
  LANGUAGES = %w[af sq ar az bn bg ca zh_CN zh_HK zh_TW hr cs da nl en en_GB en_US et fil fi fr ka de el gu ha he hi hu id ga it ja kn kk
                 rw_RW ko ky_KG lo lv lt mk ms ml mr nb fa pl pt_BR pt_PT pa ro ru sr sk sl es es_AR es_CL es_CO es_CR es_DO es_EC es_HN
                 es_MX es_PA es_PE es_ES es_UY sw sv ta te th tr uk ur uz vi zu].freeze
  LOCAL_MEDIA_HANDLE = 'local_attachment'.freeze

  def initialize(draft)
    @draft = draft
  end

  def snapshot!
    validate_identity!
    form = @draft.definition.deep_dup
    prepare_media!(form)
    validate_named_variables!(form)
    invalid!('unsupported_components') if form.fetch('preserved', {}).values.any?(&:present?)
    { 'payload' => build_payload(form), 'preferred_channel_id' => @draft.preferred_channel_id,
      'media_blob_id' => @draft.media.attached? ? @draft.media.blob.id : nil,
      'variable_bindings' => @draft.variable_bindings.deep_dup }
  end

  private

  def validate_identity!
    @draft.validate!
    invalid!('archived') if @draft.archived_at?
    invalid!('destination_required') unless @draft.waba_id.present? && @draft.destination_channels.exists?
    invalid!('invalid_name') unless Whatsapp::TemplateComponentsBuilder.valid_name?(@draft.name)
    invalid!('invalid_language') unless LANGUAGES.include?(@draft.language)
    invalid!('invalid_category') unless Whatsapp::TemplateComponentsBuilder::CATEGORIES.include?(@draft.category)
  end

  def build_payload(form)
    builder = Whatsapp::TemplateComponentsBuilder.new(**form.deep_symbolize_keys, category: @draft.category,
                                                                                  parameter_format: @draft.parameter_format)
    components = builder.components
    validate_button_groups!(components)
    payload = { name: @draft.name, language: @draft.language, category: @draft.category,
                components: components, parameter_format: builder.parameter_format }
    payload.deep_stringify_keys
  end

  def prepare_media!(form)
    format = form.dig('header', 'format')
    return unless Whatsapp::TemplateComponentsBuilder::MEDIA_FORMATS.include?(format)

    invalid!('header_media_required') unless @draft.media.attached?
    blob = @draft.media.blob
    Whatsapp::TemplateHeaderMedia.validate!(format, blob.content_type, blob.byte_size)
    form['header']['handle'] = LOCAL_MEDIA_HANDLE
  end

  # New drafts follow Meta's documented lowercase/underscore names; legacy endpoints retain their contract.
  def validate_named_variables!(form)
    text = [form.dig('header', 'text'), form.dig('body', 'text')].join(' ')
    tokens = text.scan(Whatsapp::TemplateComponentsBuilder::VARIABLE).flatten
    invalid!('variable_name_invalid') if tokens.grep_v(/\A\d+\z/).any? { |name| !name.match?(/\A[a-z_]+\z/) }
  end

  def invalid!(code)
    raise Whatsapp::TemplateComponentsBuilder::Invalid, code
  end

  def validate_button_groups!(components)
    buttons = components.find { |component| component[:type] == 'BUTTONS' }&.fetch(:buttons) || []
    groups = buttons.map { |button| button[:type] == 'QUICK_REPLY' }.chunk(&:itself).count
    invalid!('invalid_button_grouping') if groups > 2
  end
end
