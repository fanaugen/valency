class Language < ActiveRecord::Base
  has_many :coding_sets
  has_many :gloss_meanings
  has_many :contributors, through: :contributions, source: :person_id
  has_many :alternations
  has_many :coding_frames
  has_many :verbs
  
  attr_accessible :family, :id, :iso_code, :name, :variety, :alternation_occurs_judgement_criteria, :characterization_of_flagging_resources, :characterization_of_indexing_resources, :characterization_of_ordering_resources, :comments, :data_sources_generalizations_contributor_backgrounds
end
