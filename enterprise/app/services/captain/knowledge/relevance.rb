# Keeps only the knowledge results close enough to the question.
class Captain::Knowledge::Relevance
  CONFIG_NAME = 'CAPTAIN_FAQ_MAX_DISTANCE'.freeze
  DEFAULT_MAX_DISTANCE = 0.55
  RANGE = (0.20..1.00)

  Result = Data.define(:kept, :best_distance, :threshold, :filtered)

  def self.max_distance
    value = Float(InstallationConfig.find_by(name: CONFIG_NAME)&.value.to_s, exception: false)
    (value || DEFAULT_MAX_DISTANCE).clamp(RANGE.min, RANGE.max)
  end

  def self.apply(responses, filter:)
    threshold = max_distance
    distances = responses.filter_map { |response| response.try(:neighbor_distance) }
    kept = filter ? responses.select { |response| within?(response, threshold) } : responses
    Result.new(kept: kept, best_distance: distances.min, threshold: threshold, filtered: filter)
  end

  def self.within?(response, threshold)
    distance = response.try(:neighbor_distance)
    distance.nil? || distance <= threshold
  end
end
