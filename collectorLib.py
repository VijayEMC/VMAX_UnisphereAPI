import json
import requests
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

#########################
# Auth: Create Auth
#########################

def getAuth(username, password, symInfo):
    symInfo['auth'] = requests.auth.HTTPBasicAuth(user, password)

#########################
# Method: API Post Method
#########################

def restPost(body, api_url, headers, auth):
    return requests.post(api_url, json.dumps(body), headers=headers, verify=False)

#########################
# Method: API Get Method
#########################

def restGet(api_url, headers, auth):
    return requests.get(api_url, headers=headers, verify=False)

##########################################
# Method: Create/Connect InfluxDB Instance
##########################################

def ccInflux(host, port, user, password, dbname):
    return InfluxDBClient(host, port, user, password, dbname)
    
##############################################
# Method: Get Keys
# Pre Cond: Url and Auth needed to 
# Post Cond: Returns an Object with info
# about each Symmetrix connected to Unisphere
# Contains Sym IDS and first/last available
# date of metric collection
###############################################

def getKeys(symInfo):
    return requests.get(symInfo.keysUrl, headers=symInfo.headers, auth=symInfo.auth, verify=False)

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
    return requests.post(symInfo.metricsUrl, jsonPO, headers=symInfo.headers, auth=symInfo.auth, verify=False)

###########################################################
# Method: Process Metrics Object
###########################################################

def procMetrics(symInfo, metricsObj, config, index):
    metricList = metricsObj['resultList']['result']
    for i in config['metrics']:
        newValue = metricList[i]
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

