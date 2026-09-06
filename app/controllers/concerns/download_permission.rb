# frozen_string_literal: true

# Lets a super admin decide, per account, whether that account's admins may pull
# data out of the tool at all.
#
# Two separate switches because the risk is not the same: customer_data_export
# covers downloads that carry personal data (contacts, conversations, campaign
# recipients, CSAT answers, import logs), while report_export covers aggregate
# reporting. An account can keep its reports and still be unable to walk out
# with its contact list.
#
# The guard lives in the controller rather than the UI on purpose: hiding a
# button only closes the easy path, and any admin with a personal access token
# can call these endpoints straight from a terminal.
module DownloadPermission
  extend ActiveSupport::Concern

  CUSTOMER_DATA_EXPORT = 'customer_data_export'
  REPORT_EXPORT = 'report_export'

  private

  def ensure_customer_data_download_enabled
    ensure_download_enabled(CUSTOMER_DATA_EXPORT)
  end

  def ensure_report_download_enabled
    ensure_download_enabled(REPORT_EXPORT)
  end

  def ensure_download_enabled(feature)
    return if Current.account&.feature_enabled?(feature)

    log_blocked_download(feature)
    render json: { error: I18n.t('errors.downloads.disabled') }, status: :forbidden
  end

  # A blocked attempt is worth recording precisely because the button is hidden
  # when the feature is off: whatever reached this point did not come from the
  # normal interface.
  def log_blocked_download(feature)
    Rails.logger.warn(
      "[DownloadBlocked] feature=#{feature} account=#{Current.account&.id} user=#{Current.user&.id} " \
      "path=#{request.path} ip=#{request.remote_ip}"
    )
  end
end
