module Calendar::AppointmentAttributes::Definitions
  TYPES = {
    'ultima_cita' => 'datetime',
    'proxima_cita' => 'datetime',
    'proxima_cita_titulo' => 'text',
    'total_citas' => 'number',
    'estado_proxima_cita' => 'text',
    'citas_canceladas' => 'number'
  }.freeze
  CATEGORY = 'Citas'.freeze

  def self.enabled_keys(account)
    account.appointment_attributes&.fetch('enabled_keys') || []
  end
end
