import json
import requests
import sys
from influxdb import InfluxDBClient 

#############################################
# Class: Class object to hold all pertinent
# Unisphere and App variables
#############################################

class uniInfo:
    def __init__(self, config):
        self.keysUrl = config['unisphere']['ip'] + ":" + config['unisphere']['port'] + "/univmax/restapi/performance/Array/keys"
        self.metricsUrl = config['unisphere']['ip'] + ":" + config['unisphere']['port'] + "/univmax/restapi/performance/Array/metrics"
        self.auth = requests.auth.HTTPBasicAuth(config['unisphere']['user'], config['unisphere']['password'])
    symIds = []
    lastAvail = []
    firstAvail = []
    influxArray = []
    noMetrics = []
    yesMetrics = []
    headers = {}
    idb = {}

##########################################
# Method: Connect InfluxDB Instance
# Connects to a running instance of influx
# Does not seem to allow for error checking
# NOTE: SHOULD ADD A CONNCECTION CHECK
# AFTER INFLUXDBCLIENT IS CALLED
##########################################

def ccInflux(sysInfo, configObj):
    sysInfo.idb = InfluxDBClient((configObj['influx']['ip'], configObj['influx']['port'], configObj['influx']['user'], configObj['influx']['pass'], configObj['influx']['table']))
    # Add Error Checking

########################################################
# NOTES: The next two functions will deal with possible
# time discrepancies found in the event an application
# run did not successfully write to Influx. In this
# event, the app must check the last time a successful
# write occured, and fill in any missing history by
# writing a history of points to Influx. Make sense?
##########################################################

def influxTimeQuery(idbInstance):
    lastWriteObj = idbInstance.query('select value from cpu_load_short ORDER BY time DESC LIMIT 1;')
    return lastWriteObj['time']

def _timeDiff(timestamp, influxLastTime):
    if timestamp - influxLastTime > 6: # 6 minutes? Questionable move
        return influxLastTime
    else:
        return timestamp
    
    
    
##############################################
# Method: Get Keys
# Pre Cond: Url and Auth needed to 
# Post Cond: Returns an Object with info
# about each Symmetrix connected to Unisphere
# Contains Sym IDS and first/last available
# date of metric collection
###############################################

def getKeys(symInfo):
    resp = requests.get(symInfo.keysUrl, headers=symInfo.headers, auth=symInfo.auth, verify=False)
    if resp.status_code < 300:
        return resp
    else:
        print >> sys.stderr, 'Failed in getKeys() with response code' + resp.status_code
        print('Failed in getKeys() with response code' + resp.status_code)
        
###################################################
# Method: Process Keys Object
###################################################

def procKeys(arrayInfo, keysObject):
    data = keysObject['arrayInfo']
    for i in data:
        arrayInfo.symIds.append(i['symmetrixId'])
        arrayInfo.lastAvail.append(i['lastAvailableDate'])
        arrayInfo.firstAvail.append(i['firstAvailableDate'])
        
########################################################
# Method: Collect Metrics for each Sym ID
########################################################

def collectMetrics(symInfo, index):
    postObject = {'startDate' : symInfo['lastAvail'][index], 'endDate' : symInfo['lastAvail'][index], 'symmetrixId' : symInfo['symIds'][index], 'dataFormat' : 'Average', 'metrics' : config['metrics']}
    jsonPO = json.loads(postObject)
    resp = requests.post(symInfo.metricsUrl, jsonPO, headers=symInfo.headers, auth=symInfo.auth, verify=False)
    if resp.status_code < 300:
        return resp
    else:
        print >> sys.stderr, 'Failed in collectMetrics() with response code' + resp.status_code
        print('Failed in collectMetrics() with response code' + resp.status_code)

###########################################################
# Method: Process Metrics Object
###########################################################

def procMetrics(symInfo, metricsObj, config, index):
    metricList = metricsObj['resultList']['result']
    for i in config['metrics']:
        newValue = metricList[i]
        # add 'time' : <timestamp>
        influxPayload = {'series': metric, 'values': {'value': newValue}, 'tags': {'symmetrixId': symInfo.symIds[index]}}
        symInfo.influxArray.append(influxPayload)
    symInfo.idb.write_points(symInfo.influxArray)
    self._clearInfluxArray(symInfo)

#############################################################
# Method: _clearInfluxArray
# Pre Cond: object with an array property named 'influxArray'
# Post Cond: array will be emptied
##############################################################

def _clearInfluxArray(symInfo):
    symInfo['influxArray'][:] = []
    
####################################################################
# Method: importConfig
# Pre Cond: file in current directory called "settings.json.example"
# Post Cond: return json formatted content from file
#####################################################################
def importConfig():
    f = open("settings.json.example", "r")
    return json.loads(f.read())

