# Removes the stored copies of template header files that nothing uses any more.
#
# A copy is created when a file is chosen for a template header (see Whatsapp::TemplateHeaderMedia) and is shared by
# every message, campaign, automation and Captain setting that sends it. It is kept while anything points to it:
#   - a message attachment (a sent template shows its file in the chat, and that stays as long as the message does;
#     Active Storage itself refuses to purge a blob that still has an attachment),
#   - a campaign, an automation rule or a Captain setting that holds the file in its template params.
# A copy that nothing points to and that was last chosen more than RETAIN_FOR ago is purged.
class Whatsapp::HeaderMediaCleanupService
  RETAIN_FOR = 30.days

  # How many copies were purged.
  def perform
    purged = 0
    stale_blobs.find_each do |blob|
      next if recently_used?(blob) || referenced?(blob)

      purged += 1 if purge(blob)
    end
    purged
  end

  private

  def stale_blobs
    ActiveStorage::Blob.where('active_storage_blobs.created_at < ?', RETAIN_FOR.ago)
                       .where('active_storage_blobs.metadata LIKE ?', "%#{Whatsapp::TemplateHeaderMedia::METADATA_KEY}%")
                       .where.missing(:attachments)
  end

  def recently_used?(blob)
    used_at = Time.zone.parse(blob.metadata[Whatsapp::TemplateHeaderMedia::LAST_USED_KEY].to_s)
    used_at.present? && used_at > RETAIN_FOR.ago
  end

  def referenced?(blob)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(blob.signed_id)}%"
    holders.any? { |scope, column| scope.exists?(["#{column}::text LIKE ?", pattern]) }
  end

  # Where a header file can be named by its signed id.
  def holders
    list = [[Campaign, 'campaigns.template_params'], [AutomationRule, 'automation_rules.actions']]
    list << [Captain::Assistant, 'captain_assistants.config'] if defined?(Captain::Assistant)
    list
  end

  def purge(blob)
    blob.purge
    true
  rescue ActiveRecord::InvalidForeignKey
    false
  end
end
