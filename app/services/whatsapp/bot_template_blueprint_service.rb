class Whatsapp::BotTemplateBlueprintService
  WHATSAPP_API_VERSION = 'v14.0'.freeze

  BLUEPRINTS = {
    'palu_reenganche' => {
      name: 'palu_reenganche',
      language: 'es',
      category: 'MARKETING',
      body: 'Hola {{1}}, hace un tiempo conversamos y queríamos saber si aún te podemos ayudar. Respondé este mensaje para continuar.',
      body_example: [['María']],
      buttons: []
    },
    'palu_cita_confirmacion' => {
      name: 'palu_cita_confirmacion',
      language: 'es',
      category: 'UTILITY',
      body: 'Hola {{1}}, te agendamos "{{2}}" el {{3}} a las {{4}}. ¿Confirmás tu asistencia?',
      body_example: [['María', 'Consulta', '23/08/2026', '10:00']],
      buttons: %w[Confirmar Reagendar Cancelar]
    },
    'palu_cita_recordatorio' => {
      name: 'palu_cita_recordatorio',
      language: 'es',
      category: 'UTILITY',
      body: 'Hola {{1}}, recordatorio: "{{2}}" es el {{3}} a las {{4}}. ¿Seguís disponible?',
      body_example: [['María', 'Consulta', '24/08/2026', '10:00']],
      buttons: %w[Confirmar Reagendar Cancelar]
    }
  }.freeze

  def initialize(whatsapp_channel)
    @whatsapp_channel = whatsapp_channel
  end

  def submit(blueprint_id)
    blueprint = BLUEPRINTS[blueprint_id.to_s]
    return { success: false, error: 'Unknown blueprint' } if blueprint.blank?

    response = HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: build_request_body(blueprint).to_json
    )
    process_response(response, blueprint)
  end

  private

  def build_request_body(blueprint)
    components = [
      {
        type: 'BODY',
        text: blueprint[:body],
        example: { body_text: blueprint[:body_example] }
      }
    ]
    if blueprint[:buttons].any?
      components << {
        type: 'BUTTONS',
        buttons: blueprint[:buttons].map { |text| { type: 'QUICK_REPLY', text: text } }
      }
    end

    {
      name: blueprint[:name],
      language: blueprint[:language],
      category: blueprint[:category],
      components: components
    }
  end

  def process_response(response, blueprint)
    if response.success?
      {
        success: true,
        template_id: response['id'],
        template_name: response['name'] || blueprint[:name],
        language: blueprint[:language],
        status: response['status'] || 'PENDING'
      }
    else
      Rails.logger.error "WhatsApp blueprint submit failed: #{response.code} - #{response.body}"
      { success: false, error: 'Template creation failed', response_body: response.body }
    end
  end

  def business_account_path
    "#{api_base_path}/#{WHATSAPP_API_VERSION}/#{@whatsapp_channel.provider_config['business_account_id']}"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{@whatsapp_channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base_path
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
