class Captain::Llm::LanguageDetectionSchema < Schematist::Schema
  string :language, description: "Language tag, like en, pt-BR or zh-TW; 'und' when it cannot be told"
end
