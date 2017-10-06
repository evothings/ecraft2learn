# Arduinobot is a service written in Nim, run as:
#
#   arduinobot -u:myuser -p:mysecretpassword tcp://some-mqtt-server.com:1883
#
# It will connect and pick up rest of configuration from the config topic.
# Default is then to listen on port 10000 for REST calls with JSON payloads
# and to listen to corresponding MQTT topics.
#
# * Jester runs in the main thread, asynchronously. 
# * MQTT is handled in the messengerThread and uses a Channel to publish.
# * Jobs are spawned on the threadpool and results are published on MQTT via the messenger Channel.
#
# Topics used:
#
# verify/<response-id>             - Payload is JSON specification for a job.
# upload/<response-id>             - Payload is JSON specification for a job.
# response/<command>/<response-id> - Responses to requests are published here as JSON, typically with job id.
# result/<job-id>                  - Results from Jobs are published here as JSON.

import jester, asyncdispatch, mqtt, MQTTClient,
  asyncnet, htmlgen, json, logging, os, strutils,
  sequtils, nuuid, tables, osproc, base64,
  threadpool, docopt

# Jester settings
settings:
  port = Port(10000)

# MQTT defaults
var clientID = "arduinobot-" & generateUUID()
var username, password, serverUrl: string

# Arduino defaults
const
  arduinoIde = "~/arduino-1.8.4/arduino"
  arduinoBoard = "arduino:avr:uno"
  arduinoPort = "/dev/ttyACM0"

template buildsDirectory: string = getCurrentDir() / "builds"

let help = """
  arduinobot
  
  Usage:
    arduinobot [-u USERNAME] [-p PASSWORD] [-s MQTTURL]
    arduinobot (-h | --help)
    arduinobot (-v | --version)
  
  Options:
    -u USERNAME      Set MQTT username [default: test].
    -p PASSWORD      Set MQTT password [default: test].
    -s MQTTURL       Set URL for the MQTT server [default: tcp://localhost:1883]
    -h --help        Show this screen.
    -v --version     Show version.
  """  
let args = docopt(help, version = "arduinobot 0.1.0")
username = $args["-u"]
password = $args["-p"]
serverUrl = $args["-s"]

type
  MessageKind = enum connect, publish, stop
  Message = object
    case kind: MessageKind
    of connect:
      serverUrl, clientID, username, password: string
    of publish:
      topic, payload: string
    of stop:
      nil

var
  messengerThread: Thread[void]
  channel: Channel[Message]

proc publishMQTT*(topic, payload: string) =
  channel.send(Message(kind: publish, topic: topic, payload: payload))

proc connectMQTT*(s, c, u, p: string) =
  channel.send(Message(kind: connect, serverUrl: s, clientID: c, username: u, password: p))
  
proc stopMessenger() {.noconv.} =
  channel.send(Message(kind: stop))
  joinThread(messengerThread)
  close(channel)
  
proc connectToServer(serverUrl, clientID, username, password: string): MQTTClient =
  try:
    echo "Connecting as " & clientID & " to " & serverUrl
    result = newClient(serverUrl, clientID, MQTTPersistenceType.None)
    var connectOptions = newConnectOptions()
    connectOptions.username = username
    connectOptions.password = password
    result.connect(connectOptions)
    result.subscribe("config", QOS0)
    result.subscribe("verify/+", QOS0)
    result.subscribe("upload/+", QOS0)
    result.subscribe("status/+", QOS0)
  except MQTTError:
    quit "MQTT exception: " & getCurrentExceptionMsg()

proc startVerifyJob(spec: JsonNode): JsonNode {.gcsafe.}
proc handleVerify(responseId, payload: string) =
  var spec: JsonNode
  try:
    spec = parseJson(payload)
    let job = startVerifyJob(spec)
    publishMQTT("response/verify/" & responseId, $job)
  except:
    stderr.writeLine "Unable to parse JSON body: " & payload
    
proc startUploadJob(spec: JsonNode): JsonNode {.gcsafe.}    
proc handleUpload(responseId, payload: string) =
  var spec: JsonNode
  try:
    spec = parseJson(payload)
    let job = startUploadJob(spec)
    publishMQTT("response/upload/" & responseId, $job)
  except:
    stderr.writeLine "Unable to parse JSON body: " & payload

proc handleMessage(topic: string, message: MQTTMessage) =
  var parts = topic.split('/')
  if parts.len == 2:
    case parts[0]
    of "verify":
      handleVerify(parts[1], message.payload)
    of "upload":
      handleUpload(parts[1], message.payload)
  else:
    stderr.writeLine "Unknown topic: " & topic

proc messengerLoop() {.thread.} =
  var client: MQTTClient
  while true:
    if client.isConnected:
      var topicName: string
      var message: MQTTMessage
      # Wait upto 100 ms to receive an MQTT message
      let timeout = client.receive(topicName, message, 100)
      if not timeout:
        echo "Topic: " & topicName & " payload: " & message.payload
        handleMessage(topicName, message)
    # If we have something in the channel, handle it
    var (gotit, msg) = tryRecv(channel)
    if gotit:
      case msg.kind
      of connect:
        client = connectToServer(msg.serverUrl, msg.clientID, msg.username, msg.password)
      of publish:
        echo "Publishing " & msg.topic & " " & msg.payload
        discard client.publish(msg.topic, msg.payload, QOS0, false)
      of stop:
        client.disconnect(1000)
        client.destroy()      
        break

