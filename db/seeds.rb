# uses the RFM gem (ginjo-rfm) to access FileMaker Server XML API
# uses heuristics and custom mapping rules to find FM database column names
# for all the Rails models' attributes
# CAUTION: this will delete all data from the database first!
require 'rfm'

# Database connection settings for RFM
# RFM_ACCOUNT_NAME and RFM_PASSWORD need to be specified in the environment
RFM_CONFIG = {
  host:         'brugmann.eva.mpg.de',  # IP address: 194.94.96.174
  database:     'Valency',              # database name
  account_name: ENV['RFM_ACCOUNT_NAME'],# user is read-only, has XML access
  password:     ENV['RFM_PASSWORD'],
  ssl:          false,
  root_cert:    false,
  port:         80,                     # 443 with SSL doesn't seem to work
  timeout:      20
}

# initialize logger - changed to stdout for Heroku
LOG       = Logger.new($stdout) # Logger.new Rails.root.join('log', 'seeds.log')
LOG.level = Logger::DEBUG

# helper method: appends prefix and suffix to FM field name
class String
	def css_field_name
		'z_calc_' + self + '_as_css'
	end
end

# contains methods to find the layout and field names for a model
class FieldFinder
 	attr_accessor :model # needs to be set before using the methods!

  # creates hashes for the non-standard names:
  def initialize
  	# this hash maps models to layout names 
		@special_layout = {
			Contribution              => "Language_contributors (table)",
			MeaningsVerb              => "Verb_meanings (table)",
			ExamplesVerb              => "Verb_examples (table)",
			AlternationValuesExample  => "Alternation_value_examples (table)",
			CodingFrameExample	      => "Verb_coding_frame_examples (table)",
			CodingFrameIndexNumbersMicrorole => "Coding_frame_Microrole_index_numbers (table)"
		}
		# this hash maps a model to a hash from property name to field name
		@special_field_name = { # field names must be in lowercase!
			Alternation => {
				'coding_frames_text' => 'coding_frames_of_alternation',
				'complexity'         => 'simplex_or_complex'
			},
			GlossMeaning => {
				'comment' => 'gloss_meaning_comments::comments'
			},
			Example => {
				'person_id' => 'source_person_id'
			},
			Meaning => {
				'meaning_list' => 'z_calc_meaning_list_core_extended_new_or_old'
			},
			Language    => {
			  'name_for_url' => 'z_calc_language_name_for_url'
			},
			CodingFrame => {
			  'derived'    => 'z_calc_basic_or_derived'
			}
		}
  end

 # expects a block, yields lambdas to it
	def name_transformations
		def compose(f,g) # compose 2 lambdas
			->(x) { f.call(g.call(x)) }
		end
		model_name = @model.to_s.underscore + '_' #=> "model_"
		pl   = ->(s) { s.singularize == s ? s.pluralize : s.singularize } # toggle plural
		css  = ->(s) { s.css_field_name }      # z_calc_field_name_as_css
		pre  = ->(s) { model_name + s }  # model_field_name
		calc = ->(s) { 'z_calc_' + s  }  # z_calc_field_name

		yield compose(css, compose(pre, pl))      # z_calc_model_field_names_as_css
		yield compose(css, pre)                   # z_calc_model_field_name_as_css
		yield compose(calc, compose(pre, pl))     # z_calc_model_field_names
		yield compose(calc, pre)                  # z_calc_model_field_name
		yield compose(css, pl)                    # z_calc_field_names_as_css
		yield css                                 # z_calc_field_name_as_css
		yield compose(calc, pl)                   # z_calc_field_names
		yield calc                                # z_calc_field_name
		yield compose(pre, pl)                    # model_field_names
		yield pre                                 # model_field_name
		yield pl                                  # field_names
		yield ->(s){s} # identity: no change      # field_name
	end

	# returns an RFM Layout object or nil if no layout with that name exists
	def layout_or_nil(layout_name)
		begin
			if (layout = Rfm.layout(layout_name)).table then layout; end
		rescue nil
		end
	end

	# calculates the layout name, returns the RFM Layout object
	def find_layout
	  return nil if @model.nil?
		layout_name = @special_layout[@model] || @model.to_s.tableize + ' (table)'
		if (layout = layout_or_nil(layout_name))
			LOG.info("\n==== Model: #{@model.to_s} <- Layout: #{layout.name} ====")
			return layout
		else 
			LOG.warn "WARNING: Layout \"#{layout_name}\" does not exist."
			return nil
		end
	end
	
  # returns a hash mapping the Rails model's attribute names to field names
	def find_field_names(layout)
		result = {} # hash to be returned: field names for the attributes
		return result if layout.nil? or @model.nil?
		attr_names = @model.attribute_names.map{|name| name.downcase} # model attributes
	  fm_fields  = layout.field_names.map{|name| name.downcase} # layout's fields
		
		attr_names.each do |attr_name| # for each of the model's attributes
      
      special = @special_field_name[@model] # possibly nil
      f_name = special.nil? ? nil : special[attr_name] # possibly nil

		  if f_name then
		    if fm_fields.include?(f_name)
					result[attr_name] = f_name
				else 
					LOG.warn "WARNING: Field \"#{f_name}\" not found on layout \"#{layout.name}\"."
					next
				end

			else # no special field name: guess regular field name
				name_transformations do |transf|
					if fm_fields.include? (transformed = transf.call(attr_name))
						result[attr_name] = transformed
						break # found a match! exit the block
					end
				end
			end
	
			if result[attr_name].nil?
				LOG.warn "WARNING: No field found for #{@model.to_s}.#{attr_name}"
			else
				LOG.info "  mapping: #{attr_name} <-- #{result[attr_name]}"
			end
		
		end
		return result
	end
    
