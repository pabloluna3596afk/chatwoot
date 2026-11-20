# Names supplied by the activity's author, in the order they appear in its persisted text.
module ActivityMessageNames
  def self.attributes(content, *names)
    names = names.flatten.select { |name| name.present? && content.include?(name) }.uniq
    { activity: { names: names.sort_by { |name| content.index(name) } } }
  end
end
