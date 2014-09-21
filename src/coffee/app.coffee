files =
  '2013': 'data/Divvy_Trips_2013.csv',
  '1H2014': 'data/Divvy_Trips_2014_Q1Q2.csv'

dateFormat = d3.time.format "%Y-%m-%d %H:%M"

console.logCopy = console.log.bind(console)

console.log = (msg, data) ->
  this.logCopy("[#{new Date().toUTCString()}] #{msg}", data);

lastEvent = ''

logEventBoundaries = (eventName) ->
  if eventName != lastEvent
    if lastEvent
      console.log "Finished #{lastEvent}"
    console.log "Started eventName"
    lastEvent = eventName

progressTimings =
  'Fetching CSV': 10
  'Pre-parsing data': 20
  'Loading dimensions': 80
  'Rendering': 100

chartDefaults =
  
  lineChart:
    # renderArea: true
    width: 1170
    height: 200
    # transitionDuration: 1000
    brushOn: false
    mouseZoomable: true
    elasticY: true
    # legend: dc.legend().x(1070).y(10).itemHeight(13).gap(5)
    margins:
      top: 30
      right: 10
      bottom: 25
      left: 40

  barChart:
    width: 400
    height: 240
    elasticY: true
    centerBar: true
    gap: 1
    renderHorizontalGridLines: true
    margins:
      top: 10
      right: 50
      bottom: 30
      left: 40

  rowChart:
    width: 320
    height: 240
    elasticX: true
    margins:
      top: 20
      left: 10
      right: 10
      bottom: 20

  pieChart:
    width: 250
    height: 250
    radius: 125
    innerRadius: 45

loadData = (csvFile) ->
  console.log "Started processing CSV", csvFile

  # Use the D3 library to parse a CSV file into an array of JSON objects
  d3.csv csvFile, (data) ->
    console.log "Finished processing CSV"
    startTime = new Date()

    # Pre-parse the dates and calculate things like rider age
    data.forEach (d) ->
      d.startdate = dateFormat.parse(d.starttime)
      d.day = d3.time.day.floor(d.startdate)
      d.age = if d.birthday then d.startdate.getFullYear() - d.birthday else -1
      d.gender = d.gender || 'Undisclosed'

    console.log "Finished pre-parsing data"

    # Load the data into a crossfilter multi-dimensional data set
    ndx = crossfilter(data)

    # Create a group for all records (useful for counts, etc)
    all = ndx.groupAll()

    # Ignore non-subscriber counts for certain fields like gender and age
    # since we only have valid data for subscribers
    ignoreCustomerReducer = (dimension) ->
      dimension.group().reduceSum (d) ->  
        if d.usertype == 'Subscriber' then 1 else 0

    # Create a number of dimensions to slice and dice the data. The dimension
    # is the "bucket" we're aggregating into.
    dimensions =
      byDate:
        makeDimension: (d) -> d.day

      byHourOfDay:
        makeDimension: (d) -> d.startdate.getHours()
        el: '#time-of-day-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([0, 23])
        postSetup: (chart) ->
          chart.xAxis().ticks(6).tickFormat (v) ->
            if v == 0 then "Midnight" else if v < 12 then "#{v}am" else "#{v-12}pm"

      byDayOfWeek:
        makeDimension: (d) -> d.startdate.getDay()
        el: '#day-of-week-chart'
        chartType: 'rowChart'
        chartOptions:
          ordinalColors: ['#88419d', '#08519c', '#2171b5', '#4292c6', '#6baed6', '#9ecae1', '#88419d']
        labels:
          ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
        postSetup: (chart) ->
          chart.xAxis().ticks(4)

      byDuration:
        makeDimension: (d) -> d3.round(d.tripduration / 60)
        el: '#trip-duration-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([0, 75])

      byUserType:
        makeDimension: (d) -> d.usertype
        el: '#user-type-chart'
        chartType: 'pieChart'

      byAge:
        makeDimension: (d) -> d.age
        reducer: ignoreCustomerReducer
        el: '#age-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([15, 75])

      byGender:
        makeDimension: (d) -> d.gender
        reducer: ignoreCustomerReducer
        el: '#gender-chart'
        chartType: 'pieChart'

    processDimension = () ->
      ###
      Set the dimension object for each function, this defines the "bucket"
      ###
      if typeof @makeDimension == 'function'
        @dimension = ndx.dimension @makeDimension

      ###
      Then define the group operation, which determines the value for each bucket.
      For most cases, we're just looking to do a simple count of rides, but if we explicitly
      override that with a custom reducer function, use that instead.
      ###
      if typeof @reducer == 'function'
        @group = @reducer(@dimension)
      else
        @group = @dimension.group().reduceCount()

      ###
      If we have a chart and dom element defined for the dimension, bootstrap the chart
      with the dimension and group generated above.
      ###
      if @chartType and @el
        @chart = dc[@chartType](@el)
          .dimension(@dimension)
          .group(@group)

        ###
        Also, set some options for the chart based on the default values configured for
        the chart type or the values of `chartOptions` defined at the dimension level.
        ###
        defaultOptions = chartDefaults[@chartType] || {}
        options = _.defaults(@chartOptions || {}, defaultOptions)
        for option, value of options
          @chart[option](value)

        ###
        If we've defined a labels array for the dimension, replace the d.key with the
        corresponding value from the array.
        ### 
        if typeof @labels == 'object'
          @chart.label (d) =>
            @labels[d.key]

        ###
        If we've defined a post-setup function for the dimension (the set axis
        parameters, etc), call it here
        ###
        if typeof @postSetup == 'function'
          @postSetup(@chart, this)

    for name, dimension of dimensions
      processDimension.apply(dimension)

    # For our primary time series grouping, we also want to reduce a special value that denotes
    # the total user time spent on a bike for that given interval (the sum of all trip durations).
    # dimensions.byDate.minutesOnBikeGroup =
    #   dimensions.byDate.dimension.group().reduceSum (d) -> d.tripduration

    dc.renderAll()

    took = new Date().getTime() - startTime.getTime()
    console.log "Done, took #{took}ms."

    $('#reset-all').click () ->
      dc.filterAll()
      dc.redrawAll()

loadData files['2013']