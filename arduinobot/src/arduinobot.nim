# Copyright 2017 Evothings Labs AB <info@evothings.com>.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import jester, mqtt, asyncdispatch, asyncnet, htmlgen, json, logging, os, strutils, sequtils, parseopt2, nuuid

# A service written in Nim.
# http://localhost:10000/hello

settings:
  port = Port(10000)

const path = "public/download" 

var serverUrl = "tcp://lora.evothings.com:1883"
var clientID = "arduinobot-" + generateUUID()

var client = newClient(serverUrl, clientID, MQTTPersistenceType.None)

# MQTT Callbacks
proc connectionLost(cause: string) =
  echo "connectionLost"

proc messageArrived(topicName: string, message: MQTTMessage): cint =
  echo "messageArrived: ", topicName, " ", message.payload
  result = 1

proc deliveryComplete(dt: MQTTDeliveryToken) =
  echo "deliveryComplete"

proc disconnect() =
  client.disconnect(1000)
  client.destroy()

proc connect() =
  try:
    var connectOptions = newConnectOptions()
    connectOptions.username = "admin"
    connectOptions.password = "lots"

    client.setCallbacks(connectionLost, messageArrived, deliveryComplete)
    client.connect(connectOptions)
    client.subscribe("config", QOS0)

  except MQTTError:
    quit "MQTT exception: " & getCurrentExceptionMsg()

proc parseArguments() =
  for kind, key, value in getopt():
    case kind:
    of cmdArgument:
      serverUrl = key
    of cmdLongOption, cmdShortOption:
      case key:
      of "p", "port":
        result.port = parseInt(value)
      of "path-prefix":
        result.pathPrefix = value
      of "heartbeat":
        result.heartbeat = parseInt(value)
      of "dashboard":
        result.dashboard = parseInt(value)
      of "d", "debug":
        result.debug = true
      of "h", "help":
        echo USAGE
        quit QuitSuccess
      of "v", "version":
        echo VERSION
        quit QuitSuccess
      else:
        echo "Nope"
        quit QuitFailure
    of cmdEnd:
      assert(false) # cannot happen

# Parse out command line arguments
parseArguments()

# Connect to MQTT
connect()

# Jester routes
routes:
  get "/":
   resp p("Arduinobot is running")

  get "/test":
    var obj = newJObject()
    for k, v in request.params:
      obj[k] = %v
    resp($obj, "application/json")

# Start Jester
runForever()