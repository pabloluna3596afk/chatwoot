# The text a customer reads in the invitation of an appointment (the description of the Google event), written once per
# account with variables and filled in for each appointment.
#
#   text = Integrations::GoogleCalendar::InvitationText.render(template, values)
#
# Variables are {{nombre}}-style, the same style as the ones of the WhatsApp templates (see templateVariableBindings.js).
# It is a plain substitution, not Liquid: nothing of the app is reachable from a free text, and what is not a known
# variable stays as it was typed. A line whose variables are all empty (no address, no Meet link) is left out, so
# "Lugar: {{direccion}}" does not show up as an empty label.
class Integrations::GoogleCalendar::InvitationText
  TOKENS = %w[nombre primer_nombre telefono correo agente empresa fecha hora motivo direccion enlace_meet conversacion].freeze
  TOKEN = /\{\{\s*([a-z_]+)\s*\}\}/
  MAX_LENGTH = 4000

  class << self
    # The text an account has until it writes its own, in its language.
    def default_template(locale = I18n.locale)
      I18n.t('integration_apps.calendars.invitation_default', locale: locale)
    end

    def template_for(account)
      account.appointment_invitation_template.presence || default_template(locale_for(account))
    end

    # Variables of the text that are not known (a typo), so the settings can say so.
    def unknown_tokens(template)
      template.to_s.scan(TOKEN).flatten.uniq - TOKENS
    end

    def uses?(template, token)
      template.to_s.scan(TOKEN).flatten.include?(token)
    end

    def render(template, values)
      lines = template.to_s.gsub("\r\n", "\n").split("\n", -1).filter_map { |line| render_line(line, values) }
      lines.join("\n").gsub(/\n{3,}/, "\n\n").strip
    end

    # What each variable is worth for one appointment. `start_at` is in any zone, `timezone` is the account's.
    def values_for(account:, start_at:, timezone:, contact: nil, conversation: nil, agent_name: nil, summary: nil, meet_link: nil) # rubocop:disable Metrics/ParameterLists
      locale = locale_for(account)
      local = start_at.in_time_zone(timezone)
      {
        'nombre' => contact&.name, 'primer_nombre' => contact&.name.to_s.split.first&.capitalize, 'telefono' => contact&.phone_number,
        'correo' => contact&.email, 'agente' => agent_name, 'empresa' => account.name, 'fecha' => day_text(local, locale),
        'hora' => local.strftime('%H:%M'), 'motivo' => summary, 'direccion' => account.appointment_location,
        'enlace_meet' => meet_link, 'conversacion' => conversation ? "##{conversation.display_id}" : nil
      }.transform_values { |value| value.to_s.strip }
    end

    def locale_for(account)
      code = account.locale.to_s
      available = I18n.available_locales.map(&:to_s)
      [code, code.split('_').first].find { |candidate| available.include?(candidate) } || I18n.default_locale.to_s
    end

    private

    # "jueves 8 de octubre"
    def day_text(local, locale)
      weekdays = I18n.t('captain.appointments.weekdays', locale: locale)
      months = I18n.t('captain.appointments.months', locale: locale)
      I18n.t('captain.appointments.date_only', locale: locale, weekday: weekdays[local.wday], day: local.day, month: months[local.month - 1])
    end

    def render_line(line, values)
      known = line.scan(TOKEN).flatten & TOKENS
      return line if known.empty?
      return if known.all? { |token| values[token].blank? }

      line.gsub(TOKEN) { values.key?(Regexp.last_match(1)) ? values[Regexp.last_match(1)] : Regexp.last_match(0) }
    end
  end
end
