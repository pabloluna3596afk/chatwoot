# Shared, read-only data sources for body and text-header template variables.
class Whatsapp::TemplateVariableSources
  def initialize(channel)
    @channel = channel
  end

  def for(template)
    bindings = Whatsapp::TemplateVariableBindingsService.new(@channel).for_template(template['name'])
    Array(template['components']).each_with_object({ 'body' => {}, 'header' => {} }) do |component, result|
      kind = component['type'].to_s.downcase
      next unless result.key?(kind)
      next if kind == 'header' && component['format'].present? && component['format'].to_s.upcase != 'TEXT'

      component['text'].to_s.scan(Whatsapp::TemplateVariableBindingsService::VARIABLE).flatten.uniq.each do |name|
        result[kind][name] = source_for(name, bindings)
      end
    end
  end

  private

  def source_for(name, bindings)
    if bindings.key?(name)
      path = bindings[name]
      return { source: 'binding', path: path } if catalog_paths.include?(path)

      return { source: 'missing', path: nil }
    end
    descriptor = descriptors.find { |entry| entry[:group] != 'appointment' && entry[:aliases].include?(name) } unless name.match?(/\A\d+\z/)
    return { source: 'alias', path: expression_path(descriptor) } if descriptor

    { source: 'missing', path: nil }
  end

  def descriptors
    @descriptors ||= Variables::Catalog.new(account: @channel.account, surface: 'message').as_json[:variables]
  end

  def expression_path(entry)
    entry[:expression].delete_prefix('{{ ').delete_suffix(' }}')
  end

  def catalog_paths
    @catalog_paths ||= descriptors.select { |entry| entry[:available] }.flat_map { |entry| [expression_path(entry), *entry[:legacyPaths]] }.uniq
  end
end
