inner_socket = io.connect(location.hostname, {
	"connect timeout": 2000
}) if io?
sync = {}
users = {}
sync_offsets = []
sync_offset = 0
public_rooms = ['lobby', 'hsquizbowl']

sock = {
	listeners: {},
	disconnect: ->
		if inner_socket.socket.connecting
			virtual_connect = ->
				if virtual_server?
					virtual_server.connect()
				else
					setTimeout virtual_connect, 100
			virtual_connect()
		inner_socket.disconnect()

	emit: (name, data, fn) ->
		if connected()
			inner_socket.emit(name, data, fn)
		else if virtual_server?
			if name of virtual_server
				result = virtual_server[name](data)
				fn(result) if fn
				renderPartial()
			else
				console.log name, data, fn
		else
			if $('.active .not-loaded').length > 0
				el = $('.active .not-loaded')
			else
				el = $('<p>').addClass('not-loaded well')
				addImportant el
			el.data 'num', (el.data('num') || 0) + 1
			el.text("Offline component not loaded ")
			if el.data('num') > 1
				el.append($('<span>').addClass('label').text("x"+el.data('num')))

	server_emit: (name, data) ->
		sock.listeners[name](data)

	on: (name, listen) ->
		inner_socket.on(name, listen) if inner_socket?
		sock.listeners[name] = listen
}


unless io?
	#do stuff if socket IO doesnt exist, i.e., it's starting up offline
	$('.new-room').remove()


connected = -> inner_socket? and inner_socket.socket.connected

# $('html').toggleClass 'touchscreen', Modernizr.touch

jQuery.fn.disable = (value) ->
	current = $(this).attr('disabled') is 'disabled'
	if current != value
		$(this).attr 'disabled', value

mobileLayout = -> 
	if window.matchMedia
		matchMedia('(max-width: 768px)').matches
	else
		return false

avg = (list) ->
	sum(list) / list.length

sum = (list) ->
	s = 0
	s += item for item in list
	s

stdev = (list) ->
	mu = avg(list)
	Math.sqrt avg((item - mu) * (item - mu) for item in list)

cumsum = (list, rate) ->
	s = 0 #start nonzero, allow pause before rendering
	for num in [5].concat(list).slice(0, -1)
		s += Math.round(num) * rate #always round!



# So in this application, we have to juggle around not one, not two, but three notions of time
# (and possibly four if you consider freezable time, which needs a cooler name, like what 
# futurama calls intragnizent, so I'll use that, intragnizent time) anyway. So we have three
# notions of time. The first and simplest is server time, which is an uninterruptable number
# of milliseconds recorded by the server's +new Date. Problem is, that the client's +new Date
# isn't exactly the same (can be a few seconds off, not good when we're dealing with precisions
# of tens of milliseconds). However, we can operate off the assumption that the relative duration
# of each increment of time is the same (as in, the relativistic effects due to players in
# moving vehicles at significant fractions of the speed of light are largely unaccounted for
# in this version of the application), and even imprecise quartz clocks only loose a second
# every day or so, which is perfectly okay in the short spans of minutes which need to go 
# unadjusted. So, we can store the round trip and compare the values and calculate a constant
# offset between the client time and the server time. However, for some reason or another, I
# decided to implement the notion of "pausing" the game by stopping the flow of some tertiary
# notion of time (this makes the math relating to calculating the current position of the read
# somewhat easier).

# This is implemented by an offset which is maintained by the server which goes on top of the
# notion of server time. 

# Why not just use the abstraction of that pausable (tragnizent) time everywhere and forget
# about the abstraction of server time, you may ask? Well, there are two reasons, the first
# of which is that two offsets are maintained anyway (the first prototype only used one, 
# and this caused problems on iOS because certain http requests would have extremely long
# latencies when the user was scrolling, skewing the time, this new system allows the system
# to differentiate a pause from a time skew and maintain a more precise notion of time which
# is calculated by a moving window average of previously observed values)

# The second reason, is that there are times when you actually need server time. Situations
# like when you're buzzing and you have a limited time to answer before your window shuts and
# control gets handed back to the group.


time = -> if sync.time_freeze then sync.time_freeze else serverTime() - sync.time_offset

serverTime = -> new Date - sync_offset


window.onbeforeunload = ->
	if inner_socket?
		localStorage.old_socket = inner_socket.socket.sessionid
	return undefined

sock.on 'echo', (data, fn) ->
	fn 'alive'

