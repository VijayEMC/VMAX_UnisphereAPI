#!/usr/bin/python

from collectorLib import *



# Read in Config File
configObj = importConfig()

# Create unisphere class object
uniInst = uniInfo(configObj)

# Connect to Influx instance
ccInflux(uniInst, configObj)

# Get keys
keys = getKeys(uniInst)

# Process information from keys
procKeys(uniInst, keys)

# Loop through each symmetrix and collect/process metrics
for index in range(len(uniInst.symIds)):
    metrics = collectMetrics(uniInst, index)
    procMetrics(uniInst, metrics, configObj, index)




        