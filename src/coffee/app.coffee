files =
  '2013': 'data/Divvy_Trips_2013.csv',
  '1H2014': 'data/Divvy_Trips_2014_Q1Q2.csv'

dateFormat = d3.time.format "%Y-%m-%d %H:%M"

loadData = (csvFile) ->
  # Use the D3 library to parse a CSV file into an array of JSON objects
  d3.csv csvFile, (data) ->
    startTime = new Date()

    # Pre-parse the dates and calculate things like rider age
    data.forEach (d) ->
      d.startdate = dateFormat.parse(d.starttime)
      d.enddate = dateFormat.parse(d.stoptime)
      d.day = d3.time.day.round(d.startdate)
      d.age = if d.birthday then d.startdate.getFullYear() - d.birthday else -1
      d.gender = d.gender || 'Undisclosed'

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
        dimension: ndx.dimension (d) -> d.day
      byHourOfDay:
        dimension: ndx.dimension (d) -> d.startdate.getHours()
      byDayOfWeek:
        dimension: ndx.dimension (d) -> d.startdate.getDay()
      byDuration:
        dimension: ndx.dimension (d) -> d.tripduration / 60
      byUserType:
        dimension: ndx.dimension (d) -> d.byUserType
      byAge:
        dimension: ndx.dimension (d) -> d.age
        # As mentioned before, in certain cases we want to exclude non-subscribers
        # (referred to as "Customers") from the count since we don't have valid user
        # data.
        reducer: ignoreCustomerReducer
      byGender:
        dimension: ndx.dimension (d) -> d.gender
        reducer: ignoreCustomerReducer

    # Now that the dimensions are defined, we can "group" them by running simple map-reduce.
    # For most cases, we're just looking to do a simple count of rides, but if we explicitly
    # override that with a custom reducer function, use that instead.
    for name, obj of dimensions
      if obj.reducer and typeof obj.reducer == 'function'
        obj.group = reducer(obj.dimension)
      else
        obj.group = obj.dimension.group().reduceCount()

    # For our primary time series grouping, we also want to reduce a special value that denotes
    # the total user time spent on a bike for that given interval (the sum of all trip durations).
    byDate.minutesOnBikeGroup =
      byDate.dimension.group().reduceSum (d) -> d.tripduration

    took = new Date().getTime() - startTime.getTime()
    console.log "Done, took #{took}ms."
    alert "done"
loadData files['2013']