proc startMessenger(serverUrl, clientID, username, password: string) =
  open(channel)
  messengerThread.createThread(messengerLoop)
  addQuitProc(stopMessenger)
  connectMQTT(serverUrl, clientID, username, password)

# A single object variant works fine since it's not complex
type
  JobKind = enum jkVerify, jkUpload
  Job = ref object
    case kind: JobKind
    of jkVerify, jkUpload:
      id: string         # UUID on creation of job
      board: string      # The board type string, like "arduino:avr:uno" or "arduino:avr:nano:cpu=atmega168"
      port: string       # The port to use, like "/dev/ttyACM0"
      path: string       # Full path to tempdir where source is unpacked
      sketchPath: string # Full path to sketch file like: /.../blabla/foo/foo.ino
      sketch: string     # name of sketch file only, like: foo.ino
      src: string        # base64 source of sketch, for multiple files, what do we do?

proc createVerifyJob(spec: JsonNode): Job =
  ## Create a new job with a UUID and put it into the table
  Job(kind: jkVerify, board: arduinoBoard, port: arduinoPort, sketch: spec["sketch"].getStr,
    src: spec["src"].getStr, id: generateUUID())  

proc createUploadJob(spec: JsonNode): Job =
  ## Create a new job with a UUID and put it into the table
  Job(kind: jkUpload, board: arduinoBoard, port: arduinoPort, sketch: spec["sketch"].getStr,
    src: spec["src"].getStr, id: generateUUID())  

proc cleanWorkingDirectory() =
  echo "Cleaning out builds directory: " & buildsDirectory
  removeDir(buildsDirectory)
  createDir(buildsDirectory)

proc unpack(job: Job) =
  ## Create a job directory and unpack sources into it.
  job.path = buildsDirectory / $job.id
  var name = extractFilename(job.sketch)
  job.sketchPath = job.path / name / job.sketch
  createDir(job.path / name)
  writeFile(job.sketchPath, decode(job.src))

proc verify(job: Job):  tuple[output: TaintedString, exitCode: int] =
  ## Run --verify command via Arduino IDE
  echo "Starting verify job " & job.id
  let cmd = arduinoIde & " --verbose --verify --board " & job.board &
    " --preserve-temp-files --pref build.path=" & job.path & " " & job.sketchPath
  echo "Command " & cmd
  result = execCmdEx(cmd)
  echo "Job done " & job.id
  return

proc upload(job: Job):  tuple[output: TaintedString, exitCode: int] =
  ## Run --upload command via Arduino IDE
  echo "Starting upload job " & job.id
  # --verbose-build / --verbose-upload / --verbose
  let cmd = arduinoIde & " --verbose --upload --board " & job.board & " --port " & job.port &
    " --preserve-temp-files --pref build.path=" & job.path & " " & job.sketchPath
  echo "Command " & cmd
  result = execCmdEx(cmd)
  echo "Job done " & job.id
  return

proc run(job: Job): tuple[output: TaintedString, exitCode: int] =
  ## Run a job by executing all tasks needed
  unpack(job)
  case job.kind
  of jkVerify:
    return job.verify()
  of jkUpload:
    return job.upload()

proc perform(job: Job): JsonNode =
  ## Perform a job and publish JSON result
  try:
    var (output, exitCode) = job.run()
    result = %*{"type": "success", "output": output, "exitCode": exitCode}
  except:
    result = %*{"type": "error", "message": "Failed job"}
  publishMQTT("result/" & job.id, $result)

proc startVerifyJob(spec: JsonNode): JsonNode =
  var job = createVerifyJob(spec)
  discard spawn perform(job)
  return %*{"id": job.id}

proc startUploadJob(spec: JsonNode): JsonNode =
  var job = createUploadJob(spec)
  discard spawn perform(job)
  return %*{"id": job.id}

proc getJobStatus*(id: string): JsonNode =
#  if jobResults.hasKey(id):
#    let res = jobResults[id]
#    if res.isReady:
#      return %*{"id": id, "status": "done", "result": ^res}
#    else:
#      return %*{"id": id, "status": "working"}
#  else:
   return %*{"error": "no such id"}

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
      stderr.writeLine "Unable to parse JSON body: " & request.body      
      resp Http400, "Unable to parse JSON body"
    let job = startVerifyJob(spec)
    resp($job, "application/json")

  post "/upload":
    var spec: JsonNode
    try:
      spec = parseJson(request.body)
    except:
      stderr.writeLine "Unable to parse JSON body: " & request.body      
      resp Http400, "Unable to parse JSON body"
    let job = startUploadJob(spec)
    resp($job, "application/json")

  get "/status/@id":
    ## Get status of a given job
    let job = getJobStatus(@"id")
    resp($job, "application/json")

# Clean out working directory
cleanWorkingDirectory()

# Start MQTT messenger thread
startMessenger(serverUrl, clientID, username, password)

# Start Jester
runForever()