end # of class FieldFinder

# handles data import into Rails database
class DataImporter

	def initialize
	  @ff = FieldFinder.new
		# Gather all model classes:
		@models = Dir[Rails.root.join 'app','models','*.rb'].map do |file|
			File.basename(file,'.*').camelize.constantize
		end
	end

  # performs the actual import
  # it loops over the models, uses the FieldFinder instance to
  # get the RFM layout and the corresponding field names
  # then reads data from the FileMaker connection using RFM 
  # and creates records in Rails' database
	def import_data
		ok, err = '.', 'x' # for visual stdout feedback
		
		@models.each do |model|
		  next unless model == Verb # re-seed selected models only!
			LOG.info (' '<<model.to_s<<' ').center(40, '=')
	    LOG.info "Deleting all #{model.to_s} records... "
	    model.delete_all

 			# get the layout and field names
 			@ff.model = model
			next if (layout = @ff.find_layout).nil? or
			        (fields = @ff.find_field_names(layout)).empty?
			
			err_stats = Hash.new(0); # count errors by type
			new_obj = {};
			available_attributes = model.attribute_names & fields.keys
			
			total = layout.total_count
 			LOG.info "Connected to FileMaker, layout = #{layout.name}. Importing..."
 			
			# now loop through all the records of the layout, but page them by 1000
 			(total / 1000 + 1).times do |page|
			  found_set = layout.find({}, max_records:1000, skip_records:1000*page)
			  LOG.info("reading records #{1000*page+1} to #{1000*(page+1) <= total ? 1000*(page+1) : total}...")
  			found_set.each do |fm_record|
  				new_obj.clear
  				available_attributes.each do |attr_name|
  					new_obj[attr_name] = fm_record[fields[attr_name]] # fields' values are FileMaker field names
  				end
  				begin
            model.create!(new_obj) # throws Exception if Rails validation fails
  			    # print ok
  			  rescue Exception => e
  			    # print err
  			    err_stats[e.class.to_s] += 1
  			    LOG.error (e.message)
  		    end

  			end #loop over records

      end

	    # show summary and error info
	    err_count = err_stats.values.sum
	    report = "Done! Created #{model.count} records."+
	      " There were #{err_count > 0 ? err_count : 'no'} errors" 
	    # puts "\n" + report + "\n\n"
			LOG.info report
			err_stats.each do |klass, number| 
			  LOG.info '  '+ number.to_s + ' errors of type ' + klass
		  end
		  LOG.info "\n"

		end #loop over models
		
	end # method import_data
	
end # of class

di = DataImporter.new
di.import_data