sock.on 'disconnect', ->
	sync.attempt = null if sync.attempt?.user isnt public_id # get rid of any buzzes
	line = $('<div>').addClass 'well'
	line.append $('<p>').append("You were ", $('<span class="label label-important">').text("disconnected"), 
			" from the server for some reason. ", $('<em>').text(new Date))
	line.append $('<p>').append("This may be due to a drop in the network 
			connectivity or a malfunction in the server. The client will automatically 
			attempt to reconnect to the server and in the mean time, the app has automatically transitioned
			into <b>offline mode</b>. You can continue playing alone with a limited offline set
			of questions without interruption. However, you might want to try <a href=''>reloading</a>.")
	addImportant $('<div>').addClass('log disconnect-notice').append(line)
	sock.emit 'init_offline', 'yay' #obviously server wont pay attention to that
	renderState()

sock.on 'application_update', ->
	applicationCache.update() if applicationCache?

sock.on 'application_force_update', ->
	$('#update').slideDown()

public_name = null
public_id = null

sock.on 'connect', ->
	$('.actionbar button').disable false
	$('.timer').removeClass 'disabled'
	$('.disconnect-notice').slideUp()

	sock.emit 'disco', {old_socket: localStorage.old_socket}

sock.on 'redirect', (url) ->
	window.location = url

sock.on 'alert', (text) ->
	console.log 'got alert', text
	window.alert(text)

sock.on 'joined', (data) ->
	public_name = data.name
	public_id = data.id
	$('#username').val public_name
	$('#username').disable false



$('#username').keyup (e) ->
	if e.keyCode is 13
		$(this).blur()

	if $(this).val().length > 0
		sock.emit 'rename', $(this).val()

createCategoryList = ->
	$('.custom-category').empty()
	
	return unless sync.distribution
	
	for cat in sync.categories
		item = $('<div>').addClass('category-item').appendTo('.custom-category').data('value', cat)
		
		$('<span>').addClass('name').text(cat).appendTo item
		
		picker = $('<div>').addClass('btn-group pull-right dist-picker').appendTo item
		
		$('<button>').addClass('btn btn-small decrease disabled')
			.append($('<i>').addClass('icon-minus'))
			.appendTo(picker)
		
		$('<button>').addClass('btn btn-small increase disabled')
			.append($('<i>').addClass('icon-plus'))
			.appendTo(picker)

		$('<span>').addClass('percentage pull-right').css('color', 'gray').appendTo item
		renderCategoryItem(item)

renderCategoryItem = (item) ->
	return unless sync.distribution
	s = 0
	s += val for cat, val of sync.distribution
	value = $(item).data('value')

	percentage = sync.distribution[value] / s
	$(item).find('.percentage').html("#{Math.round(100 * percentage)}% &nbsp;")
	$(item).find('.increase').removeClass('disabled')

	if percentage > 0 and s > 1
		$(item).find('.decrease').removeClass('disabled')
	else
		$(item).find('.decrease').addClass('disabled')
		$(item).find('.name').css('font-weight', 'normal')
	
	if percentage > 0
		$(item).find('.name').css('font-weight', 'bold')
		

$('.dist-picker .increase').live 'click', (e) ->
	return unless sync.distribution
	item = $(this).parents('.category-item')
	sync.distribution[$(item).data('value')]++
	sock.emit 'distribution', sync.distribution
	for item in $('.custom-category .category-item')
		renderCategoryItem(item)

$('.dist-picker .decrease').live 'click', (e) ->
	return unless sync.distribution
	item = $(this).parents('.category-item')
	s = 0
	s += val for cat, val of sync.distribution

	if sync.distribution[$(item).data('value')] > 0 and s > 1
		sync.distribution[$(item).data('value')]--
		sock.emit 'distribution', sync.distribution
	for item in $('.custom-category .category-item')
		renderCategoryItem(item)


synchronize = (data) ->
	if data
		# console.log JSON.stringify(data)

		sync_offsets.push +new Date - data.real_time

		compute_sync_offset()

		# console.log 'sync', data
		for attr of data
			sync[attr] = data[attr]

	if (data and 'difficulties' of data) or ($('.difficulties')[0].options.length == 0 and sync.difficulties)
		# re-generate the lists, yaaay
		$('.difficulties option').remove()
		$('.difficulties')[0].options.add new Option("Any", '')
		for dif in sync.difficulties
			$('.difficulties')[0].options.add new Option(dif, dif)

		$('.categories option').remove()
		$('.categories')[0].options.add new Option('Everything', '')
		$('.categories')[0].options.add new Option('Custom', 'custom')

		for cat in sync.categories
			$('.categories')[0].options.add new Option(cat, cat)
			
		createCategoryList()
		
	if sync.category is 'custom'
		$('.custom-category').slideDown()
	
	$('.categories').val sync.category
	
	
	$('.difficulties').val sync.difficulty

	$('.multibuzz').attr 'checked', !sync.max_buzz

	if $('.settings').is(':hidden')
		$('.settings').slideDown()
	
	if sync.attempt
		updateTextAnnotations()
	
	if !data or 'users' of data
		for user in sync.users
			user.room = sync.name
			users[user.id] = user

	if public_id of users and 'show_typing' of users[public_id]
		$('.livechat').attr 'checked', users[public_id].show_typing
		$('.sounds').attr 'checked', users[public_id].sounds
		$('.teams').val users[public_id].team


	if !data or 'users' of data
		renderState()
	else
		renderPartial()

	
	if sync.attempt
		guessAnnotation sync.attempt

	wpm = Math.round(1000 * 60 / 5 / sync.rate)
	if !$('.speed').data('last_update') or new Date - $(".speed").data("last_update") > 1337
		if Math.abs($('.speed').val() - wpm) > 1
			$('.speed').val(wpm)


	
	if !sync.attempt or sync.attempt.user isnt public_id
		setActionMode '' if actionMode in ['guess', 'prompt']
	else
		if sync.attempt.prompt
			if actionMode isnt 'prompt'
				setActionMode 'prompt' 
				$('.prompt_input').val('').focus()
		else
			setActionMode 'guess' if actionMode isnt 'guess'

	# if sync.time_offset isnt null
	# 	$('#time_offset').text(sync.time_offset.toFixed(1))




sock.on 'sync', (data) ->
	synchronize(data)

	
latency_log = []
testLatency = ->
	return unless connected()
	initialTime = +new Date
	sock.emit 'echo', {}, (firstServerTime) ->
		recieveTime = +new Date
		sock.emit 'echo', {}, (secondServerTime) ->
			secondTime = +new Date
			CSC1 = recieveTime - initialTime
			CSC2 = secondTime - recieveTime
			SCS1 = secondServerTime - firstServerTime

			sync_offsets.push recieveTime - firstServerTime
			sync_offsets.push secondTime - secondServerTime

			latency_log.push CSC1
			latency_log.push SCS1
			latency_log.push CSC2
			# console.log CSC1, SCS1, CSC2

			compute_sync_offset()

			if latency_log.length > 0
				$('#latency').text(avg(latency_log).toFixed(1) + "/" + stdev(latency_log).toFixed(1) + " (#{latency_log.length})")


setTimeout ->
	testLatency()
	setInterval -> 
		testLatency()
	, 30 * 1000
, 2000

compute_sync_offset = ->
	#here is the rather complicated code to calculate
	#then offsets of the time synchronization stuff
	#it's totally not necessary to do this, but whatever
	#it might make the stuff work better when on an
	#apple iOS device where screen drags pause the
	#recieving of sockets/xhrs meaning that the sync
	#might be artificially inflated, so this could
	#counteract that. since it's all numerical math
	#hopefully it'll be fast even if sync_offsets becomes
	#really really huge

	
	sync_offsets = sync_offsets.slice(-20)

	thresh = avg sync_offsets
	below = (item for item in sync_offsets when item <= thresh)
	sync_offset = avg(below)
	# console.log 'frst iter', below
	thresh = avg below
	below = (item for item in sync_offsets when item <= thresh)
	sync_offset = avg(below)

	# console.log 'sec iter', below
	$('#sync_offset').text(sync_offset.toFixed(1) + '/' + stdev(below).toFixed(1) + '/' + stdev(sync_offsets).toFixed(1))



last_question = null

sock.on 'chat', (data) ->
	chatAnnotation data

###
	Correct: 10pts
	Early: 15pts
	Interrupts: -5pts
###

computeScore = (user) ->
	return 0 if !user

	CORRECT = 10
	EARLY = 15
	INTERRUPT = -5

	return user.early * EARLY + (user.correct - user.early) * CORRECT + user.interrupts * INTERRUPT

getTimeSpan = do ->
	# https://github.com/skovalyov/coffee-script-utils/tree/master/date
	SECOND_IN_MILLISECONDS = 1000
	FEW_SECONDS = 5
	MINUTE_IN_SECONDS = 60
	HOUR_IN_SECONDS = MINUTE_IN_SECONDS * 60
	MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

	formatTime = (date) ->
		minutes = date.getMinutes()
		hours = date.getHours()
		ampm = if hours > 12 then "pm" else "am"
		formattedHours = if hours == 0 or hours == 12 then "12" else "#{hours % 12}";
		formattedMinutes = if minutes < 10 then "0#{minutes}" else "#{minutes}"
		formattedTime = "#{formattedHours}:#{formattedMinutes}#{ampm}"
		return formattedTime

	formatMonth = (date) -> MONTH_NAMES[date.getMonth()]

	formatWeekday = (date) -> WEEKDAY_NAMES[date.getDay()]

	getTimeSpan = (date) ->
		now = new Date()
		range = (now.getTime() - date.getTime()) / SECOND_IN_MILLISECONDS
		nextYearStart = new Date now.getFullYear() + 1, 0, 1
		nextWeekStart = new Date now.getFullYear(), now.getMonth(), now.getDate() + (7 - now.getDay())
		tomorrowStart = new Date now.getFullYear(), now.getMonth(), now.getDate() + 1
		theDayAfterTomorrowStart = new Date now.getFullYear(), now.getMonth(), now.getDate() + 2
		todayStart = new Date now.getFullYear(), now.getMonth(), now.getDate()
		yesterdayStart = new Date now.getFullYear(), now.getMonth(), now.getDate() - 1
		thisWeekStart = new Date now.getFullYear(), now.getMonth(), now.getDate() - now.getDay()
		thisYearStart = new Date now.getFullYear(), 0, 1
		nextYearRange = (now.getTime() - nextYearStart.getTime()) / SECOND_IN_MILLISECONDS
		nextWeekRange = (now.getTime() - nextWeekStart.getTime()) / SECOND_IN_MILLISECONDS
		theDayAfterTomorrowRange = (now.getTime() - theDayAfterTomorrowStart.getTime()) / SECOND_IN_MILLISECONDS
		tomorrowRange = (now.getTime() - tomorrowStart.getTime()) / SECOND_IN_MILLISECONDS
		todayRange = (now.getTime() - todayStart.getTime()) / SECOND_IN_MILLISECONDS
		yesterdayRange = (now.getTime() - yesterdayStart.getTime()) / SECOND_IN_MILLISECONDS
		thisWeekRange = (now.getTime() - thisWeekStart.getTime()) / SECOND_IN_MILLISECONDS
		thisYearRange = (now.getTime() - thisYearStart.getTime()) / SECOND_IN_MILLISECONDS
		if range >= 0
			if range < FEW_SECONDS
				result = "A few seconds ago"
			else if range < MINUTE_IN_SECONDS
				result = "#{Math.floor(range)} seconds ago"
			else if range < MINUTE_IN_SECONDS * 2
				result = "About a minute ago"
			else if range < HOUR_IN_SECONDS
				result = "#{Math.floor(range / MINUTE_IN_SECONDS)} minutes ago"
			else if range < HOUR_IN_SECONDS * 2
				result = "About an hour ago"
			else if range < todayRange
				result = "#{Math.floor(range / HOUR_IN_SECONDS)} hours ago"
			else if range < yesterdayRange
				result = "Yesterday at #{formatTime(date)}"
			else if range < thisWeekRange
				result = "#{formatWeekday(date)} at #{formatTime(date)}"
			else if range < thisYearRange
				result = "#{formatMonth(date)} #{date.getDate()} at #{formatTime(date)}"
			else
				result = "#{formatMonth(date)} #{date.getDate()}, #{date.getFullYear()} at #{formatTime(date)}"
		else
			if range > -FEW_SECONDS
				result = "In a few seconds"
			else if range > -MINUTE_IN_SECONDS
				result = "In #{Math.floor(-range)} seconds"
			else if range > -MINUTE_IN_SECONDS * 2
				result = "In about a minute"
			else if range > -HOUR_IN_SECONDS
				result = "In #{Math.floor(-range / MINUTE_IN_SECONDS)} minutes"
			else if range > -HOUR_IN_SECONDS * 2
				result = "In about an hour"
			else if range > tomorrowRange
				result = "In #{Math.floor(-range / HOUR_IN_SECONDS)} hours"
			else if range > theDayAfterTomorrowRange
				result = "Tomorrow at #{formatTime(date)}"
			else if range > nextWeekRange
				result = "#{formatWeekday(date)} at #{formatTime(date)}"
			else if range > nextYearRange
				result = "#{formatMonth(date)} #{date.getDate()} at #{formatTime(date)}"
			else
				result = "#{formatMonth(date)} #{date.getDate()}, #{date.getFullYear()} at #{formatTime(date)}"
		return result
	return getTimeSpan

formatRelativeTime = (timestamp) ->
	date = new Date
	date.setTime timestamp
	# console.log 'formatting time', date, timestamp
	return getTimeSpan(date)
	# (date.getHours() % 12)+':'+
	# ('0'+date.getMinutes()).substr(-2,2)+
	# #':'+ ('0'+date.getSeconds()).substr(-2,2) +
	# (if date.getHours() > 12 then "pm" else "am")

formatTime = (timestamp) ->
	date = new Date
	date.setTime timestamp
	(date.getHours() % 12)+':'+
	('0'+date.getMinutes()).substr(-2,2)+
	#':'+ ('0'+date.getSeconds()).substr(-2,2) +
	(if date.getHours() > 12 then "pm" else "am")


createStatSheet = (user, full) ->
	table = $('<table>').addClass('table headless')
	body = $('<tbody>').appendTo(table)
	row = (name, val) ->
		$('<tr>')
			.appendTo(body)
			.append($("<th>").text(name))
			.append($("<td>").addClass("value").append(val))
	
	row	"Score", $('<span>').addClass('badge').text(computeScore(user))
	row	"Correct", user.correct
	row "Interrupts", user.interrupts
	row "Early", user.early  if full
	row "Incorrect", user.guesses - user.correct  if full
	row "Guesses", user.guesses 
	row "Seen", user.seen
	row "Team", user.team if user.team
	row "ID", user.id.slice(0, 10) if full
	row "Last Seen", formatRelativeTime(user.last_action) if full
	return table


renderState = ->
	# render the user list and that stuff
	return unless sync.users
	#console.time('render state')
	teams = {}
	team_hash = ''
	for user in sync.users
		# votes = []
		# for action of sync.voting
		# 	if user.id in sync.voting[action]
		# 		votes.push action
		# user.votes = votes.join(', ')
		# user.room = sync.name
		# users[user.id] = user
		if user.team
			teams[user.team] = [] unless user.team of teams
			teams[user.team].push user.id
			team_hash += user.team + user.id
		
		#teams[user.team || user.id] = [] unless teams[user.team || ''] 
		#teams[user.team || user.id].push user.id

		userSpan(user.id, true) # do a global update!


		# user.name + " (" + user.id + ") " + votes.join(", ")
	
	if $('.teams').data('teamhash') isnt team_hash
		$('.teams').data('teamhash', team_hash)
		$('.teams').empty()
		$('.teams')[0].options.add new Option('Individual', '')
		for team, members of teams
			$('.teams')[0].options.add new Option("#{team} (#{members.length})", team)
		$('.teams')[0].options.add new Option('Create Team', 'create')
		if public_id of users
			$('.teams').val(users[public_id].team)
	
	#console.time('draw board')
	list = $('.leaderboard tbody')
	# list.find('tr').remove() #abort all people
	ranking = 1
	
	entities = sync.users
	team_count = 0
	if $('.teams').val() or public_id.slice(0,2) == "__"
		entities = for team, members of teams
			attrs = {}
			team_count++
			for member in members
				for attr, val of users[member]
					if typeof val is 'number'
						attrs[attr] = 0 unless attr of attrs
						attrs[attr] += val

			attrs.id = 't-' + team.toLowerCase().replace(/[^a-z0-9]/g, '')
			attrs.members = members
			
			attrs.name = team
			attrs
			
		for user in sync.users when !user.team 
			entities.push user # add all the unaffiliated users

	list.empty()
	for user, user_index in entities.sort((a, b) -> computeScore(b) - computeScore(a))
		# if the score is worse, increment ranks
		ranking++ if entities[user_index - 1] and computeScore(user) < computeScore(entities[user_index - 1])
		row = $('<tr>').data('entity', user).appendTo list
		row.click -> 1
		badge = $('<span>').addClass('badge pull-right').text(computeScore(user))
		if public_id in (user.members || [user.id])
			badge.addClass('badge-info').attr('title', 'You')
		else
			idle_count = 0
			active_count = 0
			for member in (user.members || [user.id])
				if users[member].online
					if serverTime() - users[member].last_action > 1000 * 60 * 10
						idle_count++
					else
						active_count++
			if active_count > 0
				badge.addClass('badge-success').attr('title', 'Online')
			else if idle_count > 0
				badge.addClass('badge-warning').attr('title', 'Idle')
		
		$('<td>').addClass('rank').append(badge).append(ranking).appendTo row
		name = $('<td>').appendTo row
		
		$('<td>').text(user.interrupts).appendTo row
		if !user.members #user.members.length is 1 and !users[user.members[0]].team # that's not a team! that's a person!
			name.append($('<span>').text(user.name)) #.css('font-weight', 'bold'))
		else
			name.append($('<span>').text(user.name).css('font-weight', 'bold')).append(" (#{user.members.length})")
		
			for member in user.members.sort((a, b) -> computeScore(users[b]) - computeScore(users[a]))
				user = users[member]
				row = $('<tr>').addClass('subordinate').data('entity', user).appendTo list
				row.click -> 1
				badge = $('<span>').addClass('badge pull-right').text(computeScore(user))
				if user.id is public_id
					badge.addClass('badge-info').attr('title', 'You')
				else
					if user.online
						if serverTime() - user.last_action > 1000 * 60 * 10
							badge.addClass('badge-warning').attr('title', 'Idle')
						else
							badge.addClass('badge-success').attr('title', 'Online')

				$('<td>').css("border", 0).append(badge).appendTo row
				name = $('<td>').text(user.name)
				name.appendTo row
				$('<td>').text(user.interrupts).appendTo row

	#console.timeEnd('draw board')
	# this if clause is ~5msecs
	if sync.users.length > 1 and connected() or (sync.users.length is 1 and sync.users[0].id isnt public_id and connected())
		if $('.leaderboard').is(':hidden')
			$('.leaderboard').slideDown()
			$('.singleuser').slideUp()
	else if users[public_id]
		$('.singleuser .stats table').replaceWith(createStatSheet(users[public_id], !!$('.singleuser').data('full')))
		if $('.singleuser').is(':hidden')
			$('.leaderboard').slideUp()
			$('.singleuser').slideDown()
	# turns out doing this resize is like the slowest part!
	# console.time('resize')
	# $(window).resize() #fix all the expandos
	# console.timeEnd('resize')
	checkAlone() # ~ 1 msec
	
	#console.time('partial')
	renderPartial()
	#console.timeEnd('partial')
	#console.timeEnd('render state')


checkAlone = ->
	return unless connected()
	active_count = 0
	for user in sync.users
		if user.online and serverTime() - user.last_action < 1000 * 60 * 10
			active_count++
	if active_count is 1
		sock.emit 'check_rooms', public_rooms, (data) ->
			suggested_candidates = []
			for room, count of data
				if count > 0 and room isnt sync.name
					suggested_candidates.push room
			if suggested_candidates.length > 0
				links = (can.link("/" + can) + " (#{data[can]}) " for can in suggested_candidates)
				$('.foreveralone .roomlist').html links.join(' or ')
				$('.foreveralone').slideDown()
			else
				$('.foreveralone').slideUp()
	else
		$('.foreveralone').slideUp()

$('.singleuser').click ->
	$('.singleuser .stats').slideUp().queue ->
		$('.singleuser').data 'full', !$('.singleuser').data('full')
		renderState()

		$(this).dequeue().slideDown()

lastRendering = 0
renderPartial = ->
	if !sync.time_freeze or sync.attempt
		if time() < sync.end_time
			requestAnimationFrame(renderPartial)
			# setTimeout renderPartial, 1000 / 30
			if new Date - lastRendering < 1000 / 20
				return

	lastRendering = +new Date
	return unless sync.question and sync.timing


	#render the question 
	if sync.question isnt last_question
		changeQuestion() #whee slidey
		last_question = sync.question

	if !sync.time_freeze
		removeSplash()

	updateTextPosition()

	#render the time
	renderTimer()
	



updateTextAnnotations = ->
	return unless sync.question and sync.timing

	words = sync.question.split ' '
	early_index = sync.question.replace(/[^ \*]/g, '').indexOf('*')
	bundle = $('#history .bundle.active') 

	spots = bundle.data('starts') || []

	readout = bundle.find('.readout .well')
	readout.data('spots', spots.join(','))

	children = readout.children()
	# children.slice(words.length).remove()

	elements = []
	
	for i in [0...words.length]
		element = $('<span>').addClass('unread')

		if words[i].indexOf('*') isnt -1
			element.append " <span class='inline-icon'><span class='asterisk'>"+words[i]+"</span><i class='label icon-white icon-asterisk'></i></span> "
		else
			element.append(words[i] + " ")

		if i in spots
			# element.append('<span class="label label-important">'+words[i]+'</span> ')
			label_type = 'label-important'
			# console.log spots, i, words.length
			if i is words.length - 1
				label_type = "label-info"
			if early_index != -1 and i < early_index
				label_type = "label"

			element.append " <span class='inline-icon'><i class='label icon-white icon-bell  #{label_type}'></i></span> "

		elements.push element

	for i in [0...words.length]
		unless children.eq(i).html() is elements[i].html()
			if children.eq(i).length > 0
				children.eq(i).replaceWith(elements[i])
			else
				readout.append elements[i]


				
updateTextPosition = ->
	return unless sync.question and sync.timing

	timeDelta = time() - sync.begin_time
	words = sync.question.split ' '
	cumulative = cumsum sync.timing, sync.rate
	index = 0
	index++ while timeDelta > cumulative[index]
	# console.log index
	bundle = $('#history .bundle.active') 
	readout = bundle.find('.readout .well')
	children = readout.children()
	if children.length != words.length
		updateTextAnnotations()

	children.slice(0, index).removeClass('unread')
	# children.slice(index).addClass('unread')


window.requestAnimationFrame ||=
  window.webkitRequestAnimationFrame ||
  window.mozRequestAnimationFrame    ||
  window.oRequestAnimationFrame      ||
  window.msRequestAnimationFrame     ||
  (callback, element) ->
    window.setTimeout( ->
      callback(+new Date())
    , 1000 / 60)

# setInterval ->
# 	renderState()
# , 15000

# setInterval renderPartial, 50



renderTimer = ->
	# $('#pause').show !!sync.time_freeze
	# $('.buzzbtn').attr 'disabled', !!sync.attempt
	if connected()
		$('.offline').fadeOut()
	else
		$('.offline').fadeIn()

	if sync.time_freeze
		$('.buzzbtn').disable true

		if sync.attempt
			do ->
				cumulative = cumsum sync.timing, sync.rate
				del = sync.attempt.start - sync.begin_time
				i = 0
				i++ while del > cumulative[i]
				starts = ($('.bundle.active').data('starts') || [])
				starts.push(i - 1) if (i - 1) not in starts
				$('.bundle.active').data('starts', starts)

			$('.label.pause').hide()
			$('.label.buzz').fadeIn()

		else
			$('.label.pause').fadeIn()
			$('.label.buzz').hide()
			

		# show the resume button
		if $('.pausebtn').hasClass('btn-warning')

			$('.pausebtn .resume').show()
			$('.pausebtn .pause').hide()

			$('.pausebtn')
			.addClass('btn-success')
			.removeClass('btn-warning')

	else
		# show the pause button
		$('.label.pause').fadeOut()
		$('.label.buzz').fadeOut()
		if $('.pausebtn').hasClass('btn-success')
			$('.pausebtn .resume').hide()
			$('.pausebtn .pause').show()
			$('.pausebtn')
			.addClass('btn-warning')
			.removeClass('btn-success')

	if time() > sync.end_time - sync.answer_duration
		if $(".nextbtn").is(":hidden")
			$('.nextbtn').show() 
			$('.skipbtn').hide() 
	else
		if $(".skipbtn").is(":hidden")
			$('.nextbtn').hide()
			$('.skipbtn').show()

	$('.timer').toggleClass 'buzz', !!sync.attempt


	$('.progress').toggleClass 'progress-warning', !!(sync.time_freeze and !sync.attempt)
	$('.progress').toggleClass 'active progress-danger', !!sync.attempt

	
	if sync.attempt
		elapsed = serverTime() - sync.attempt.realTime
		ms = sync.attempt.duration - elapsed
		progress = elapsed / sync.attempt.duration
		$('.pausebtn, .buzzbtn, .skipbtn, .nextbtn').disable true
	else
		ms = sync.end_time - time()
		elapsed = (time() - sync.begin_time)
		progress = elapsed/(sync.end_time - sync.begin_time)
		$('.skipbtn, .nextbtn').disable false
		$('.pausebtn').disable (ms < 0)
		unless sync.time_freeze
			$('.buzzbtn').disable (ms < 0 or elapsed < 100)
		if ms < 0
			$('.bundle.active').find('.answer')
				.css('display', 'inline')
				.css('visibility', 'visible')
			ruling = $('.bundle.active').find('.ruling')
			unless ruling.data('shown_tooltip')
				ruling.data('shown_tooltip', true)
				$('.bundle.active').find('.ruling').first()
					.tooltip({
						trigger: "manual"
					})
					.tooltip('show')
	
	if $('.progress .bar').hasClass 'pull-right'
		$('.progress .bar').width (1 - progress) * 100 + '%'
	else
		$('.progress .bar').width progress * 100 + '%'

	ms = Math.max(0, ms) # force time into positive range, comment this out to show negones
	sign = ""
	sign = "+" if ms < 0
	sec = Math.abs(ms) / 1000


	cs = (sec % 1).toFixed(1).slice(1)
	$('.timer .fraction').text cs
	min = sec / 60
	pad = (num) ->
		str = Math.floor(num).toString()
		while str.length < 2
			str = '0' + str
		str
	$('.timer .face').text sign + pad(min) + ':' + pad(sec % 60)


removeSplash = (fn) ->
	start = $('.bundle .start-page')
	bundle = start.parent(".bundle")
	if start.length > 0
		bundle.find('.readout')
			.width(start.width())
			.slideDown 'normal', ->
				$(this).width('auto')

		start.slideUp 'normal', ->
			start.remove()
			fn() if fn
	else
		fn() if fn

changeQuestion = ->
	cutoff = 15
	#smaller cutoff for phones which dont place things in parallel
	cutoff = 1 if mobileLayout()
	$('.bundle .ruling').tooltip('destroy')

	#remove the old crap when it's really old (and turdy)
	$('.bundle:not(.bookmarked)').slice(cutoff).slideUp 'normal', -> 
			$(this).remove()
	old = $('#history .bundle').first()
	# old.find('.answer').css('visibility', 'visible')
	old.removeClass 'active'
	old.find('.breadcrumb').click -> 1 # register a empty event handler so touch devices recognize
	#merge the text nodes, perhaps for performance reasons
	bundle = createBundle().width($('#history').width()) #.css('display', 'none')
	bundle.addClass 'active'


	$('#history').prepend bundle.hide()
	updateTextPosition()

	if !last_question and sync.time_freeze and sync.time_freeze - sync.begin_time < 500
		# console.log 'loading splash page'
		start = $('<div>').addClass('start-page')
		well = $('<div>').addClass('well').appendTo(start)
		$('<button>')
			.addClass('btn btn-success btn-large')
			.text('Start the Question')
			.appendTo(well)
			.click ->
				removeSplash ->
					$('.pausebtn').click()

		
		bundle.find('.readout').hide().before start

	bundle.slideDown("normal").queue ->
		bundle.width('auto')
		$(this).dequeue()
	if old.find('.readout').length > 0
		nested = old.find('.readout .well>span')
		old.find('.readout .well').append nested.contents()
		nested.remove()

		old.find('.readout')[0].normalize()

		old.queue ->
			old.find('.readout').slideUp("normal")
			$(this).dequeue()

createAlert = (bundle, title, message) ->
	div = $("<div>").addClass("alert alert-success")
		.insertAfter(bundle.find(".annotations")).hide()
	div.append $("<button>")
		.attr("data-dismiss", "alert")
		.attr("type", "button")
		.html("&times;")
		.addClass("close")
	div.append $("<strong>").text(title)
	div.append " "
	div.append message
	div.slideDown()
	setTimeout ->
		div.slideUp().queue ->
			$(this).dequeue()
			$(this).remove()
	, 5000
	

createBundle = ->
	bundle = $('<div>').addClass('bundle').attr('name', sync.qid).addClass('room-'+sync.name?.replace(/[^a-z0-9]/g, ''))
	important = $('<div>').addClass 'important'
	bundle.append(important)
	breadcrumb = $('<ul>')

	star = $('<a>', {
		href: "#",
		rel: "tooltip",
		title: "Bookmark this question"
	})
		.addClass('icon-star-empty bookmark')
		.click (e) ->
			# whoever is reading this:
			# if you decide to add a server-side notion of saved questions
			# here is wher eyou shove it
			bundle.toggleClass 'bookmarked'
			star.toggleClass 'icon-star-empty', !bundle.hasClass 'bookmarked'
			star.toggleClass 'icon-star', bundle.hasClass 'bookmarked'
			e.stopPropagation()
			e.preventDefault()

	breadcrumb.append $('<li>').addClass('pull-right').append(star)

	addInfo = (name, value) ->
		breadcrumb.find('li:not(.pull-right)').last().append $('<span>').addClass('divider').text('/')
		if value
			name += ": " + value
		el = $('<li>').text(name).appendTo(breadcrumb)
		if value
			el.addClass('hidden-phone')
		else
			el.addClass('visible-phone')

	if (public_id + '').slice(0, 2) is "__"
		addInfo 'Room', sync.name
	
	addInfo 'Category', sync.info.category
	addInfo 'Difficulty', sync.info.difficulty
	addInfo 'Tournament', sync.info.year + ' ' + sync.info.tournament

	addInfo sync.info.year + ' ' + sync.info.difficulty + ' ' + sync.info.category
	# addInfo 'Year', sync.info.year
	# addInfo 'Number', sync.info.num
	# addInfo 'Round', sync.info.round
	# addInfo 'Report', ''

	breadcrumb.find('li').last().append $('<span>').addClass('divider hidden-phone').text('/')
	bundle.data 'report_info', {
		year: sync.info.year, 
		difficulty: sync.info.difficulty, 
		category: sync.info.category, 
		tournament: sync.info.tournament,
		round: sync.info.round,
		num: sync.info.num,
		qid: sync.qid,
		question: sync.question,
		answer: sync.answer
	}
	breadcrumb.append $('<li>').addClass('clickable hidden-phone').text('Report').click (e) ->
		# console.log 'report question'
		# $('#report-question').modal('show')
		info = bundle.data 'report_info'

		div = $("<div>").addClass("alert alert-block alert-info")
			.insertBefore(bundle.find(".annotations")).hide()
		div.append $("<button>")
			.attr("data-dismiss", "alert")
			.attr("type", "button")
			.html("&times;")
			.addClass("close")
		div.append $("<h4>").text "Report Question"
		form = $("<form>")
		form.addClass('form-horizontal').appendTo div
		rtype = $('<div>').addClass('control-group').appendTo(form)
		rtype.append $("<label>").addClass('control-label').text('Description')
		controls = $("<div>").addClass('controls').appendTo rtype
		for option in ["Wrong category", "Wrong details", "Bad question", "Broken formatting"]
			controls.append $("<label>")
				.addClass("radio")
				.append($("<input type=radio name=description>").val(option.split(" ")[1].toLowerCase()))
				.append(option)

		form.find(":radio").change ->
			if form.find(":radio:checked").val() is 'category'
				ctype.slideDown()
			else
				ctype.slideUp()
		
		ctype = $('<div>').addClass('control-group').appendTo(form)
		ctype.append $("<label>").addClass('control-label').text('Category')
		cat_list = $('<select>')
		ctype.append $("<div>").addClass('controls').append cat_list
		
		controls.find('input:radio')[0].checked = true

		cat_list.append new Option(cat) for cat in sync.categories
		cat_list.val(info.category)
		stype = $('<div>').addClass('control-group').appendTo(form)

		$("<div>").addClass('controls').appendTo(stype)
			.append($('<button type=submit>').addClass('btn btn-primary').text('Submit'))

		$(form).submit ->
			describe = form.find(":radio:checked").val()
			if describe is 'category'
				info.fixed_category = cat_list.val()
			info.describe = describe
			sock.emit 'report_question', info
			
			createAlert bundle, 'Reported Question', 'You have successfully reported a question. It will be reviewed and the database may be updated to fix the problem. Thanks.'
			div.slideUp()
			return false
		div.slideDown()

		# createAlert bundle, 'Reported Question', 'You have successfully reported a question. It will be reviewed and the database may be updated to fix the problem. Thanks.'
		# sock.emit 'report_question', bundle.data 'report_info'

		e.stopPropagation()
		e.preventDefault()


	breadcrumb.append $('<li>').addClass('pull-right answer').text(sync.answer)

	readout = $('<div>').addClass('readout')
	well = $('<div>').addClass('well').appendTo(readout)
	# well.append $('<span>').addClass('visible')
	# well.append document.createTextNode(' ') #space: the frontier in between visible and unread
	well.append $('<span>').addClass('unread').text(sync.question)
	annotations = $('<div>').addClass 'annotations'
	bundle
		.append($('<ul>').addClass('breadcrumb').append(breadcrumb))
		.append(readout)
		.append(annotations)


userSpan = (user, global) ->
	prefix = ''

	if public_id and public_id.slice(0, 2) == "__"
		prefix = (users[user]?.room || 'unknown') + '/'
	text = ''

	if user.slice(0, 2) == "__"
		text = prefix + user.slice(2)
	else
		text = prefix + (users[user]?.name || "[name missing]")
	
	hash = 'userhash-' + escape(text).toLowerCase().replace(/[^a-z0-9]/g, '')
	
	if global
		scope = $(".user-#{user}:not(.#{hash})")
		# get rid of the old hashes
		for el in scope
			for c in $(el).attr('class').split('\s') when c.slice(0, 8) is 'userhash'
				$(el).removeClass(c)
			
	else
		scope = $('<span>')
	scope
		.addClass(hash)
		.addClass('user-'+user)
		.addClass('username')
		.text(text)

addAnnotation = (el, name = sync.name) ->
	# destroy the tooltip
	$('.bundle .ruling').tooltip('destroy')
	current_bundle = $('.room-' + (name || '').replace(/[^a-z0-9]/g, ''))
	if current_bundle.length is 0
		current_bundle = $('#history .bundle.active')
	el.css('display', 'none').prependTo current_bundle.eq(0).find('.annotations')
	el.slideDown()
	return el

addImportant = (el) ->
	$('.bundle .ruling').tooltip('destroy')
	el.css('display', 'none').prependTo $('#history .bundle.active .important')
	el.slideDown()
	return el

guessAnnotation = ({session, text, user, done, correct, interrupt, early, prompt}) ->
	# TODO: make this less like chats
	# console.log("guess annotat", text, done)
	# id = user + '-' + session
	id = "#{user}-#{session}-#{if prompt then 'prompt' else 'guess'}"
	# console.log id
	# console.log id
	if $('#' + id).length > 0
		line = $('#' + id)
	else
		line = $('<p>').attr('id', id)
		if prompt
			prompt_el = $('<a>').addClass('label prompt label-info').text('Prompt')
			line.append ' '
			line.append prompt_el
		else
			marker = $('<span>').addClass('label').text("Buzz")
			if early
				# do nothing, use default
			else if interrupt
				marker.addClass 'label-important'
			else
				marker.addClass 'label-info'
			line.append marker
		

		line.append " "
		line.append userSpan(user).addClass('author')
		line.append document.createTextNode ' '
		$('<span>')
			.addClass('comment')
			.appendTo line

		ruling = $('<a>')
			.addClass('label ruling')
			.hide()
			.attr('href', '#')
			.attr('title', 'Click to Report')
			.data('placement', 'right')
		line.append ' '
		line.append ruling
		# addAnnotation line
		line.css('display', 'none').prependTo $('#history .bundle[name="' + sync.qid + '"]').eq(0).find('.annotations')
		line.slideDown()
	if done
		if text is ''
			line.find('.comment').html('<em>(blank)</em>')
		else
			line.find('.comment').text(text)
	else
		line.find('.comment').text(text)


	if done
		ruling = line.find('.ruling').show().css('display', 'inline')
		# setTimeout ->
		# 	ruling.tooltip('show')
		# , 100
		# setTimeout ->
		# 	ruling.tooltip('hide')
		# , 1000
		decision = ""
		if correct is "prompt"
			ruling.addClass('label-info').text('Prompt')
			decision = "prompt"
		else if correct
			decision = "correct"
			ruling.addClass('label-success').text('Correct')
			if user is public_id # if the person who got it right was me
				old_score = computeScore(users[public_id])
				checkScoreUpdate = ->
					updated_score = computeScore(users[public_id])
					if updated_score is old_score
						setTimeout checkScoreUpdate, 100
						return

					magic_multiple = 1000
					magic_number = Math.round(old_score / magic_multiple) * magic_multiple
					# console.log updated_score, old_score
					return if magic_number is 0 # 0 is hardly an accomplishment
					if magic_number > 0
						if old_score < magic_number and updated_score >= magic_number
							$('body').fireworks(magic_number / magic_multiple * 10)
							createAlert ruling.parents('.bundle'), 'Congratulations', "You have over #{magic_number} points! Here's some fireworks."
				checkScoreUpdate()
		else
			decision = "wrong"
			ruling.addClass('label-warning').text('Wrong')
			if user is public_id and public_id of users
				old_score = computeScore(users[public_id])
				if old_score < -100 # just a little way of saying "you suck"
					createAlert ruling.parents('.bundle'), 'you suck', 'like seriously you really really suck. you are a turd.'


		answer = sync.answer
		ruling.click ->
			sock.emit 'report_answer', {guess: text, answer: answer, ruling: decision}
			createAlert ruling.parents('.bundle'), 'Reported Answer', "You have successfully told me that my algorithm sucks. Thanks, I'll fix it eventually. "
			# I've been informed that this green box might make you feel bad and that I should change the wording so that it doesn't induce a throbbing pang of guilt in your gut. But the truth is that I really do appreciate flagging this stuff, it helps improve this product and with moar data, I can do science with it.

			# $('#review .review-judgement')
			# 	.after(ruling.clone().addClass('review-judgement'))
			# 	.remove()
				
			# $('#review .review-answer').text answer
			# $('#review .review-response').text text
			# $('#review').modal('show')
			return false

		if actionMode is 'guess'
			setActionMode ''
	# line.toggleClass 'typing', !done
	return line

chatAnnotation = ({session, text, user, done, time}) ->
	id = user + '-' + session
	if $('#' + id).length > 0
		line = $('#' + id)
	else
		line = $('<p>').attr('id', id)
		line.append userSpan(user).addClass('author').attr('title', formatTime(time))
		line.append document.createTextNode ' '
		$('<span>')
			.addClass('comment')
			.appendTo line
		addAnnotation line, users[user]?.room

	url_regex = /\b((?:https?:\/\/|www\d{0,3}[.]|[a-z0-9.\-]+[.][a-z]{2,4}\/)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\))+(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s`!()\[\]{};:'".,<>?«»“”‘’]))/ig
	html = text.replace(/</g, '&lt;').replace(/>/g, '&gt;')
	.replace(/(^|\s+)(\/[a-z0-9\-]+)(\s+|$)/g, (all, pre, room, post) ->
		# console.log all, pre, room, post
		return pre + "<a href='#{room}'>#{room}</a>" + post
	).replace(url_regex, (url) ->
		real_url = url
		real_url = "http://#{url}" unless /:\//.test(url)
		if /\.(jpe?g|gif|png)$/.test(url)
			return "<img src='#{real_url}' alt='#{url}'>"
		else
			return "<a href='#{real_url}' target='_blank'>#{url}</a>"
	)
	# console.log html
	if done
		line.removeClass('buffer')
		if text is ''
			line.find('.comment').html('<em>(no message)</em>')
		else
			line.find('.comment').html html
	else
		if !$('.livechat')[0].checked or text is '(typing)'
			line.addClass('buffer')
			line.find('.comment').text(' is typing...')
		else
			line.removeClass('buffer')
			# line.find('.comment').text(text)

			line.find('.comment').html html

	line.toggleClass 'typing', !done


sock.on 'log', ({user, verb}) ->
	line = $('<p>').addClass 'log'
	if user
		line.append userSpan(user)
		line.append " " + verb
	else
		line.append verb
	addAnnotation line



jQuery('.bundle .breadcrumb').live 'click', ->
	unless $(this).is jQuery('.bundle .breadcrumb').first()
		readout = $(this).parent().find('.readout')
		readout.width($('#history').width()).slideToggle "normal", ->
			readout.width 'auto'

actionMode = ''
setActionMode = (mode) ->
	actionMode = mode
	$('.prompt_input, .guess_input, .chat_input').blur()
	$('.actionbar' ).toggle mode is ''
	$('.chat_form').toggle mode is 'chat'
	$('.guess_form').toggle mode is 'guess'
	$('.prompt_form').toggle mode is 'prompt'

	$(window).resize() #reset expandos

$('.chatbtn').click ->
	setActionMode 'chat'
	# create a new input session id, which helps syncing work better
	$('.chat_input')
		.data('input_session', Math.random().toString(36).slice(3))
		.data('begin_time', +new Date)
		.val('')
		.focus()
		.keyup()

recent_actions = [0]
rate_limit_ceiling = 0
rate_limit_check = ->
	online_count = (user for user in sync.users when user.online and user.last_action > new Date - 1000 * 60 * 10).length
	rate_threshold = 7
	if online_count > 1
		rate_threshold = 3
	current_time = +new Date
	filtered_actions = []
	rate_limited = false
	for action in recent_actions when current_time - action < 5000
		# only look at past 5 seconds
		filtered_actions.push action
	# console.log filtered_actions.length, rate_threshold
	if filtered_actions.length >= rate_threshold
		rate_limited = true
	if rate_limit_ceiling > current_time
		rate_limited = true
	recent_actions = filtered_actions.slice(-10)
	recent_actions.push current_time
	if rate_limited
		rate_limit_ceiling = current_time + 5000
		createAlert $('.bundle.active'), 'Rate Limited', "You been rate limited for doing too many things in the past five seconds. "
	return rate_limited

# last_skip = 0
skip = ->
	removeSplash()
	return if rate_limit_check()
	sock.emit 'skip', 'yay'

next = ->
	removeSplash()
	sock.emit 'next', 'yay'

$('.skipbtn').click skip

$('.nextbtn').click next

try
	ding_sound = new Audio('img/ding.wav')
catch e
	# do nothing

$('.buzzbtn').click ->
	return if $('.buzzbtn').attr('disabled') is 'disabled'
	return if rate_limit_check()
	setActionMode 'guess'
	$('.guess_input')
		.val('')
		.addClass('disabled')
		.focus()
	# so it seems that on mobile devices with on screen virtual keyboards
	# if your focus isn't event initiated (eg. based on the callback of
	# some server query to confirm control of the textbox) it wont actualy
	# bring up the keyboard, so the solution here is to first open it up
	# and ask nicely for forgiveness otherwise
	submit_time = +new Date
	sock.emit 'buzz', 'yay', (status) ->
		if status is 'http://www.whosawesome.com/'
			$('.guess_input').removeClass('disabled')
			if $('.sounds')[0].checked
				
				
				ding_sound.play() if ding_sound
			_gaq.push ['_trackEvent', 'Game', 'Response Latency', 'Buzz Accepted', new Date - submit_time] if window._gaq
		else
			setActionMode ''
			_gaq.push ['_trackEvent', 'Game', 'Response Latency', 'Buzz Rejected', new Date - submit_time] if window._gaq

$('.score-reset').click ->
	sock.emit 'resetscore', 'yay'

$('.pausebtn').click ->
	removeSplash ->
		if !!sync.time_freeze
			sock.emit 'unpause', 'yay'
		else
			sock.emit 'pause', 'yay'


$('.chat_input').keydown (e) ->
	if e.keyCode in [47, 111, 191] and $(this).val().length is 0 and !e.shiftKey
		e.preventDefault()
	if e.keyCode in [27] #escape key
		$('.chat_form').submit()


$('input').keydown (e) ->
	e.stopPropagation() #make it so that the event listener doesnt pick up on stuff
	if $(this).hasClass("disabled")
		e.preventDefault()



$('.chat_input').keyup (e) ->
	return if e.keyCode is 13
	if $('.livechat')[0].checked
		sock.emit 'chat', {
			text: $('.chat_input').val(), 
			session: $('.chat_input').data('input_session'), 
			done: false
		}
	else if $('.chat_input').data('sent_typing') isnt $('.chat_input').data('input_session')
		sock.emit 'chat', {
			text: '(typing)', 
			session: $('.chat_input').data('input_session'), 
			done: false
		}
		$('.chat_input').data 'sent_typing', $('.chat_input').data('input_session')


$('.chat_form').submit (e) ->
	sock.emit 'chat', {
		text: $('.chat_input').val(), 
		session: $('.chat_input').data('input_session'), 
		done: true
	}
	e.preventDefault()
	setActionMode ''
	time_delta = new Date - $('.chat_input').data('begin_time')
	_gaq.push ['_trackEvent', 'Chat', 'Typing Time', 'Posted Message', time_delta] if window._gaq

$('.guess_input').keyup (e) ->
	return if e.keyCode is 13
	sock.emit 'guess', {
		text: $('.guess_input').val(), 
		done: false
	}

	
$('.guess_form').submit (e) ->
	sock.emit 'guess', {
		text: $('.guess_input').val(), 
		done: true
	}
	e.preventDefault()
	setActionMode ''

$('.prompt_input').keyup (e) ->
	return if e.keyCode is 13
	sock.emit 'guess', {
		text: $('.prompt_input').val(), 
		done: false
	}

	
$('.prompt_form').submit (e) ->
	sock.emit 'guess', {
		text: $('.prompt_input').val(), 
		done: true
	}
	e.preventDefault()
	setActionMode ''


$('body').keydown (e) ->
	if actionMode is 'chat'
		return $('.chat_input').focus()

	if actionMode is 'guess'
		return $('.guess_input').focus()
	
	return if e.shiftKey or e.ctrlKey or e.metaKey

	if e.keyCode is 32
		e.preventDefault()
		if $('.bundle .start-page').length is 1
			$('.pausebtn').click()	
		else
			$('.buzzbtn').click()
	else if e.keyCode in [83] # S
		skip()
	else if e.keyCode in [78, 74] # N, J
		next()
	else if e.keyCode in [80, 82] # P, R
		$('.pausebtn').click()
	else if e.keyCode in [47, 111, 191, 67, 65] # / (forward slash), C, A
		e.preventDefault()
		$('.chatbtn').click()
	else if e.keyCode in [70] # F
		sock.emit 'finish', 'yay'
	else if e.keyCode in [66]
		$('.bundle.active .bookmark').click()

	# console.log e.keyCode


$('.speed').change ->
	$('.speed').not(this).val($(this).val())
	$('.speed').data("last_update", +new Date)
	rate = 1000 * 60 / 5 / Math.round($(this).val())
	sock.emit 'speed', rate
	# console.log rate
		
$('.categories').change ->
	if  $('.categories').val() is 'custom'
		createCategoryList()
		$('.custom-category').slideDown()
	else
		$('.custom-category').slideUp()
	sock.emit 'category', $('.categories').val()

$('.difficulties').change ->
	sock.emit 'difficulty', $('.difficulties').val()

$('.teams').change ->
	if $('.teams').val() is 'create'
		sock.emit 'team', prompt('Enter Team Name') || ''
	else
		sock.emit 'team', $('.teams').val()

$('.multibuzz').change ->
	sock.emit 'max_buzz', (if $('.multibuzz')[0].checked then null else 1)

$('.livechat').change ->
	sock.emit 'show_typing', $('.livechat')[0].checked

$('.sounds').change ->
	sock.emit 'sounds', $('.sounds')[0].checked


	

jQuery.fn.fireworks = (times = 5) ->
	for i in [0...times]
		duration = Math.random() * 2000
		@.delay(duration).queue =>
			{top, left} = @position()
			left += jQuery(window).width() * Math.random()
			top += jQuery(window).height() * Math.random()
			color = '#'+Math.random().toString(16).slice(2,8)
			@dequeue()
			for j in [0...50]
				ang = Math.random() * 6.294
				speed = Math.min(100, 150 * Math.random())
				
				vx = speed * Math.cos(ang)
				vy = speed * Math.sin(ang)

				seconds = 2 * Math.random()
				size = 5
				end_size = Math.random() * size
				jQuery('<div>')
				.css({
					"position": 'fixed',
					"background-color": color,
					'width': size,
					'height': size,
					'border-radius': size,
					'top': top,
					'left': left
				})
				.appendTo('body')
				.animate {
					left: "+=#{vx * seconds}",
					top: "+=#{vy * seconds}",
					width: end_size,
					height: end_size
				}, {
					duration: seconds * 1000,
					complete: ->
						$(this).remove()
				}

# possibly this should be replaced by something smarter using CSS calc()
# but that would be a 
$(window).resize ->
	$('.expando').each ->
		add = sum($(i).outerWidth() for i in $(this).find('.add-on, .padd-on'))
		# console.log add
		size = $(this).width()
		input = $(this).find('input, .input')
		if input.hasClass 'input'
			outer = 0
		else
			outer = input.outerWidth() - input.width()
		# console.log 'exp', input, add, outer, size
		# console.log(input[0], outer, add)
		if Modernizr.csscalc
			input.css('width', "-webkit-calc(100% - #{outer + add}px)")
			input.css('width', "-moz-calc(100% - #{outer + add}px)")
			input.css('width', "-o-calc(100% - #{outer + add}px)")
			input.css('width', "calc(100% - #{outer + add}px)")
			
		else
			input.width size - outer - add


$(window).resize()

#ugh, this is fugly, maybe i should have used calc
setTimeout ->
	$(window).resize()
, 762

setTimeout ->
	$(window).resize()
, 2718

setTimeout ->
	$(window).resize()
, 6022

#display a tooltip for keyboard shortcuts on keyboard machines
if !Modernizr.touch and !mobileLayout()
	$('.actionbar button').tooltip()
	# hide crap when clicked upon
	$('.actionbar button').click -> 
		$('.actionbar button').tooltip 'hide'

	$('#history, .settings').tooltip {
		selector: "[rel=tooltip]", 
		placement: -> 
			if mobileLayout() then "error" else "left"
	}

$('body').click (e) ->
	if $(e.target).parents('.leaderboard, .popover').length is 0
		$('.popover').remove()

$(".leaderboard tbody tr").live 'click', (e) ->
	# console.log this
	# tmp = $('.popover')
	# allow time delay so that things can be faded out before you kill them
	# setTimeout ->
	# 	tmp.remove()
	# , 1000
	user = $(this).data('entity')
	enabled = $(this).data('popover')?.enabled
	# console.log $('.leaderboard tbody tr').not(this).popover 'toggle'
	$('.leaderboard tbody tr').popover 'destroy'
	unless enabled
		$(this).popover {
			placement: if mobileLayout() then "top" else "left"
			trigger: "manual",
			title: "#{user.name}'s Stats",
			content: ->
				createStatSheet(user, true)
		}
		$(this).popover 'toggle'


if Modernizr.touch
	$('.show-keyboard').hide()
	$('.show-touch').show()
else
	$('.show-keyboard').show()
	$('.show-touch').hide()


handleCacheEvent = ->
	status = applicationCache.status
	switch applicationCache.status
		when applicationCache.UPDATEREADY
			$('#cachestatus').text 'Updated'
			console.log 'update is ready'
			applicationCache.swapCache()
			$('#update').slideDown()		
			
			if localStorage.auto_reload is "yay"
				setTimeout ->
					location.reload()
				, 500
		when applicationCache.UNCACHED
			$('#cachestatus').text 'Uncached'
		when applicationCache.OBSOLETE
			$('#cachestatus').text 'Obsolete'
		when applicationCache.IDLE
			$('#cachestatus').text 'Cached'
		when applicationCache.DOWNLOADING
			$('#cachestatus').text 'Downloading'
		when applicationCache.CHECKING
			$('#cachestatus').text 'Checking'

do -> # isolate variables from globals
	if window.applicationCache
		for name in ['cached', 'checking', 'downloading', 'error', 'noupdate', 'obsolete', 'progress', 'updateready']
			applicationCache.addEventListener name, handleCacheEvent

# asynchronously load offline components
#also, html5slider isnt actually for offline,
# but it can be loaded async, so lets do that, 
# and reuse all the crap that can be reused
setTimeout ->
	window.exports = {}
	window.require = -> window.exports
	deps = ["html5slider", "levenshtein", "removeDiacritics", "porter", "answerparse", "syllable", "names", "offline"]
	loadNextResource = ->
		$.ajax {
			url: "lib/#{deps.shift()}.js",
			cache: true,
			dataType: "script",
			success: ->
				if deps.length > 0
					loadNextResource()
		}
	loadNextResource()
, 10

