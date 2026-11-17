require 'rails_helper'

RSpec.describe AdministratorNotifications::AccountNotificationMailer do
  let(:account) { create(:account, name: 'Test Account') }
  let(:mailer) { described_class.with(account: account) }
  let(:class_instance) { described_class.new }

  before do
    allow(described_class).to receive(:new).and_return(class_instance)
    allow(class_instance).to receive(:smtp_config_set_or_development?).and_return(true)
    account.custom_attributes['marked_for_deletion_at'] = 7.days.from_now.iso8601
    account.save!
  end

  describe '#account_deletion_user_initiated' do
    it 'sets the correct subject for user-initiated deletion' do
      mail = mailer.account_deletion_user_initiated(account, 'manual_deletion')
      expect(mail.subject).to eq('Your Chatwoot account deletion has been scheduled')
    end
  end

  describe '#account_deletion_for_inactivity' do
    it 'sets the correct subject for system-initiated deletion' do
      mail = mailer.account_deletion_for_inactivity(account, 'Account Inactive')
      expect(mail.subject).to eq('Your Chatwoot account is scheduled for deletion due to inactivity')
    end
  end

  describe '#format_deletion_date' do
    it 'formats a valid date string' do
      date_str = '2024-12-31T12:00:00Z'
      formatted = described_class.new.send(:format_deletion_date, date_str)
      expect(formatted).to eq('December 31, 2024')
    end

    it 'handles blank dates' do
      formatted = described_class.new.send(:format_deletion_date, nil)
      expect(formatted).to eq('Unknown')
    end

    it 'handles invalid dates' do
      formatted = described_class.new.send(:format_deletion_date, 'invalid-date')
      expect(formatted).to eq('Unknown')
    end
  end

  describe '#usage_limit_warning' do
    it 'localizes the administrator alert in the account language' do
      account.update!(locale: 'es')
      allow(class_instance).to receive(:send_notification)

      Current.account = account
      mailer.usage_limit_warning(:copilot, 80, 4, 5).message

      expect(class_instance).to have_received(:send_notification).with(
        'El uso de sugerencias de Copilot alcanzó el 80% del límite del plan',
        action_url: anything,
        meta: { 'message' => 'La cuenta Test Account ha usado 4 de 5 sugerencias de Copilot en este período.' }
      )
    end
  end

  describe '#automation_rule_paused_by_cap' do
    let(:rule) { create(:automation_rule, account: account, name: 'Birthday reminder') }
    let(:administrator) { create(:user, account: account, role: :administrator) }

    it 'localizes the full email content and sends it to account administrators' do
      administrator
      account.update!(locale: 'es')
      Current.account = account
      allow(class_instance).to receive(:send_mail_with_liquid).and_return(:mail)

      class_instance.automation_rule_paused_by_cap(rule, 200)

      expect(class_instance).to have_received(:send_mail_with_liquid).with(
        to: [administrator.email], subject: 'La regla «Birthday reminder» se pausó por el límite diario de envíos'
      )
      expected_message = 'La regla «Birthday reminder» alcanzó hoy el límite de 200 envíos automáticos y se pausó ' \
                         'para no seguir enviando. Revisa a cuántos contactos aplica y vuelve a activarla en ' \
                         'Automatizaciones cuando estés seguro.'
      expect(class_instance.send(:liquid_locals)).to include(
        meta: {
          'message' => expected_message,
          'action' => 'Ir a Automatizaciones'
        }
      )
    end

    it 'uses the English strings when the account language is English' do
      administrator
      account.update!(locale: 'en')
      Current.account = account
      allow(class_instance).to receive(:send_mail_with_liquid).and_return(:mail)

      class_instance.automation_rule_paused_by_cap(rule, 200)

      expect(class_instance).to have_received(:send_mail_with_liquid).with(
        to: [administrator.email], subject: 'The rule "Birthday reminder" was paused by the daily send limit'
      )
      expect(class_instance.send(:liquid_locals).dig(:meta, 'message')).to include("reached today's limit of 200 automatic sends")
    end

    it 'does not attempt delivery when the account has no administrators' do
      Current.account = account

      expect(class_instance).not_to receive(:send_notification)
      expect { class_instance.automation_rule_paused_by_cap(rule, 200) }.not_to raise_error
    end
  end
end
