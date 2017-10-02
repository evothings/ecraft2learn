# Arduinobot is a service written in Nim, run as:
#
#   arduinobot -u:myuser -p:mysecretpassword tcp://some-mqtt-server.com:1883
#
# It will connect and pick up rest of configuration from the config topic.
# Default is then to listen on port 10000 for REST calls with JSON payloads
# and to listen to corresponding MQTT topics.

import jester, mqtt, MQTTClient, asyncdispatch,
  asyncnet, htmlgen, json, logging, os, strutils, sequtils, parseopt2, nuuid

import jobs

# Jester settings
settings:
  port = Port(10000)

# MQTT defaults
var serverUrl = "tcp://localhost:1883"
var clientID = "arduinobot-" & generateUUID()
var username = "test"
var password = "test"
var client: MQTTClient

# MQTT Callbacks
proc connect()
proc connectionLost(cause: string) =
  sleep(1000)
  # Reconnect
  connect()

proc messageArrived(topicName: string, message: MQTTMessage): cint =
  echo "messageArrived: ", topicName, " ", message.payload
  let parts = topicName.split('/')
  case parts[0]
    of "verify":
      var spec: JsonNode
      try:
        spec = parseJson(message.payload)
      except:
        echo getCurrentExceptionMsg()
        return
      let job = startVerifyJob(spec)
      discard client.publish("/verify/response/" & parts[1], $job, QOS0, false)
    of "status":
      let job = statusJob(parts[1])
      discard client.publish("/status/response/" & parts[1], $job, QOS0, false)
    else:
      echo "Unknown topic: ", topicName
  result = 1

proc deliveryComplete(dt: MQTTDeliveryToken) =
  discard # echo "deliveryComplete"

proc disconnect() =
  client.disconnect(1000)
  client.destroy()

proc subscribe() =
  client.subscribe("config", QOS0)
  client.subscribe("verify/+", QOS0)
  client.subscribe("status/+", QOS0)

proc connect() =
  try:
    echo "Connecting as " & clientID & " to " & serverUrl
    client = newClient(serverUrl, clientID, MQTTPersistenceType.None)
    var connectOptions = newConnectOptions()
    connectOptions.username = username
    connectOptions.password = password
    client.setCallbacks(connectionLost, messageArrived, deliveryComplete)
    client.connect(connectOptions)
    subscribe()
  except MQTTError:
    quit "MQTT exception: " & getCurrentExceptionMsg()

proc parseArguments() =
  for kind, key, value in getopt():
    case kind:
    of cmdArgument:
      serverUrl = key
    of cmdLongOption, cmdShortOption:
      case key:
      of "u", "username":
        username = value
      of "p", "password":
        password = value
      of "h", "help":
        echo "here is some help"
        quit QuitSuccess
      else:
        echo "No such option"
        quit QuitFailure
    of cmdEnd:
      assert(false) # cannot happen

# Parse out command line arguments
parseArguments()

initJobs()

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

  post "/verify":
    var spec: JsonNode
    try:
      spec = parseJson(request.body)
    except:
      resp Http400, "Unable to parse JSON body"
    let job = startVerifyJob(spec)
    resp($job, "application/json")

  post "/upload":
    var spec: JsonNode
    try:
      spec = parseJson(request.body)
    except:
      resp Http400, "Unable to parse JSON body"
    let job = startUploadJob(spec)
    resp($job, "application/json")

  get "/status/@id":
    ## Get status of a given job
    let job = statusJob(@"id")
    resp($job, "application/json")

# Start Jester
runForever()