# == Schema Information
#
# Table name: calendar_connection_calendars
#
#  id                          :bigint           not null, primary key
#  default_bot_followup_policy :jsonb            not null
#  external_id                 :string           not null
#  hour_end                    :integer          default(20), not null
#  hour_start                  :integer          default(8), not null
#  is_enabled                  :boolean          default(FALSE), not null
#  is_primary                  :boolean          default(FALSE), not null
#  summary                     :string           default(""), not null
#  working_days                :integer          default([0, 1, 2, 3, 4, 5, 6]), not null, is an Array
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  calendar_connection_id      :bigint           not null
#
class CalendarConnectionCalendar < ApplicationRecord
  belongs_to :account
  belongs_to :calendar_connection

  validates :external_id, presence: true
  validates :external_id, uniqueness: { scope: :calendar_connection_id }
  validates :hour_start, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 22 }
  validates :hour_end, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 23 }
  validate :hour_range_order
  validate :working_days_are_valid

  scope :enabled, -> { where(is_enabled: true) }

  def works_on?(wday)
    working_days.include?(wday)
  end

  private

  def working_days_are_valid
    days = working_days
    valid = days.is_a?(Array) && days.any? && days.all?(Integer) && (days - (0..6).to_a).empty? && days.uniq.size == days.size
    errors.add(:working_days, :invalid) unless valid
  end

  def hour_range_order
    return if hour_end.nil? || hour_start.nil?
    return if hour_end > hour_start

    errors.add(:hour_end, :greater_than, count: hour_start)
  end
end
