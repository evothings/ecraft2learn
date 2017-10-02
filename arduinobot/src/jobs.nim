import nuuid, json, tables, os, osproc, base64, threadpool

# Just constants for now
const
  arduinoIde = "~/arduino-1.8.3/arduino"
  arduinoBoard = "arduino:avr:uno"

# A single object variant works fine since it's not complex
type
  JobKind = enum jkVerify, jkUpload
  Job = ref object
    case kind: JobKind
    of jkVerify, jkUpload:
      id: string         # UUID on creation of job
      path: string       # Full path to tempdir where source is unpacked
      sketchPath: string # Full path sketch file like: /.../blabla/foo/foo.ino
      sketch: string     # name of sketch file only, like: foo.ino
      src: string        # base64 source of sketch, for multiple files, what do we do?

# Keep track of our jobs and their results via id, these tables are kept in the main thread.
var jobs {.threadvar.}: Table[string, Job]
var jobResults {.threadvar.}: Table[string, FlowVar[JsonNode]]

# We need to create tables explicitly
proc initJobs*() =
  jobs = initTable[string, Job]()
  jobResults = initTable[string, FlowVar[JsonNode]]()

proc createVerifyJob(spec: JsonNode): Job =
  ## Create a new job with a UUID and put it into the table
  result = Job(kind: jkVerify, sketch: spec["sketch"].getStr , src: spec["src"].getStr, id: generateUUID())  
  jobs[result.id] = result

proc createUploadJob(spec: JsonNode): Job =
  ## Create a new job with a UUID and put it into the table
  result = Job(kind: jkUpload, sketch: spec["sketch"].getStr , src: spec["src"].getStr, id: generateUUID())  
  jobs[result.id] = result

proc unpack(job: Job) =
  ## Create a build directory and unpack sources into it.
  let cwd = getCurrentDir()
  job.path = cwd / "builds" / $job.id
  var (_, name, _) = splitFile(job.sketch)
  job.sketchPath = job.path / name / job.sketch
  createDir(job.path / name)
  writeFile(job.sketchPath, decode(job.src))

proc verify(job: Job):  tuple[output: TaintedString, exitCode: int] =
  ## Run --verify command via Arduino IDE
  echo "Starting verify job " & job.id
  let cmd = arduinoIde & " --verify --board " & arduinoBoard & " --pref build.path=" & job.path & " " & job.sketchPath
  echo "Command " & cmd
  result = execCmdEx(cmd)
  sleep(30000)
  echo "Job done " & job.id
  return

proc upload(job: Job):  tuple[output: TaintedString, exitCode: int] =
  ## Run --upload command via Arduino IDE
  echo "Starting upload job " & job.id
  # --port portname --verbose-build / --verbose-upload / --verbose
  let cmd = arduinoIde & " --upload --preserve-temp-files --board " & arduinoBoard & " --pref build.path=" & job.path & " " & job.sketchPath
  echo "Command " & cmd
  result = execCmdEx(cmd)
  sleep(30000)
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
  ## Perform a job and return proper JSON depending on result
  try:
    var (output, exitCode) = job.run()
    return %*{"type": "success", "output": output, "exitCode": exitCode}
  except:
    return %*{"type": "error", "message": "Failed job"}

proc start(job: Job) =
  ## Start running a job on the threadpool and put the result FlowVar
  ## into a table for later retrieval
  jobResults[job.id] = spawn perform(job)

proc startVerifyJob*(spec: JsonNode): JsonNode =
  var job = createVerifyJob(spec)
  job.start()
  return %*{"id": job.id}

proc startUploadJob*(spec: JsonNode): JsonNode =
  var job = createUploadJob(spec)
  job.start()
  return %*{"id": job.id}

proc statusJob*(id: string): JsonNode =
  if jobResults.hasKey(id):
    let res = jobResults[id]
    if res.isReady:
      return %*{"id": id, "status": "done", "result": ^res}
    else:
      return %*{"id": id, "status": "working"}
  else:
    return %*{"error": "no such id"}