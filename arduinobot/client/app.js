;(function () {
  /* global $ */

  // Constants
  var portNumber = 1884

  // MQTT
  var mqttClient = null
  var editor = null
  var sketch = 'blinky'

  function getParameterByName (name, url) {
    if (!url) url = window.location.href
    name = name.replace(/[\[\]]/g, '\\$&')
    var regex = new RegExp('[?&]' + name + '(=([^&#]*)|&|#|$)')
    var results = regex.exec(url)
    if (!results) return null
    if (!results[2]) return ''
    return decodeURIComponent(results[2].replace(/\+/g, ' '))
  }

  function main () {
    $(function () {
      // When document has loaded we attach FastClick to
      // eliminate the 300 ms delay on click events.
      window.FastClick.attach(document.body)

      // Event listener for Back button.
      $('.app-back').on('click', function () { window.history.back() })

      // Create editor
      editor = window.CodeMirror.fromTextArea(document.getElementById('code'), {
        lineNumbers: true,
        matchBrackets: true,
        mode: 'text/x-csrc'
      })
      editor.setSize('100%', 500)

      // Disable buttons from start
      disableButtons(true)

      // Sketch name to fetch
      sketch = getParameterByName('sketch')
      if (sketch === null) {
        sketch = 'blinky'
      }

      // Verify and Upload buttons
      $('#verify').mouseup(function () { this.blur(); verify(false) })
      $('#upload').mouseup(function () { this.blur(); verify(true) })
      editor.setOption('extraKeys', {
        F5: function (cm) { verify(false) },
        F6: function (cm) { verify(true) }
      })

      // Server changed
      $('#server').change(function () { connect() })

      // Call device ready directly (this app can work without Cordova).
      onDeviceReady()
    })
  }

  function disableButtons (disable) {
    $('#verify').prop('disabled', disable)
    $('#upload').prop('disabled', disable)
  }

  function onDeviceReady () {
    connect()
  }

  function connect () {
    disconnectMQTT()
    connectMQTT()
    //showAlert('info', '', 'Connecting to MQTT ...', true)
  }

  // We need a unique client id when connecting to MQTT
  function guid () {
    function s4 () {
      return Math.floor((1 + Math.random()) * 0x10000)
        .toString(16)
        .substring(1)
    }
    return s4() + s4() + '-' + s4() + '-' + s4() + '-' + s4() + '-' + s4() + s4() + s4()
  }

  function connectMQTT () {
    var clientID = guid()
    mqttClient = new window.Paho.MQTT.Client(getServer(), portNumber, clientID)
    mqttClient.onConnectionLost = onConnectionLost
    mqttClient.onMessageArrived = onMessageArrived
    var options =
      {
        userName: 'test',
        password: 'test',
        useSSL: false,
        reconnect: true,
        onSuccess: onConnectSuccess,
        onFailure: onConnectFailure
      }
    mqttClient.connect(options)
  }

  function getSource () {
    return editor.getValue()
  }

  function setSource (src) {
    return editor.setValue(src)
  }

  function getServer () {
    return $('#server').val()
  }

  function cursorWait () {
    $('body').css('cursor', 'progress')
  }

  function cursorDefault () {
    $('body').css('cursor', 'default')
  }

  function verify (upload) {
    cursorWait()
    disableButtons(true)
    clearAlerts()
    if (upload) {
      showAlert('info', 'Compiling and uploading ...', '', false)
    } else {
      showAlert('info', 'Compiling ...', '', false)
    }

    // Select command
    var command = 'verify'
    if (upload) {
      command = 'upload'
    }

    // Generate an id for the response we want to get
    var responseId = guid()

    // Subscribe in advance for that response
    subscribe('response/' + command + '/' + responseId)

    // Construct a job to run
    var job = {
      'sketch': sketch + '.ino',
      'src': window.btoa(getSource())
    }

    // Save sketch
    publish('sketch/' + sketch, job, true)

    // Submit job
    publish(command + '/' + responseId, job)
  }

  function handleResponse (topic, payload) {
    var jobId = payload.id
    subscribe('result/' + jobId)
    unsubscribe(topic)
  }

  function handleSketch (topic, payload) {
    if (payload.sketch === (sketch + '.ino')) {
      var newSource = window.atob(payload.src)
      if (getSource() !== newSource) {
        setSource(newSource)
      }
    }
  }

  function handleResult (topic, payload) {
    var type = payload.type
    var command = payload.command
    unsubscribe(topic)
    if (type === 'success') {
      if (command === 'verify') {
        console.log('Exit code: ' + payload.exitCode)
        console.log('Stdout: ' + payload.stdout)
        console.log('Stderr: ' + payload.stderr)
        console.log('Errors: ' + JSON.stringify(payload.errors))
        clearAlerts()
        if (payload.exitCode === 0) {
          showAlert('success', 'Success!', 'No compilation errors')
        } else {
          showAlert('danger', 'Failed!', 'Compilation errors detected')
        }
      } else {
        console.log('Exit code: ' + payload.exitCode)
        console.log('Stdout: ' + payload.stdout)
        console.log('Stderr: ' + payload.stderr)
        console.log('Errors: ' + JSON.stringify(payload.errors))
        clearAlerts()
        if (payload.exitCode === 0) {
          showAlert('success', 'Success!', 'No compilation errors and upload was performed correctly')
        } else {
          showAlert('danger', 'Failed!', 'Compilation errors detected, upload not performed')
        }
      }
    } else {
      console.log('Fail:' + payload)
    }
    cursorDefault()
    disableButtons(false)
  }

  function onMessageArrived (message) {
    var payload = JSON.parse(message.payloadString)
    console.log('Topic: ' + message.topic + ' payload: ' + message.payloadString)
    handleMessage(message.topic, payload)
  }

  function onConnectSuccess (context) {
    disableButtons(false)
    showAlert('info', '', 'Connected', true)
    subscribeToSketch()
  }

  function onConnectFailure (error) {
    console.log('Failed to connect: ' + JSON.stringify(error))
    showAlert('danger', 'Connect failed!', 'Reconnecting ...', true)
  }

  function onConnectionLost (responseObject) {
    console.log('Connection lost: ' + responseObject.errorMessage)
    disableButtons(true)
    showAlert('warning', 'Connection was lost!', 'Reconnecting ...', true)
  }

  function publish (topic, payload, retained = false) {
    var message = new window.Paho.MQTT.Message(JSON.stringify(payload))
    message.destinationName = topic
    message.retained = retained
    mqttClient.send(message)
  }

  function subscribe (topic) {
    mqttClient.subscribe(topic)
    console.log('Subscribed: ' + topic)
  }

  function subscribeToSketch () {
    subscribe('sketch/' + sketch)
  }

  function unsubscribe (topic) {
    mqttClient.unsubscribe(topic)
    console.log('Unsubscribed: ' + topic)
  }

  function disconnectMQTT () {
    if (mqttClient) mqttClient.disconnect()
    mqttClient = null
  }

  function clearAlerts () {
    // Remove all visible alerts
    $('#alerts').empty()
  }

  function showAlert (type, title, message, fading = false) {
    // Clone template HTML. Type can be: 'success', 'info', 'warning', 'danger'
    var template = $('.alert-template')
    var el = template.clone()
    el.removeClass('alert-template')
    el.removeClass('hide')
    el.addClass('alert-' + type)
    // Set message, append to DOM, hook up as alert and show
    el.find('#alert-message').append('<strong>' + title + '</strong> ' + message)
    $('#alerts').append(el)
    el.alert()
    el.show()
    if (fading) {
      setTimeout(function () {
        el.alert('close')
      }, 2000)
    }
  }

  function handleMessage (topic, payload) {
    try {
      if (topic.startsWith('response/')) {
        return handleResponse(topic, payload)
      } else if (topic.startsWith('result/')) {
        return handleResult(topic, payload)
      } else if (topic.startsWith('sketch/')) {
        return handleSketch(topic, payload)
      }
      console.log('Unknown topic: ' + topic)
    } catch (error) {
      console.log('Error handling payload: ' + error)
    }
  }

  // Call main function to initialise app.
  main()
})()
