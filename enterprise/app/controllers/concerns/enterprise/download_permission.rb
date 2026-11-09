module Enterprise::DownloadPermission
  private

  def log_blocked_download(feature)
    super
    Audited.audit_class.create!(
      auditable: Current.account, associated: Current.account, user: Current.user,
      action: 'download_blocked', audited_changes: { feature: feature, path: request.path },
      remote_address: request.remote_ip, request_uuid: request.uuid
    )
  end
end
