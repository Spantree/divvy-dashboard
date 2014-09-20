files =
  '2013': 'data/Divvy_Trips_2013.csv'

loadData = (csvFile) ->
  d3.csv csvFile, (data) ->
    ndx = crossfilter(data)

loadData files['2013']