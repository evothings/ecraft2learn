;(function () {
  /* global $ */

  // Keeping state in a global object to make debugging easier
  if (!window.bot) { window.bot = {} }

  // MQTT
  var mqttClient = null
  var subscribeTopic = 'decoded/#'

  function main () {
    $(function () {
      // When document has loaded we attach FastClick to
      // eliminate the 300 ms delay on click events.
      window.FastClick.attach(document.body)

      // Event listener for Back button.
      $('.app-back').on('click', function () { window.history.back() })

      // Verify and Upload
      $('#verify').click(function () { verify() })
      $('#upload').click(function () { upload() })

      // Call device ready directly (this app can work without Cordova).
      onDeviceReady()
    })
  }

  function onDeviceReady () {
    // Connect to MQTT
    connect()
  }

  function connect () {
    disconnectMQTT()
    connectMQTT()
    showMessage('Connecting')
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
    mqttClient = new window.Paho.MQTT.Client('lora.evothings.com', 1884, clientID)
    mqttClient.onConnectionLost = onConnectionLost
    mqttClient.onMessageArrived = onMessageArrived
    var options =
      {
        userName: 'admin',
        password: 'lots',
        useSSL: true,
        reconnect: true,
        onSuccess: onConnectSuccess,
        onFailure: onConnectFailure
      }
    mqttClient.connect(options)
  }

  function verify () {

  }

  function upload () {
    
  }

  function onMessageArrived (message) {
    var payload = JSON.parse(message.payloadString)
    console.log('Topic: ' + message.topic + ' payload: ' + message.payloadString)
    handleMessage(payload)
  }

  function onConnectSuccess (context) {
    subscribe()
    showMessage('Connected')
    // For debugging: publish({ message: 'Hello' })
  }

  function onConnectFailure (error) {
    console.log('Failed to connect: ' + JSON.stringify(error))
    showMessage('Connect failed')
  }

  function onConnectionLost (responseObject) {
    console.log('Connection lost: ' + responseObject.errorMessage)
    showMessage('Connection was lost')
  }

  function publish (json) {
    var message = new window.Paho.MQTT.Message(JSON.stringify(json.message))
    message.destinationName = json.topic
    mqttClient.send(message)
  }

  function subscribe () {
    mqttClient.subscribe(subscribeTopic)
    console.log('Subscribed: ' + subscribeTopic)
  }

  function unsubscribe () {
    mqttClient.unsubscribe(subscribeTopic)
    console.log('Unsubscribed: ' + subscribeTopic)
  }

  function disconnectMQTT () {
    if (mqttClient) mqttClient.disconnect()
    mqttClient = null
  }

  function showMessage (message) {
    //document.querySelector('.mdl-snackbar').MaterialSnackbar.showSnackbar({message: message})
  }

  function handleMessage (payload) {
    try {
      // Set current timestamp.
      // currentTimeStamp = new Date(payload.datetime).getTime()

    } catch (error) {
      console.log('Error handling payload: ' + error)
    }
  }

  // Call main function to initialise app.
  main()
})()
