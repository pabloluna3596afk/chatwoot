module Captain::Messaging::TemplateKey
  def self.for(waba_id, template)
    "#{waba_id}:#{template.fetch('name')}|#{template.fetch('language').downcase}"
  end

  def self.normalize(key)
    prefix, separator, language = key.rpartition('|')
    "#{prefix}#{separator}#{language.downcase}"
  end
end
