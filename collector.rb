#!/usr/bin/env ruby
#require "devkit"
require "rest-client"
require "csv"
require "json"
require "base64"
require "crack"
require "pry-byebug"
require "ostruct"
%w{simple-graphite}.each { |l| require l }
require "influxdb"

current_dir=File.dirname(__FILE__)
new_curr_dir = Dir.pwd
settings_file=("#{new_curr_dir}/settings.json.example")
####################################################################################
# Method: Read's the Unisphere XSD file and gets all Metrics for the specified scope
####################################################################################
def get_metrics(param_type,xsd)
  output = Array.new
  JSON.parse(xsd)['xs:schema']['xs:simpleType'].each do |type|
    if type['name'] == "#{param_type}Metric"
      type['xs:restriction']['xs:enumeration'].each do |metric|
        output.push(metric['value']) if metric['value'] == metric['value'].upcase
      end
    end
  end
  return output
end

#####################################
# Method: Reutrns keys for all scopes
#####################################
def get_keys(unisphere,payload,monitor,auth)
  if monitor['scope'].downcase == "array"
    rest = rest_get("https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/keys", auth)
  else
    rest = rest_post(payload.to_json,"https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/keys", auth)
  end
  
  componentId = get_component_id_payload(monitor['scope'])
  output = rest["#{componentId}Info"] if unisphere['version'] == 8
  output = rest["#{componentId}KeyResult"]["#{componentId}Info"] if unisphere['version'] == 7
  puts output
  return output
end

##################################################
# Method: Find differences in the key payload
##################################################
def diff_key_payload(incoming_payload,parent_id=nil)
  baseline_keys=["firstAvailableDate","lastAvailableDate"]
  #baseline_keys.push(parent_id) if parent_id
  incoming_keys=incoming_payload.keys
  return incoming_keys-baseline_keys
end

##################################################
# Method: Build the Key Payload
##################################################
def build_key_payload(unisphere,symmetrix,monitor,key=nil,parent_id=nil)
  payload = { "symmetrixId" => symmetrix['sid']}
  extra_payload = {parent_id[0] => key[parent_id[0]]} if parent_id
  payload.merge!(extra_payload) if parent_id
  componentId = get_component_id_key(monitor['scope']) if unisphere['version'] == 7
  payload = {  "#{componentId}KeyParam" => payload } if unisphere['version'] == 7
  return payload
end

##################################################
# Method: Build the Metric Payload
##################################################
def build_metric_payload(unisphere,monitor,symmetrix,metrics,key=nil,parent_id=nil,child_key=nil,child_id=nil)
  payload = { "symmetrixId" => symmetrix['sid'], "metrics" => metrics}
  parent_payload = { parent_id[0] => key[parent_id[0]] } unless monitor['scope'] == "Array"
  payload.merge!(parent_payload) unless monitor['scope'] == "Array"
  child_payload = { child_id[0] => child_key[child_id[0]], "startDate" => child_key['lastAvailableDate'], "endDate" => child_key['lastAvailableDate'] } if child_key
  payload.merge!(child_payload) if child_key
  timestamp_payload = { "startDate" => key['lastAvailableDate'], "endDate" => key['lastAvailableDate'] } unless child_key
  payload.merge!(timestamp_payload) unless child_key
  uni8_payload = { "dataFormat" => "Average" } if unisphere['version'] == 8
  payload.merge!(uni8_payload) if unisphere['version'] == 8
  componentId = get_component_id_key(monitor['scope']) if (unisphere['version'] == 7 && child_key.nil?)
  componentId = get_component_id_key(monitor['children'][0]['scope']) if (unisphere['version'] == 7 && child_key != nil)
  payload = {  "#{componentId}Param" => payload } if unisphere['version'] == 7
  return payload
end

################################################################################
# Method: Returns Metrics for all component scopes. Helper for building payloads
################################################################################
def get_perf_metrics(unisphere,payload,monitor,auth)
  binding.pry
  rest = rest_post(payload.to_json,"https://#{unisphere['ip']}:#{unisphere['port']}/univmax/restapi/performance/#{monitor['scope']}/metrics", auth)
  output = rest['resultList']['result'][0] if unisphere['version'] == 8
  output = rest['iterator']['resultList']['result'][0] if unisphere['version'] == 7
  puts output
  return output
end

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

##################################################################################
# Method: Helper Method to correctly format scope for JSON payloads in Unisphere 7
##################################################################################
def get_component_id_key(scope)
  ## Splits the string based on upper case letters ##
  s = scope.split /(?=[A-Z])/
  i = 0
  while i < s.length
    ## If the string in the array is all upcase, make it downcase ##
    s[i] = s[i].downcase if s[i] == s[i].upcase
    ## If this is the first string in the array and it is camelcase, make it all downcase ##
    s[i] = s[i].downcase if i == 0 && s[i] == s[i].capitalize
    i += 1
  end
  new_scope = s.join
  return new_scope
end

##################################################################################
# Method: Helper Method to correctly format scope for JSON return in Unisphere 7
##################################################################################
def get_component_id_payload(scope)
  ## Splits the string based on upper case letters ##
  s = scope.split /(?=[A-Z])/
  i = 0
  if s[-1].capitalize == "Pool"
    new_scope = "pool"
  else
    while i < s.length
      ## If the string in the array is all upcase, make it downcase ##
      s[i] = s[i].downcase if s[i] == s[i].upcase
      ## If this is the first string in the array and it is camelcase, make it all downcase ##
      s[i] = s[i].downcase if i == 0 && s[i] == s[i].capitalize
      i += 1
    end
    new_scope = s.join
  end
  return new_scope
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
influxdb = InfluxDB::Client.new config['influx']['table'], host: config['influx']['host'], port: config['influx']['port'] if config['influx']['enabled']


#####################################################
# Make Keys Call to get SYM IDs and Most Recent Date
######################################################

# Build our url strings
keys_url = "https://#{config['unisphere']['ip']}:#{config['unisphere']['port']}/performance/Array/keys"
metrics_url = "https://#{config['unisphere']['ip']}:#{config['unisphere']['port']}/performance/Array/metrics" 

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

keys_object.arrayInfo.each do |arrayObj|
    symIds << arrayObj.symmetrixId
    lastAvail << arrayObj.lastAvailableDate
end


# create new object for post request payload
postObject = OpenStruct.new
# create new object for influx payload
influxPayload = OpenStruct.new
# create array to send multiple metrics
influxArray = []

#Start a loop that makes requests and dumps requested info into influx
index = 0

symIds.each do |sym|
    postObject.startDate = lastAvail[index]
    postObject.endDate = lastAvail[index]
    postObject.symmetrixId = sym
    postObject.dataFormat = "Average"
    postObject.metrics = config['metrics']
    # Make POST Request
    metrics_object = rest_post(postObject, metrics_url, auth, cert=nil)
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