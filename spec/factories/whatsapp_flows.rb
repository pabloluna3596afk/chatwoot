FactoryBot.define do
  factory :whatsapp_flow do
    account
    sequence(:name) { |n| "Formulario #{n}" }
    categories { ['LEAD_GENERATION'] }
    definition do
      { 'schema_version' => 1,
        'screens' => [{ 'title' => 'Tus datos', 'button' => 'Enviar',
                        'blocks' => [{ 'type' => 'short_text', 'key' => 'nombre', 'label' => 'Nombre', 'required' => true }] }] }
    end
  end
end
