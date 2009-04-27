$:.unshift File.dirname(__FILE__) # for use/testing when no gem is installed

# external
require 'net/http'
require 'net/https'
require 'uri'
require 'logger'
require 'rubygems'
require 'hpricot'

# internal
require 'gattica/core_extensions'
require 'gattica/convertible'
require 'gattica/exceptions'
require 'gattica/user'
require 'gattica/auth'
require 'gattica/account'
require 'gattica/data_set'
require 'gattica/data_point'

# Gattica is a Ruby library for talking to the Google Analytics API.
# 
# = Installation
# Install the gattica gem using github as the source:
# 
#   gem install cannikin-gattica -s http://gems.github.com
# 
# When you want to require, you just use 'gattica' as the gem name:
# 
#   require 'rubygems'
#   require 'gattica'
# 
# = Introduction
# There are generally three steps to getting info from the GA API:
# 
# 1. Authenticate
# 2. Get a profile id
# 3. Get the data you really want
# 
# It's a good idea to familiarize yourself with the Google API docs:
# 
#   http://code.google.com/apis/analytics/docs/gdata/gdataDeveloperGuide.html
#   
# In particular there are some very specific combinations of Metrics and Dimensions that
# you are restricted to and those are explained in this document:
# 
#   http://code.google.com/apis/analytics/docs/gdata/gdataReferenceDimensionsMetrics.html
# 
# = Usage
# This library does all three. A typical transaction will look like this:
# 
#  gs = Gattica.new('johndoe@google.com','password',123456)
#  results = gs.get({ :start_date => '2008-01-01', 
#                     :end_date => '2008-02-01', 
#                     :dimensions => 'browser', 
#                     :metrics => 'pageviews', 
#                     :sort => '-pageviews'})
# 
# So we instantiate a copy of Gattica and pass it a Google Account email address and password.
# The third parameter is the profile_id that we want to access data for.
# 
# Then we call +get+ with the parameters we want to shape our data with. In this case we want
# total page views, broken down by browser, from Jan 1 2008 to Feb 1 2008, sorted by descending
# page views.
# 
# If you don't know the profile_id you want to get data for, call +accounts+
# 
#  gs = Gattica.new('johndoe@google.com','password')
#  accounts = gs.accounts
# 
# This returns all of the accounts and profiles that the user has access to. Note that if you
# use this method to get profiles, you need to manually set the profile before you can call +get+
# 
#  gs.profile_id = 123456
#  results = gs.get({ :start_date => '2008-01-01', 
#                     :end_date => '2008-02-01', 
#                     :dimensions => 'browser', 
#                     :metrics => 'pageviews', 
#                     :sort => '-pageviews'})
#                     
# When you put in the names for the dimensions and metrics you want, refer to this doc for the 
# available names:
# 
#   http://code.google.com/apis/analytics/docs/gdata/gdataReferenceDimensionsMetrics.html
#   
# Note that you do *not* use the 'ga:' prefix when you tell Gattica which ones you want. Gattica
# adds that for you automatically.
# 
# If you want to search on more than one dimension or metric, pass them in as an array (you can
# also pass in single values as arrays too, if you wish):
#                     
#   results = gs.get({ :start_date => '2008-01-01', 
#                      :end_date => '2008-02-01', 
#                      :dimensions => ['browser','browserVersion'], 
#                      :metrics => ['pageviews','visits'], 
#                      :sort => ['-pageviews']})
#                       
# = Output
# When Gattica was originally created it was intended to take the data returned and put it into
# Excel for someone else to crunch through the numbers. Thus, Gattica has great built-in support
# for CSV output. Once you have your data simply:
# 
#   results.to_csv
#   
# A couple example rows of what that looks like:
# 
#   "id","updated","title","browser","pageviews"
#   "http://www.google.com/analytics/feeds/data?ids=ga:12345&amp;ga:browser=Internet%20Explorer&amp;start-date=2009-01-01&amp;end-date=2009-01-31","2009-01-30T16:00:00-08:00","ga:browser=Internet Explorer","Internet Explorer","53303"
#   "http://www.google.com/analytics/feeds/data?ids=ga:12345&amp;ga:browser=Firefox&amp;start-date=2009-01-01&amp;end-date=2009-01-31","2009-01-30T16:00:00-08:00","ga:browser=Firefox","Firefox","20323"
#   
# Data is comma-separated and double-quote delimited. In most cases, people don't care
# about the id, updated, or title attributes of this data. They just want the dimensions and
# metrics. In that case, pass the symbol +:short+ to +to_csv+ and receive get back only the
# the good stuff:
# 
#   results.to_csv(:short)
#   
# Which returns: 
# 
#   "browser","pageviews"
#   "Internet Explorer","53303"
#   "Firefox","20323"
# 
# You can also just output the results as a string and you'll get the standard inspect syntax:
# 
#   results.to_s
#   
# Gives you:
# 
#   { "end_date"=>#<Date: 4909725/2,0,2299161>, 
#     "start_date"=>#<Date: 4909665/2,0,2299161>, 
#     "points"=>[
#       { "title"=>"ga:browser=Internet Explorer", 
#         "dimensions"=>[{:browser=>"Internet Explorer"}],
#         "id"=>"http://www.google.com/analytics/feeds/data?ids=ga:12345&amp;ga:browser=Internet%20Explorer&amp;start-date=2009-01-01&amp;end-date=2009-01-31", 
#         "metrics"=>[{:pageviews=>53303}], 
#         "updated"=>#<DateTime: 212100120000001/86400000,-1/3,2299161>}]}
#         
# = Limitations
# The GA API limits each call to 1000 results per "page." If you want more, you need to tell
# the API what number to begin at and it will return the next 1000. Gattica does not currently
# support this, but it's in the plan for the very next version.
# 
# The GA API support filtering, so you can say things like "only show me the pageviews for pages
# whose URL meets the regular expression ^/saf.*?/$". Support for filters have begun, but according
# to one report, the DataSet object that returns doesn't parse the results correctly. So for now,
# avoid using filters.


