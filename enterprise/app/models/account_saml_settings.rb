# == Schema Information
#
# Table name: account_saml_settings
#
#  id            :bigint           not null, primary key
#  certificate   :text
#  metadata_refreshed_at :datetime
#  metadata_url          :string
#  role_mappings         :json
#  sso_url               :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  idp_entity_id         :string
#  sp_entity_id          :string
#
# Indexes
#
#  index_account_saml_settings_on_account_id  (account_id)
#
class AccountSamlSettings < ApplicationRecord
  METADATA_REFRESH_INTERVAL = 5.minutes
  CERTIFICATE_EXPIRY_WINDOW = 15.minutes
  belongs_to :account

  validates :account_id, presence: true
  validates :sso_url, presence: true
  validates :certificate, presence: true
  validates :idp_entity_id, presence: true
  validate :certificate_must_be_valid_x509

  before_validation :set_sp_entity_id, if: :sp_entity_id_needs_generation?
  before_validation :assign_idp_metadata, if: -> { metadata_url.present? && will_save_change_to_metadata_url? }

  after_create_commit :update_account_users_provider
  after_destroy_commit :reset_account_users_provider

  def saml_enabled?
    sso_url.present? && certificate.present?
  end

  def certificate_fingerprint
    return nil if certificate.blank?

    begin
      cert = parsed_certificates.max_by(&:not_after)
      OpenSSL::Digest::SHA1.new(cert.to_der).hexdigest
                           .upcase.gsub(/(.{2})(?=.)/, '\1:')
    rescue OpenSSL::X509::CertificateError
      nil
    end
  end

  def signing_certificates
    parsed_certificates.map(&:to_pem)
  end

  def signing_certificates=(certificates)
    self.certificate = certificates.join("\n")
  end

  def refresh_metadata
    return false if metadata_url.blank? && errors.add(:metadata_url, :blank)

    previous_values = attributes.slice('sso_url', 'certificate', 'idp_entity_id', 'metadata_refreshed_at')
    assign_idp_metadata
    return preserve_metadata_after_failed_refresh(previous_values) if errors.any?

    return true if save

    preserve_metadata_after_failed_refresh(previous_values)
  end

  def refresh_metadata_if_needed
    return if metadata_url.blank? || !certificate_expiring? || metadata_refreshed_at&.after?(METADATA_REFRESH_INTERVAL.ago)

    claimed = self.class.where(id: id)
                  .where('metadata_refreshed_at IS NULL OR metadata_refreshed_at < ?', METADATA_REFRESH_INTERVAL.ago)
                  .update_all(metadata_refreshed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return if claimed.zero?

    self.metadata_refreshed_at = Time.current
    return if refresh_metadata

    restore_attributes
  end

  private

  def preserve_metadata_after_failed_refresh(previous_values)
    Rails.logger.warn("SAML metadata refresh failed for account #{account_id}: #{errors.full_messages.to_sentence}")
    self.class.where(id: id).update_all(metadata_refreshed_at: Time.current) if persisted? # rubocop:disable Rails/SkipsModelValidations
    assign_attributes(previous_values.except('metadata_refreshed_at').merge('metadata_refreshed_at' => Time.current))
    false
  end

  def set_sp_entity_id
    base_url = GlobalConfigService.load('FRONTEND_URL', 'http://localhost:3000')
    self.sp_entity_id = "#{base_url}/saml/sp/#{account_id}"
  end

  def sp_entity_id_needs_generation?
    sp_entity_id.blank?
  end

  def installation_name
    GlobalConfigService.load('INSTALLATION_NAME', 'InboxHub')
  end

  def update_account_users_provider
    Saml::UpdateAccountUsersProviderJob.perform_later(account_id, 'saml')
  end

  def reset_account_users_provider
    Saml::UpdateAccountUsersProviderJob.perform_later(account_id, 'email')
  end

  def certificate_must_be_valid_x509
    return if certificate.blank?

    parsed_certificates
  rescue OpenSSL::X509::CertificateError
    errors.add(:certificate, I18n.t('errors.account_saml_settings.invalid_certificate'))
  end

  def parsed_certificates
    OpenSSL::X509::Certificate.load(certificate.to_s)
  end

  def certificate_expiring?
    parsed_certificates.max_by(&:not_after).not_after < CERTIFICATE_EXPIRY_WINDOW.from_now
  rescue OpenSSL::X509::CertificateError, NoMethodError
    true
  end

  def assign_idp_metadata
    values = Saml::IdpMetadataService.new(metadata_url).perform
    assign_attributes(values.merge(metadata_refreshed_at: Time.current))
  rescue Saml::IdpMetadataService::Error => e
    errors.add(:metadata_url, I18n.t("errors.account_saml_settings.metadata_url.#{e.reason}"))
  end
end
