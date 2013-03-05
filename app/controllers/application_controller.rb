class ApplicationController < ActionController::Base
  protect_from_forgery
  before_filter :global_queries
  
  # password protection: basic HTTP auth
  http_basic_authenticate_with(
    :name     => ENV['HTTP_USER'],
    :password => ENV['HTTP_PASSWORD'],
    :realm    => 'see LinguaWiki'
  )
  # necessary for languages dropdown,
  # meanings dropdown and more
  def global_queries
    @languages     ||= Language.all
    @meanings_core ||= Meaning.core
  end
  
  # create action for home page
  def home
    render 'shared/home'
  end

end