module Gattica
  
  VERSION = '0.2.0'
  # LOGGER = Logger.new(STDOUT)

  def self.new(*args)
    Engine.new(*args)
  end
  
  # The real meat of Gattica, deals with talking to GA, returning and parsing results. You automatically
  # get an instance of this when you go Gattica.new()
  
  class Engine
    
    SERVER = 'www.google.com'
    PORT = 443
    SECURE = true
    DEFAULT_ARGS = { :start_date => nil, :end_date => nil, :dimensions => [], :metrics => [], :filters => [], :sort => [] }
    DEFAULT_OPTIONS = { :email => nil, :password => nil, :token => nil, :profile_id => nil, :debug => false, :headers => {}, :logger => Logger.new(STDOUT) }
    
    attr_reader :user
    attr_accessor :profile_id, :token
    
    # Create a user, and get them authorized.
    # If you're making a web app you're going to want to save the token that's retrieved by Gattica
    # so that you can use it later (Google recommends not re-authenticating the user for each and every request)
    #
    #   ga = Gattica.new({:email => 'johndoe@google.com', :password => 'password', :profile_id => 123456})
    #   ga.token => 'DW9N00wenl23R0...' (really long string)
    #
    # Or if you already have the token (because you authenticated previously and now want to reuse that session):
    #
    #   ga = Gattica.new({:token => '23ohda09hw...', :profile_id => 123456})
    
    def initialize(options={})
      @options = DEFAULT_OPTIONS.merge(options)
      @logger = @options[:logger]
      @logger.datetime_format = '' if @logger.respond_to? 'datetime_format'
      
      @profile_id = @options[:profile_id]     # if you don't include the profile_id now, you'll have to set it manually later via Gattica::Engine#profile_id=
      @user_accounts = nil                    # filled in later if the user ever calls Gattica::Engine#accounts
      @headers = {}                           # headers used for any HTTP requests (Google requires a special 'Authorization' header)
      
      # save an http connection for everyone to use
      @http = Net::HTTP.new(SERVER, PORT)
      @http.use_ssl = SECURE
      @http.set_debug_output $stdout if @options[:debug]
      
      # authenticate
      if @options[:email] && @options[:password]      # username and password: authenticate and get a token from Google's ClientLogin
        @user = User.new(@options[:email], @options[:password])
        @auth = Auth.new(@http, user, { :source => 'gattica-'+VERSION }, { 'User-Agent' => 'Ruby Net::HTTP' })
        self.token = @auth.tokens[:auth]
      elsif @options[:token]                          # use an existing token (this also sets the headers for any HTTP requests we make)
        self.token = @options[:token]
      else                                            # no login or token, you can't do anything
        raise GatticaError::NoLoginOrToken, 'You must provide an email and password, or authentication token'
      end

      # the user can provide their own additional headers - merge them into the ones that Gattica requires
      @headers = @headers.merge(@options[:headers])
      
      # TODO: check that the user has access to the specified profile and show an error here rather than wait for Google to respond with a message
    end
    
    
    # Returns the list of accounts the user has access to. A user may have multiple accounts on Google Analytics
    # and each account may have multiple profiles. You need the profile_id in order to get info from GA. If you
    # don't know the profile_id then use this method to get a list of all them. Then set the profile_id of your
    # instance and you can make regular calls from then on.
    #
    #   ga = Gattica.new({:email => 'johndoe@google.com', :password => 'password'})
    #   ga.get_accounts
    #   # you parse through the accounts to find the profile_id you need
    #   ga.profile_id = 12345678
    #   # now you can perform a regular search, see Gattica::Engine#get
    #
    # If you pass in a profile id when you instantiate Gattica::Search then you won't need to
    # get the accounts and find a profile_id - you apparently already know it!
    #
    # See Gattica::Engine#get to see how to get some data.
    
    def accounts
      # if we haven't retrieved the user's accounts yet, get them now and save them
      if @accts.nil?
        response, data = @http.get('/analytics/feeds/accounts/default', @headers)
        xml = Hpricot(data)
        @user_accounts = xml.search(:entry).collect { |entry| Account.new(entry) }
      end
      return @user_accounts
    end
    
    
    # This is the method that performs the actual request to get data.
    #
    # == Usage
    #
    #   gs = Gattica.new({:email => 'johndoe@google.com', :password => 'password', :profile_id => 123456})
    #   gs.get({ :start_date => '2008-01-01', 
    #            :end_date => '2008-02-01', 
    #            :dimensions => 'browser', 
    #            :metrics => 'pageviews', 
    #            :sort => 'pageviews'})
    #
    # == Input
    #
    # When calling +get+ you'll pass in a hash of options. For a description of what these mean to 
    # Google Analytics, see http://code.google.com/apis/analytics/docs
    #
    # Required values are:
    #
    # * +start_date+ => Beginning of the date range to search within
    # * +end_date+ => End of the date range to search within
    #
    # Optional values are:
    #
    # * +dimensions+ => an array of GA dimensions (without the ga: prefix)
    # * +metrics+ => an array of GA metrics (without the ga: prefix)
    # * +filter+ => an array of GA dimensions/metrics you want to filter by (without the ga: prefix)
    # * +sort+ => an array of GA dimensions/metrics you want to sort by (without the ga: prefix)
    #
    # == Exceptions
    #
    # If a user doesn't have access to the +profile_id+ you specified, you'll receive an error.
    # Likewise, if you attempt to access a dimension or metric that doesn't exist, you'll get an
    # error back from Google Analytics telling you so.
    
    def get(args={})
      args = validate_and_clean(DEFAULT_ARGS.merge(args))
      query_string = build_query_string(args,@profile_id)
        @logger.debug(query_string)
      response, data = @http.get("/analytics/feeds/data?#{query_string}", @headers)
      begin
        response.value
      rescue Net::HTTPServerException => e
        raise GatticaError::AnalyticsError, data.to_s + " (status code: #{e.message})"
      end
      return DataSet.new(Hpricot.XML(data))
    end
    
    
    # Since google wants the token to appear in any HTTP call's header, we have to set that header
    # again any time @token is changed
    
    def token=(token)
      @token = token
      set_http_headers
    end
    
    
    private
    
    # Sets up the HTTP headers that Google expects (this is called any time @token is set either by Gattica
    # or manually by the user since the header must include the token)
    def set_http_headers
      @headers['Authorization'] = "GoogleLogin auth=#{@token}"
    end
    
    
    # Creates a valid query string for GA
    def build_query_string(args,profile)
      output = "ids=ga:#{profile}&start-date=#{args[:start_date]}&end-date=#{args[:end_date]}"
      unless args[:dimensions].empty?
        output += '&dimensions=' + args[:dimensions].collect do |dimension|
          "ga:#{dimension}"
        end.join(',')
      end
      unless args[:metrics].empty?
        output += '&metrics=' + args[:metrics].collect do |metric|
          "ga:#{metric}"
        end.join(',')
      end
      unless args[:sort].empty?
        output += '&sort=' + args[:sort].collect do |sort|
          sort[0..0] == '-' ? "-ga:#{sort[1..-1]}" : "ga:#{sort}"  # if the first character is a dash, move it before the ga:
        end.join(',')
      end
      unless args[:filters].empty?    # filters are a little more complicated because they can have all kinds of modifiers
        
      end
      return output
    end
    
    
    # Validates that the args passed to +get+ are valid
    def validate_and_clean(args)
      
      raise GatticaError::MissingStartDate, ':start_date is required' if args[:start_date].nil? || args[:start_date].empty?
      raise GatticaError::MissingEndDate, ':end_date is required' if args[:end_date].nil? || args[:end_date].empty?
      raise GatticaError::TooManyDimensions, 'You can only have a maximum of 7 dimensions' if args[:dimensions] && (args[:dimensions].is_a?(Array) && args[:dimensions].length > 7)
      raise GatticaError::TooManyMetrics, 'You can only have a maximum of 10 metrics' if args[:metrics] && (args[:metrics].is_a?(Array) && args[:metrics].length > 10)
      
      # make sure that the user is only trying to sort fields that they've previously included with dimensions and metrics
      if args[:sort]
        possible = args[:dimensions] + args[:metrics]
        missing = args[:sort].find_all do |arg|
          !possible.include? arg.gsub(/^-/,'')    # remove possible minuses from any sort params
        end
        raise GatticaError::InvalidSort, "You are trying to sort by fields that are not in the available dimensions or metrics: #{missing.join(', ')}" unless missing.empty?
      end
      
      return args
    end
    
    
  end
end
