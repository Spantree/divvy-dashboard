files =
  '2013': 'data/Divvy_Trips_2013.csv',
  '1H2014': 'data/Divvy_Trips_2014_Q1Q2.csv'

dateFormat = d3.time.format "%Y-%m-%d %H:%M"

console.logCopy = console.log.bind(console)

console.log = (msg, data) ->
  this.logCopy("[#{new Date().toUTCString()}] #{msg}", data);

progressTimings =
  'Fetching CSV': 10
  'Pre-parsing data': 20
  'Loading dimensions': 80
  'Rendering': 100

chartDefaults =
  
  lineChart:
    transitionDuration: 1
    renderArea: true
    width: 1170
    height: 200
    brushOn: false
    mouseZoomable: false
    elasticY: true
    renderHorizontalGridLines: true
    legend: dc.legend().x(1000).y(10).itemHeight(13).gap(5)
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

class DimensionChart
  reducers:
    allRides: ->
      @dimension.group().reduceCount()
    customerRides: ->
      @dimension.group().reduceSum (d) ->
        if d.usertype == 'Customer' then 1 else 0
    subscriberRides: ->
      @dimension.group().reduceSum (d) ->
        if d.usertype == 'Subscriber' then 1 else 0
    minutesOnBike: ->
      @dimension.group().reduceSum (d) ->
        d.tripduration

  constructor: (opts) ->
    @name = opts.name
    @el = opts.el
    @chartType = opts.chartType
    @chartOptions = _.defaults(opts.chartOptions || {}, chartDefaults[@chartType])
    @labels = opts.labels
    @postSetup = opts.postSetup
    @dimensionFunction = opts.dimensionFunction
    @reducer = opts.reducer || 'allRides'
    @rangeChart = opts.rangeChart
    @additionalGroupNames = opts.additionalGroupNames || []

  applyToCrossFilter: (ndx) ->
    @dimension = ndx.dimension @dimensionFunction
    @group = @reducers[@reducer].apply(this)
    if @additionalGroupNames
      @additionalGroups = {}
    for name in @additionalGroupNames
      @additionalGroups[name] = @reducers[name].apply(this)

    return

  createRangeChart: ->
    opts = @rangeChart
    group = @additionalGroups[opts.group] || @group
    chart = dc[opts.chartType](opts.el)
      .dimension(@dimension)
      .group(group)

    for option, value of opts.chartOptions
      chart[option](value)

    if typeof opts.postSetup == 'function'
      opts.postSetup.apply(chart)

    @chart.rangeChart(chart)

  createChart: ->
    ###
    If we have a chart and dom element defined for the dimension, bootstrap the chart
    with the dimension and group generated above.
    ###
    if @chartType and @el
      @chart = dc[@chartType](@el)
        .dimension(@dimension)
        .group(@group, @name)

      ###
      Also, set some options for the chart based on the default values configured for
      the chart type or the values of `chartOptions` defined at the dimension level.
      ###
      for option, value of @chartOptions
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
        @postSetup.apply(this)

      if typeof @rangeChart == 'object'
        @createRangeChart()
        

      return

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
      d.membertype = if d.usertype == 'Subscriber' then 'Member' else 'Guest'
      d.gender = d.gender || 'Undisclosed'
      return

    dateExtent = d3.extent data, (d) -> d.day

    console.log "Finished pre-parsing data"

    # Load the data into a crossfilter multi-dimensional data set
    ndx = crossfilter(data)

    # Create a group for all records (useful for counts, etc)
    all = ndx.groupAll()

    # Create a number of dimensions to slice and dice the data. The dimension
    # is the "bucket" we're aggregating into.
    dimensions = [
      new DimensionChart
        name: 'Member Rides per Day'
        dimensionFunction: (d) -> d.day
        reducer: 'subscriberRides'
        additionalGroupNames: ['customerRides', 'minutesOnBike']
        el: '#trips-over-time-chart'
        chartType: 'lineChart'
        chartOptions:
          x: d3.time.scale().domain(dateExtent)
          xUnits: d3.time.days
        postSetup: ->
          @chart
            .stack(@additionalGroups.customerRides, "Guest Rides Per Day")

        rangeChart:
          el: '#minutes-on-bike-chart'
          chartType: 'barChart'
          group: 'minutesOnBike'
          postSetup: ->
            @yAxis().tickValues []
          chartOptions:
            width: 1170
            height: 40
            centerBar: true
            gap: 1
            x: d3.time.scale().domain(dateExtent)
            xUnits: d3.time.days
            margins:
              top: 0
              right: 0
              bottom: 20
              left: 40

      new DimensionChart
        name: 'Hour of Day'
        dimensionFunction: (d) -> d.startdate.getHours()
        el: '#time-of-day-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([0, 23])
        postSetup: ->
          @chart.xAxis().ticks(6).tickFormat (v) ->
            if v == 0 then "Midnight" else if v < 12 then "#{v}am" else "#{v-12}pm"

      new DimensionChart
        name: 'Day of Week'
        dimensionFunction: (d) -> d.startdate.getDay()
        el: '#day-of-week-chart'
        chartType: 'rowChart'
        chartOptions:
          ordinalColors: ['#88419d', '#08519c', '#2171b5', '#4292c6', '#6baed6', '#9ecae1', '#88419d']
        labels:
          ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
        postSetup: ->
          @chart.xAxis().ticks(4)

      new DimensionChart
        name: 'Trip Duration'
        dimensionFunction: (d) -> d3.round(d.tripduration / 60)
        el: '#trip-duration-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([0, 75])

      new DimensionChart
        name: 'User Type'
        dimensionFunction: (d) -> d.membertype
        el: '#user-type-chart'
        chartType: 'pieChart'

      new DimensionChart
        name: 'Age of Rider'
        dimensionFunction: (d) -> d.age
        reducer: 'subscriberRides'
        el: '#age-chart'
        chartType: 'barChart'
        chartOptions:
          x: d3.scale.linear().domain([15, 75])

      new DimensionChart
        name: 'Gender of Rider'
        dimensionFunction: (d) -> d.gender
        reducer: 'subscriberRides'
        el: '#gender-chart'
        chartType: 'pieChart'
    ]

    for dimension in dimensions
      console.log "Building dimension '#{dimension.name}'"
      dimension.applyToCrossFilter(ndx)
      dimension.createChart()

    dc.renderAll()

    took = new Date().getTime() - startTime.getTime()
    console.log "Done, took #{took}ms."

    alert "Chart ready"

    $('#reset-all').click ->
      dc.filterAll()
      dc.redrawAll()

loadData files['2013']