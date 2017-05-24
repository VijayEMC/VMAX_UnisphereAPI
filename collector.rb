#!/usr/bin/env ruby
#require "devkit"
require "rest-client"
#require "csv"
require "json"
require "base64"
#require "crack"
require "pry-byebug"
require "ostruct"
require "influxdb"

current_dir=File.dirname(__FILE__)
new_curr_dir = Dir.pwd
settings_file=("#{new_curr_dir}/settings.json.example")



testobj = {'startdate' => 'hi'}

puts testobj
#########################
# Method: API Post Method
#########################
def rest_post(payload, api_url, auth, cert=nil)
  JSON.parse(RestClient::Request.execute(
    method: :post,
    url: api_url,
    verify_ssl: false,
    payload: payload,
    headers: {
      authorization: auth,
      content_type: 'application/json',
      accept: :json
    }
  ))
end

########################
# Method: API GET Method
########################
def rest_get(api_url, auth, cert=nil)
  JSON.parse(RestClient::Request.execute(method: :get,
    url: api_url,
    verify_ssl: false,
    headers: {
      authorization: auth,
      accept: :json
    }
  ))
end

#################################
# Method: Read settings.json file
#################################
def readSettings(file)
  settings = File.read(file)
  JSON.parse(settings)
end

config=readSettings(settings_file)
# Create influx instance and connect to InfluxDB
influxdb = InfluxDB::Client.new config['influx']['table'], host: config['influx']['host'], port: config['influx']['port']


#####################################################
# Make Keys Call to get SYM IDs and Most Recent Date
######################################################

# Build our url strings
keys_url = "https://#{config['unisphere']['ip']}:#{config['unisphere']['port']}/univmax/restapi/performance/Array/keys"
metrics_url = "https://#{config['unisphere']['ip']}:#{config['unisphere']['port']}/univmax/restapi/performance/Array/metrics" 

# Create base 64 encoded auth
auth = Base64.strict_encode64("#{config['unisphere']['user']}:#{config['unisphere']['password']}")

# Make call to get keys

keys_object = rest_get(keys_url, auth, cert=nil)


#################################################
# Build POST Request Body Object from Keys Return
##################################################

# Create array to hold symmetrix IDS and another to hold their last available date
symIds = []
lastAvail = []

keys_object['arrayInfo'].each do |arrayObj|
    symIds << arrayObj['symmetrixId']
    lastAvail << arrayObj['lastAvailableDate']
end


# create new object for post request payload
#postObject = {startDate => nil, endDate => nil, symmetrixId => nil, dataFormat => nil, metrics => nil }
# create new object for influx payload
influxPayload = OpenStruct.new
# create array to send multiple metrics
influxArray = []

#Start a loop that makes requests and dumps requested info into influx
index = 0
#change

symIds.each do |sym|
    postObject = {'startDate' => lastAvail[index], 'endDate' => lastAvail[index], 'symmetrixId' => sym, 'dataFormat' => 'Average', 'metrics' => config['metrics']}
    jsonPayload = postObject.to_json
    binding.pry
    # Make POST Request
    metrics_object = rest_post(jsonPayload, metrics_url, auth, cert=nil)
    ####################################################
    # Organized returned object into influxDB payload
    #####################################################
    # collect the data from each metric returned from API
    config['metrics'].each do |metric|
        # get actual value
        newValue = metrics_object.metric
        # create influx payload
        influxPayload.values = {value => newValue}
        influxPayload.tags = {symmetrixId => sym}
        influxPayload.series = metric
        # push the current metric to the array
        influxArray.push(influxPayload)
    end
    # send array of data points to influx
    influxdb.write_points(influxArray)
    # clear array
    influxArray.clear
    # increment and loop
    index += 1
end