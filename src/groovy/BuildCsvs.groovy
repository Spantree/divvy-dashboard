import com.spatial4j.core.context.SpatialContext
import com.spatial4j.core.context.SpatialContextFactory
import com.spatial4j.core.distance.DistanceUtils
import com.spatial4j.core.shape.Point
import com.spatial4j.core.shape.impl.PointImpl

import java.text.DecimalFormat
import java.text.SimpleDateFormat
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import au.com.bytecode.opencsv.CSVReader
import au.com.bytecode.opencsv.CSVParser
import au.com.bytecode.opencsv.CSVWriter

class BuildCsvs {
    static Map<List<Integer>, Double> distanceFromStations = [:]
    static SpatialContext spatialContext = SpatialContext.GEO
    static Map<Integer, Point> stations = [:]

    static dateFormats = [
        new SimpleDateFormat("yyyy-MM-dd hh:mm"),
        new SimpleDateFormat("M/d/yyyy hh:mm")
    ]

    static distanceFormat = new DecimalFormat("0.00")

    static getRow(String[] line, String[] headers) {
        def row = [:]
        headers.eachWithIndex{ k, i ->
            row[k] = line[i]
        }
        row
    }

    static Double milesMultiplier = 2 * Math.PI * DistanceUtils.EARTH_MEAN_RADIUS_MI / 360

    static Double getDistanceBetweenStations(int fromStationId, int toStationId) {
        List<Integer> key = fromStationId <= toStationId ? [fromStationId, toStationId] : [toStationId, fromStationId]

        Float distance = distanceFromStations.get(key)
        if(distance == null) {
            Point fromPoint = stations[fromStationId]
            Point toPoint = stations[toStationId]
            double[] vectorX = [fromPoint.x, fromPoint.y]
            double[] vectorY = [toPoint.x, toPoint.y]
            distance = DistanceUtils.vectorDistance(vectorX, vectorY, 1.0) * milesMultiplier
            distanceFromStations[key] = distance
        }

        distance
    }

    static Date parseDate(String dateStr) {
        Date date = null
        dateFormats.each { df ->
            try {
                date = df.parse(dateStr)
            } catch(Exception e) { }
        }
        return date
    }

    static void main(String[] args) {
        def dataDir = new File("data")

        // Load Divvy Stations
        dataDir.eachFileMatch(~/Divvy_Stations_.*\.csv$/) { f ->
            println "Processing ${f.name}"
            def reader = new CSVReader(f.newReader('utf8'))
            String[] headers = reader.readNext()
            String[] line = null
            while((line = reader.readNext()) != null) {
                def row = getRow(line, headers)
                def latitude = Double.parseDouble(row.latitude)
                def longitude = Double.parseDouble(row.longitude)
                stations[Integer.parseInt(row.id)] = new PointImpl(latitude, longitude, spatialContext)
            }
            reader.close()
        }

        // Uncompress trips file
        dataDir.eachFileMatch(~/Divvy_Trips_.*\.csv\.gz$/) { f ->
            println "Extracting ${f.name}"
            def outFileName = f.name.replaceAll(/\.gz$/, "")
            def outFile = new File(outFileName, dataDir)
            def zis = new GZIPInputStream(new FileInputStream(f))
            def out = new FileOutputStream(outFile)
            out << zis
            out.close()
            zis.close()
        }

        // Initialize CSV Writers
        Map<String, File> writers = [:]
        ['all', '2013', '2014'].each { key ->
            def file = new File("${key}_trips.csv", dataDir)
            writers[key] = file
            file.write(['start_time', 'trip_duration', 'trip_distance', 'rider_age', 'rider_gender', 'user_type'].join(','))
        }

        // Update Divvy data
        dataDir.eachFileMatch(~/Divvy_Trips_.*\.csv$/) { f ->
            println "Processing ${f.name}"
            def reader = new CSVReader(f.newReader('utf8'))
            String[] headers = reader.readNext()
            String[] line = null

            while((line = reader.readNext()) != null) {
                def row = getRow(line, headers)
                def fromStationId = Integer.parseInt(row.from_station_id)
                def toStationId = Integer.parseInt(row.to_station_id)
                Date startTime = parseDate(row.starttime)
                def birthYear = row.birthday ? Integer.parseInt(row.birthday) : null
                def startYear = startTime.year + 1900
                def riderAge = birthYear ? startYear - birthYear : -1
                def tripDistance = getDistanceBetweenStations(fromStationId, toStationId)
                def tripDuration = Integer.parseInt(row.tripduration)
                [writers.all, writers[startYear.toString()]].each { File out ->
                    // We write to the file directly instead of using CSVWriter so we can preserve native types
                    out.append('\n')
                    out.append([
                        '"' + dateFormats[0].format(startTime) + '"',
                        tripDuration,
                        distanceFormat.format(tripDistance),
                        riderAge,
                        '"' + row.gender ?: 'Undisclosed' + '"',
                        '"' + row.usertype == 'Subscriber' ? 'Member' : 'Guest' + '"'
                    ].join(','))
                }
            }
            reader.close()
        }

        writers.each { key, file ->
            def fis = new FileInputStream(file)
            def outFile = new File("${file.name}.gz", dataDir)
            println "Writing ${outFile.name}"
            def zos = new GZIPOutputStream(new FileOutputStream(outFile))
            zos << fis
            fis.close()
            zos.close()
        }
    }


}
