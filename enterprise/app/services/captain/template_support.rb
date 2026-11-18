# The server-side equivalent of captainTemplates.js#isSupportedForCaptain.
class Captain::TemplateSupport
  STATIC_BUTTONS = %w[QUICK_REPLY PHONE_NUMBER URL].freeze

  def self.supported?(template)
    Array(template['components']).all? do |component|
      case component['type'].to_s.upcase
      when 'BODY', 'FOOTER'
        true
      when 'HEADER'
        component['format'].to_s.upcase == 'TEXT'
      when 'BUTTONS'
        Array(component['buttons']).all? do |button|
          STATIC_BUTTONS.include?(button['type'].to_s.upcase) && button['url'].to_s.exclude?('{{')
        end
      else
        false
      end
    end
  end

  def self.url_button?(template)
    Array(template['components']).any? do |component|
      component['type'].to_s.upcase == 'BUTTONS' && Array(component['buttons']).any? do |button|
        button['type'].to_s.upcase == 'URL'
      end
    end
  end
end
