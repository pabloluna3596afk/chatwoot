FactoryBot.define do
  factory :whatsapp_template_draft do
    account
    title { 'Recordatorio' }
    sequence(:name) { |number| "recordatorio_#{number}" }
    language { 'es' }
    category { 'UTILITY' }
    definition { { 'body' => { 'text' => 'Tu cita está confirmada.' } } }
  end
end
