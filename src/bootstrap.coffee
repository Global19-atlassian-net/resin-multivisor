Promise = require 'bluebird'
_ = require 'lodash'
knex = require './db'
utils = require './utils'
deviceRegister = require 'resin-register-device'
{ resinApi } = require './request'
fs = Promise.promisifyAll(require('fs'))
crypto = require 'crypto'
appConfig = require './config'
EventEmitter = require('events').EventEmitter

module.exports = do ->
	configPath = '/boot/config.json'
	userConfig = {}

	bootstrapper = new EventEmitter()

	loadPreloadedApps = ->
		#To-Do

	bootstrap = ->
		Promise.try ->
			userConfig.deviceType ?= 'raspberry-pi'
			if userConfig.registered_at?
				return userConfig
			deviceRegister.register(resinApi, userConfig)
			.catch (err) ->
				# Do not fail if device already exists
				return {} if err.message = '"uuid" must be unique.'
			.then (device) ->
				userConfig.registered_at = Date.now()
				userConfig.deviceId = device.id if device.id?
				fs.writeFileAsync(configPath, JSON.stringify(userConfig))
			.return(userConfig)
		.then (userConfig) ->
			console.log('Finishing bootstrapping')
			Promise.all([
				knex('config').truncate()
				.then ->
					knex('config').insert([
						{ key: 'uuid', value: userConfig.uuid }
						{ key: 'apiKey', value: userConfig.apiKey }
						{ key: 'username', value: userConfig.username }
						{ key: 'userId', value: userConfig.userId }
						{ key: 'version', value: utils.supervisorVersion }
					])
			])
			.tap ->
				doneBootstrapping()

	readConfigAndEnsureUUID = ->
		# Load config file
		fs.readFileAsync(configPath, 'utf8')
		.then(JSON.parse)
		.then (config) ->
			userConfig = config
			return userConfig.uuid if userConfig.uuid?
			Promise.try ->
				deviceRegister.generateUUID()
			.then (uuid) ->
				userConfig.uuid = uuid
				fs.writeFileAsync(configPath, JSON.stringify(userConfig))
			.return(userConfig.uuid)
		.catch (err) ->
			console.log('Error generating UUID: ', err)
			Promise.delay(config.bootstrapRetryDelay)
			.then ->
				readConfigAndEnsureUUID()

	bootstrapOrRetry = ->
		utils.mixpanelTrack('Device bootstrap')
		bootstrap().catch (err) ->
			utils.mixpanelTrack('Device bootstrap failed, retrying', {error: err, delay: config.bootstrapRetryDelay})
			setTimeout(bootstrapOrRetry, config.bootstrapRetryDelay)

	doneBootstrapping = ->
		bootstrapper.bootstrapped = true
		bootstrapper.emit('done')

	bootstrapper.bootstrapped = false
	bootstrapper.startBootstrapping = ->
		knex('config').select('value').where(key: 'uuid')
		.then ([ uuid ]) ->
			if uuid?.value
				doneBootstrapping()
				return uuid.value
			console.log('New device detected. Bootstrapping..')
			readConfigAndEnsureUUID()
			.tap ->
				loadPreloadedApps()
			.tap ->
				bootstrapOrRetry()

	return bootstrapper
