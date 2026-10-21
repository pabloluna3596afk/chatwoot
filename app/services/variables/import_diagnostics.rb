class Variables::ImportDiagnostics
  ERROR_CODE = 'undefined_custom_attributes'.freeze

  def initialize(data_import:)
    @data_import = data_import
  end

  def check(scope:, values:)
    defined = @data_import.account.custom_attribute_definitions.where(attribute_model: "#{scope}_attribute").pluck(:attribute_key)
    unknown = values.keys.map(&:to_s) - defined
    return if unknown.empty?

    @data_import.with_lock do
      warning = @data_import.import_errors.find_or_initialize_by(error_code: ERROR_CODE, source_object_type: scope)
      keys = (Array(warning.details['keys']) | unknown).sort
      next if warning.persisted? && keys == warning.details['keys']

      warning.assign_attributes(
        message: I18n.t('variables.import_undefined', locale: @data_import.account.locale, scope: scope, keys: keys.join(', ')),
        details: { kind: 'warning', keys: keys }
      )
      warning.save!
    end
  end
end
