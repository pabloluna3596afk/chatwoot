# == Schema Information
#
# Table name: whatsapp_flows
#
#  id            :bigint           not null, primary key
#  categories    :jsonb            not null
#  definition    :jsonb            not null
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_whatsapp_flows_on_account_id           (account_id)
#  index_whatsapp_flows_on_account_id_and_name  (account_id,name)
#  index_whatsapp_flows_on_created_by_id        (created_by_id)
#
# A form built in ChatHub (a "flow" for WhatsApp). The definition is the neutral one of Whatsapp::Flows::Spec: it is
# saved as a draft even when it still has mistakes (the builder shows them), and only a valid one can be published.
# Not to be confused with Flow, the conversation automations.
class WhatsappFlow < ApplicationRecord
  MAX_DEFINITION_BYTES = 1.megabyte

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :whatsapp_flow_publications, dependent: :destroy

  before_validation :normalize

  validates :name, presence: true, length: { maximum: 100 }
  validate :categories_known
  validate :definition_shape

  def definition_check
    Whatsapp::Flows::DefinitionValidator.new(definition, account: account).call
  end

  def flow_json
    Whatsapp::Flows::Exporter.new(definition).call
  end

  private

  def normalize
    self.name = name.to_s.strip
    self.categories = Array(categories).map(&:to_s).uniq
    self.definition = Whatsapp::Flows::Spec.string_keys(definition.presence || {})
    definition['schema_version'] ||= Whatsapp::Flows::Spec::SCHEMA_VERSION if definition.is_a?(Hash)
  end

  def categories_known
    unknown = categories - Whatsapp::Flows::Spec::CATEGORIES
    errors.add(:categories, :inclusion) if unknown.any?
  end

  def definition_shape
    return errors.add(:definition, :invalid) unless definition.is_a?(Hash) && definition['screens'].is_a?(Array)

    errors.add(:definition, :too_long) if definition.to_json.bytesize > MAX_DEFINITION_BYTES
  end
end
