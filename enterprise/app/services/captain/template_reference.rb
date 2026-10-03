# The template an assistant's settings point to: { 'name', 'language', 'processed_params' }, where `processed_params`
# holds the text of each variable of the template, as automations do (see Captain::TemplateMessage). Casting keeps what
# cannot be cast as given, so the validators reject it instead of silently replacing it.
module Captain::TemplateReference
  COMPONENTS = %w[body header].freeze

  module_function

  # nil, or { 'name' => , 'language' => , 'processed_params' => { 'body' => { '1' => 'text' }, 'header' => { ... } } }
  def cast(value)
    return if value.blank?
    return value unless hash_like?(value)

    reference = value.to_h.stringify_keys
    cast = { 'name' => reference['name'].to_s, 'language' => reference['language'].to_s }
    cast['processed_params'] = cast_params(reference['processed_params']) unless reference['processed_params'].nil?
    cast
  end

  def cast_params(params)
    return params unless hash_like?(params)

    params.to_h.stringify_keys.slice(*COMPONENTS).transform_values do |texts|
      hash_like?(texts) ? texts.to_h.to_h { |key, text| [key.to_s, text.to_s] } : texts
    end
  end

  # The reasons a reference cannot be saved. `account` is used to check the texts against the real template (every
  # variable of the body and of a text header needs one); when the template is not found in the account it is only
  # checked by shape.
  def errors(reference, account)
    return [] if reference.nil?
    return ['must have a name and a language'] unless valid_reference?(reference)

    shape_errors(reference['processed_params']) + coverage_errors(reference, account)
  end

  def valid_reference?(reference)
    reference.is_a?(Hash) && reference['name'].present? && reference['language'].present?
  end

  def shape_errors(params)
    return [] if params.nil?
    return ['processed_params must be an object'] unless params.is_a?(Hash) && params.values.all?(Hash)

    params.flat_map do |component, texts|
      texts.filter_map do |name, text|
        "variable #{component}.#{name} is not valid Liquid" unless Captain::TemplateMessage.valid_liquid?(text)
      end
    end
  end

  def coverage_errors(reference, account)
    entry = Captain::TemplateMessage.find_in_account(account, reference)
    return [] if entry.blank?

    Captain::TemplateMessage.unmapped(entry, reference['processed_params']).map { |key| "variable #{key} is empty" }
  end

  def hash_like?(value)
    value.respond_to?(:to_h) && !value.is_a?(Array) && !value.is_a?(String)
  end
end
