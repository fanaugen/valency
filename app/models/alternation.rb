class Alternation < ActiveRecord::Base
  self.primary_key = :id
  attr_accessible :name, :alternation_type, :coding_frames_text, :description, :id, :language_id, :complexity

  belongs_to :language
  has_many :alternation_values
  has_many :verbs,    :through => :alternation_values
  has_many :examples, :through => :alternation_values # I wonder if this will work

  def coded_yes_no
    alternation_type == "Coded" ? "Yes" : "No"
  end

end
