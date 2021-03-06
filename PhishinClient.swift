//
//  PhishinClient.swift
//  PhishTour
//
//  Created by Aaron Justman on 9/30/15.
//  Copyright (c) 2015 AaronJ. All rights reserved.
//

import UIKit
import CoreData

class PhishinClient: NSObject
{
    let context = CoreDataStack.sharedInstance().managedObjectContext
    let session: NSURLSession = NSURLSession.sharedSession()
    let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
    
    /// to construct request URLs
    let endpoint: String = "http://phish.in/api/v1"
    struct Routes
    {
        static let Years = "/years"
        static let Tours = "/tours"
        static let Shows = "/shows"
        static let Songs = "/songs"
    }
    
    /// phish has played a bunch of one-off shows that aren't part of any formal tour. phish.in gives all those shows the tour id 71.
    /// i use it as a flag to prevent "not part of a tour" from appearing in the tour picker
    let notPartOfATour: Int = 71
    
    /// references to the progress bars on the tour selecter, setlist, and song history view controllers
    var tourSelecterProgressBar: UIProgressView!
    var setlistProgressBar: UIProgressView!
    var historyProgressBar: UIProgressView!
    
    class func sharedInstance() -> PhishinClient
    {
        struct Singleton
        {
            static var sharedInstance = PhishinClient()
        }
        
        return Singleton.sharedInstance
    }
    
    /// request the years that phish toured in
    func requestYears(completionHandler:(yearsRequestError: NSError!, years: [PhishYear]?) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            /// create the URL and start the task
            let yearsRequestString = self.endpoint + Routes.Years
            let yearsRequestURL = NSURL(string: yearsRequestString)!
            let yearsRequestTask = self.session.dataTaskWithURL(yearsRequestURL)
            {
                yearsData, yearsResponse, yearsError in
                
                /// something went wrong
                if yearsError != nil
                {
                    completionHandler(yearsRequestError: yearsError, years: nil)
                }
                else
                {
                    do
                    {
                        let yearsResults = try NSJSONSerialization.JSONObjectWithData(yearsData!, options: []) as! [String : AnyObject]
                        
                        /// all three shows from 2002 are "category 71," so i'm removing from 2002 from the list of searchable years;
                        /// this requires creating a mutable NSArray, removing the specified year, and then casting it back to a [String] array
                        let theYears = yearsResults["data"] as! NSArray
                        let theYearsMutable: AnyObject = theYears.mutableCopy()
                        theYearsMutable.removeObjectAtIndex(14)
                        let years = NSArray(array: theYearsMutable as! [AnyObject]) as! [String]
                        
                        var phishYears = [PhishYear]()
                        self.context.performBlockAndWait()
                        {
                            /// create PhishYear objects for every year and bump the progress bar
                            let progressBump: Float = 1.0 / 20.0
                            var totalProgress: Float = 0
                            self.context.performBlockAndWait()
                            {
                                for year in years
                                {
                                    if let intYear = Int(year)
                                    {
                                        self.context.performBlockAndWait()
                                        {
                                            let newYear = PhishYear(year: intYear)
                                    
                                            phishYears.append(newYear)
                                        }
                                        
                                        totalProgress += progressBump
                                        dispatch_async(dispatch_get_main_queue())
                                        {
                                            self.tourSelecterProgressBar.setProgress(totalProgress, animated: true)
                                        }
                                    }
                                }
                            }
                        }
                        
                        self.context.performBlockAndWait()
                        {
                            /// reverse the results so that the most recent tours and shows appear first in the list
                            phishYears.sortInPlace
                            {
                                year1, year2 in
                                
                                Int(year1.year) > Int(year2.year)
                            }
                        }
                        
                        /// send it back through the completion handler
                        completionHandler(yearsRequestError: nil, years: phishYears)
                    }
                    catch
                    {
                        print("There was a problem processing the years results.")
                    }
                }
            }
            yearsRequestTask.resume()
        }
    }
    
    /// this request has two parts:
    /// the first request returns all the shows played in that year and creates arrays for each set of shows in a particular tour,
    /// the second request gets a name for each unique tour ID,
    /// once all the tour info is collected, a [PhishTour] array is returned through the completion handler
    func requestToursForYear(year: PhishYear, completionHandler: (toursRequestError: NSError!, tours: [PhishTour]!) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            self.context.performBlockAndWait()
            {
                let toursRequestString = self.endpoint + Routes.Years + "/\(year.year)"
                let toursRequestURL = NSURL(string: toursRequestString)!
                let toursRequestTask = self.session.dataTaskWithURL(toursRequestURL)
                {
                    toursData, toursResponse, toursError in
                    
                    /// something went wrong
                    if toursError != nil
                    {
                        completionHandler(toursRequestError: toursError, tours: nil)
                    }
                    else
                    {
                        do
                        {
                            let toursResults = try NSJSONSerialization.JSONObjectWithData(toursData!, options: []) as! [String : AnyObject]
                            let showsForTheYear = toursResults["data"] as! [[String : AnyObject]]
                            
                            /// collect all the shows and tour IDs from the results
                            var tourIDs = [Int]()
                            for show in showsForTheYear
                            {
                                /// only append unique tour IDs, tour IDs that haven't already been requested,
                                /// and tours that aren't "not part of a tour"
                                let tourID = show["tour_id"] as! Int
                                
                                self.context.performBlockAndWait()
                                {
                                    if let yearTourIDs = year.tourIDs
                                    {
                                        if !yearTourIDs.contains(tourID) && !tourIDs.contains(tourID) && tourID != self.notPartOfATour
                                        {
                                            tourIDs.append(tourID)
                                        }
                                    }
                                    else
                                    {
                                        tourIDs.append(tourID)
                                    }
                                }
                            }
                            
                            /// get the names of each tour
                            self.requestTourNamesForIDs(tourIDs, year: year)
                            {
                                tourNamesRequestError, tours in
                                
                                /// something went wrong
                                if tourNamesRequestError != nil
                                {
                                    completionHandler(toursRequestError: tourNamesRequestError, tours: nil)
                                }
                                else
                                {
                                    self.context.performBlockAndWait()
                                    {
                                        /// send the tours back through the completion handler
                                        completionHandler(toursRequestError: nil, tours: year.tours!)
                                    }
                                }
                            }
                        }
                        catch
                        {
                            print("There was a problem processing the tours results.")
                        }
                    }
                }
                toursRequestTask.resume()
            }
        }
    }
    
    /// requests the name of a tour for a given tour ID;
    /// the name is used in the song history table view, the PhishTour object is used when the user selects that show and pops back to the map
    func requestTourNameForID(id: Int, completionHandler: (tourNameRequestError: NSError?, tourName: String?) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            let tourIDRequestString = self.endpoint + Routes.Tours + "/\(id)"
            let tourIDRequestURL = NSURL(string: tourIDRequestString)!
            let tourIDRequestTask = self.session.dataTaskWithURL(tourIDRequestURL)
            {
                tourData, tourResponse, tourError in
                
                /// something went wrong
                if tourError != nil
                {
                    completionHandler(tourNameRequestError: tourError!, tourName: nil)
                }
                else
                {
                    do
                    {
                        let tourResults = try NSJSONSerialization.JSONObjectWithData(tourData!, options: []) as! [String : AnyObject]
                        let tourData = tourResults["data"] as! [String : AnyObject]
                        let tourName = tourData["name"] as! String
                        
                        /// send the tour name back through the completion handler
                        completionHandler(tourNameRequestError: nil, tourName: tourName)
                    }
                    catch
                    {
                        print("There was a problem getting the tour name for tour \(id).")
                    }
                }
            }
            tourIDRequestTask.resume() 
        }
    }
    
    /// requests names for tours given a set of tour IDs
    func requestTourNamesForIDs(tourIDs: [Int], year: PhishYear, completionHandler: (tourNamesRequestError: NSError!, tours: [PhishTour]!) -> Void)
    {
        var tours = [PhishTour]()
        
        /// the progress bar will update as each request is completed
        var currentProgress: Float?
        var progressBump: Float?
        if let tourSelecterProgressBar = self.tourSelecterProgressBar
        {
            currentProgress = tourSelecterProgressBar.progress
            progressBump = 1.0 / Float(tourIDs.count)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            for tourID in tourIDs
            {
                if currentProgress != nil
                {
                    /// increment the progress bar
                    currentProgress! += progressBump!
                    dispatch_async(dispatch_get_main_queue())
                    {
                        self.tourSelecterProgressBar.setProgress(currentProgress!, animated: true)
                    }
                }
                
                let tourIDRequestString = self.endpoint + Routes.Tours + "/\(tourID)"
                let tourIDRequestURL = NSURL(string: tourIDRequestString)!
                let tourIDRequestTask = self.session.dataTaskWithURL(tourIDRequestURL)
                {
                    tourData, tourResponse, tourError in
                    
                    /// something went wrong
                    if tourError != nil
                    {
                        completionHandler(tourNamesRequestError: tourError, tours: nil)
                    }
                    else
                    {
                        do
                        {
                            let tourResults = try NSJSONSerialization.JSONObjectWithData(tourData!, options: []) as! [String : AnyObject]
                            let theTourData = tourResults["data"] as! [String : AnyObject]
                            let tourName = theTourData["name"] as! String
                            
                            self.context.performBlockAndWait()
                            {
                                /// create a new tour and set the show/tour relationship
                                let newTour = PhishTour(year: year, name: tourName, tourID: tourID)
                                
                                /// add the new tour to the array being sent back
                                tours.append(newTour)
                            }                            
                        }
                        catch
                        {
                            print("There was a problem processing the results for tour \(tourID).")
                        }
                    }
                    
                    self.context.performBlockAndWait()
                    {
                        /// sort the tours by ID
                        tours.sortInPlace()
                        {
                            tour1, tour2 in
                            
                            Int(tour1.tourID) < Int(tour2.tourID)
                        }
                    }
                    
                    /// return the tours through the completion handler
                    completionHandler(tourNamesRequestError: nil, tours: tours)
                }
                tourIDRequestTask.resume()
            }
        }
    }
    
    /// request the shows for a tour and return the results by completion handler
    func requestShowsForTour(inout tour: PhishTour, completionHandler: (showsRequestError: NSError!) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            self.context.performBlockAndWait()
            {
                /// construct a URL for the tour request and start a task
                let tourRequestString = self.endpoint + Routes.Tours + "/\(tour.tourID)"
                let tourRequestURL = NSURL(string: tourRequestString)!
                let tourRequestTask = self.session.dataTaskWithURL(tourRequestURL)
                {
                    tourRequestData, tourRequestResponse, tourRequestError in
                    
                    /// something went wrong
                    if tourRequestError != nil
                    {
                        completionHandler(showsRequestError: tourRequestError)
                    }
                    else
                    {
                        do
                        {
                            /// create a JSON object and get at the shows
                            let tourResults = try NSJSONSerialization.JSONObjectWithData(tourRequestData!, options: []) as! [String : AnyObject]
                            let tourData = tourResults["data"] as! [String : AnyObject]
                            let shows = tourData["shows"] as! [[String : AnyObject]]
                            
                            /// request show data for each show
                            var showIDs = [Int]()
                            for show in shows
                            {
                                let showID = show["id"] as! Int
                                showIDs.append(showID)
                            }
                            
                            self.requestShowsForIDs(showIDs, andTour: tour)
                            {
                                showRequestsError in
                                
                                if showRequestsError != nil
                                {
                                    completionHandler(showsRequestError: showRequestsError)
                                }
                                else
                                {
                                    completionHandler(showsRequestError: nil)
                                }
                            }
                        }
                        catch
                        {
                            print("There was an error with the data received for \(tour.name)")
                        }
                    }
                }
                tourRequestTask.resume()
            }
        }
    }
    
    /// request show info for every show on the tour
    func requestShowsForIDs(showIDs: [Int], andTour tour: PhishTour, completionHandler: (showRequestsError: NSError!) -> Void)
    {
        /// the progress bar will update as each show is created
        var currentProgress: Float?
        var progressBump: Float?
        if let tourSelecterProgressBar = self.tourSelecterProgressBar
        {
            currentProgress = tourSelecterProgressBar.progress
            progressBump = 1.0 / Float(showIDs.count)
        }
        
        /// temporary holders for the new shows
        var shows = [PhishShow]()
        var showsToGeocode = [PhishShow]()
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            /// create a serial dispatch queue for these requests
            /// NOTE: insight into creating dispatch queues here: http://stackoverflow.com/a/11909880
            let showDispatchQueue = dispatch_queue_create(nil, DISPATCH_QUEUE_SERIAL)
            
            /// keep track of the requests
            var showsToRequest = showIDs.count
            for showID in showIDs
            {
                /// construct the request URL
                let showRequestString = self.endpoint + Routes.Shows + "/\(showID)"
                let showRequestURL = NSURL(string: showRequestString)!
                
                dispatch_sync(showDispatchQueue)
                {
                    let showRequestTask = self.session.dataTaskWithURL(showRequestURL)
                    {
                        showRequestData, showRequestResponse, showRequestError in
                        
                        if showRequestError != nil
                        {
                            completionHandler(showRequestsError: showRequestError)
                        }
                        else
                        {
                            do
                            {
                                /// get the show data
                                let showResults = try NSJSONSerialization.JSONObjectWithData(showRequestData!, options: []) as! [String : AnyObject]
                                let showData = showResults["data"] as! [String : AnyObject]
                                
                                self.context.performBlockAndWait()
                                {
                                    /// create a new show
                                    let newShow = PhishShow(showInfoFromShow: showData)
                                    
                                    /// check that there was latitude/longitude info,
                                    /// otherwise, put the show in a separate array
                                    if newShow.showLatitude != 0 && newShow.showLongitude != 0
                                    {
                                        shows.append(newShow)
                                        
                                        --showsToRequest
                                    }
                                    else
                                    {
                                        showsToGeocode.append(newShow)
                                        
                                        --showsToRequest
                                    }
                                }                                
                                
                                /// update the progress bar
                                if currentProgress != nil
                                {
                                    currentProgress! += progressBump!
                                    dispatch_async(dispatch_get_main_queue())
                                    {
                                        self.tourSelecterProgressBar.setProgress(currentProgress!, animated: true)
                                    }
                                }
                                
                                /// all the requests have finished
                                if showsToRequest == 0
                                {
                                    /// none of the shows needed geocoding
                                    if showsToGeocode.isEmpty
                                    {
                                        self.context.performBlockAndWait()
                                        {
                                            /// set the relationship
                                            for show in shows
                                            {
                                                show.tour = tour
                                            }
                                        }
                                        
                                        /// return by completion handler
                                        completionHandler(showRequestsError: nil)
                                        
                                        return
                                    }
                                    /// one or more shows were missing latitude/longitude info
                                    else
                                    {
                                        /// give the progress bar to the Mapquest client
                                        MapquestClient.sharedInstance().tourMapProgressBar = self.tourSelecterProgressBar
                                        
                                        dispatch_sync(showDispatchQueue)
                                        {
                                            /// geocode the shows
                                            MapquestClient.sharedInstance().geocodeShows(showsToGeocode, withType: .Batch)
                                            {
                                                /// something went wrong
                                                geocodingError in
                                                
                                                if geocodingError != nil
                                                {
                                                    completionHandler(showRequestsError: geocodingError)
                                                }
                                                else
                                                {
                                                    /// add the geocoded shows to the rest, then sort, etc.
                                                    shows += showsToGeocode
                                                    
                                                    self.context.performBlockAndWait()
                                                    {
                                                        /// set the relationship
                                                        for show in shows
                                                        {
                                                            show.tour = tour
                                                        }
                                                    }
                                                    
                                                    completionHandler(showRequestsError: nil)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            catch
                            {
                                print("There was an error with the show request.")
                            }
                        }
                    }
                    showRequestTask.resume()
                }
            }
        }
    }
    
    /// request a setlist for a given show and return the result by completion handler
    func requestSetlistForShow(show: PhishShow, completionHandler: (setlistError: NSError?, setlist: [Int : [PhishSong]]?) -> Void)
    {
        dispatch_async(dispatch_get_main_queue())
        {
            self.setlistProgressBar.setProgress(0.8, animated: true)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            self.context.performBlockAndWait()
            {
                /// construct a URL to the setlist and start a task
                let setlistRequestString = self.endpoint + Routes.Shows + "/\(show.showID)"
                let setlistRequestURL = NSURL(string: setlistRequestString)!
                let setlistRequestTask = self.session.dataTaskWithURL(setlistRequestURL)
                {
                    setlistData, setlistResponse, setlistError in
                    
                    /// an error occurred
                    if setlistError != nil
                    {
                        completionHandler(setlistError: setlistError, setlist: nil)
                    }
                    else
                    {
                        do
                        {
                            /// turn the received data into a JSON object
                            let setlistResults = try NSJSONSerialization.JSONObjectWithData(setlistData!, options: []) as! [String : AnyObject]
                            
                            /// get the songs
                            let resultsData = setlistResults["data"] as! [String : AnyObject]
                            let tracks = resultsData["tracks"] as! [[String : AnyObject]]
                            
                            /// the progress bar will update as each song is added to the setlist
                            var currentProgress: Float?
                            var progressBump: Float?
                            if let setlistProgressBar = self.setlistProgressBar
                            {
                                currentProgress = setlistProgressBar.progress
                                progressBump = 0.2 / Float(tracks.count)
                            }
                            
                            /// create each song and update the progress bar
                            for track in tracks
                            {
                                self.context.performBlockAndWait()
                                {
                                    let newSong = NSEntityDescription.insertNewObjectForEntityForName("PhishSong", inManagedObjectContext: self.context) as! PhishSong
                                    newSong.updateProperties(track)
                                    newSong.show = show
                                }
                                
                                if currentProgress != nil
                                {
                                    currentProgress! += progressBump!
                                    dispatch_async(dispatch_get_main_queue())
                                    {
                                        self.setlistProgressBar.setProgress(currentProgress!, animated: true)
                                    }
                                }
                            }
                            
                            /// save new and updated objects to the context
                            self.context.performBlockAndWait()
                            {
                                CoreDataStack.sharedInstance().saveContext()
                            }
                            
                            /// return the setlist through the completion handler
                            completionHandler(setlistError: nil, setlist: show.setlist!)
                        }
                        catch
                        {
                            print("There was an error parsing the setlist data for \(show.date) \(show.year)")
                        }
                    }
                }
                setlistRequestTask.resume()  
            }
        }
    }
    
    /// request all the shows a song was performed at
    func requestHistoryForSong(song: PhishSong, completionHandler: (songHistoryError: NSError?) -> Void)
    {
        dispatch_async(dispatch_get_main_queue())
        {
            self.historyProgressBar.setProgress(0.8, animated: true)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            self.context.performBlockAndWait()
            {
                /// construct the request URL and start a task
                let songHistoryRequestString = self.endpoint + Routes.Songs + "/\(song.songID)"
                let songHistoryRequestURL = NSURL(string: songHistoryRequestString)!
                let songHistoryRequestTask = self.session.dataTaskWithURL(songHistoryRequestURL)
                {
                    songHistoryData, songHistoryResponse, songHistoryError in
                    
                    /// something went wrong
                    if songHistoryError != nil
                    {
                        completionHandler(songHistoryError: songHistoryError!)
                    }
                    else
                    {
                        do
                        {
                            /// turn the received data into a JSON object
                            let songHistoryResults = try NSJSONSerialization.JSONObjectWithData(songHistoryData!, options: []) as! [String : AnyObject]
                            
                            /// get the info for every instance of the song being played
                            let resultsData = songHistoryResults["data"] as! [String : AnyObject]
                            let tracks = resultsData["tracks"] as! [[String : AnyObject]]
                            
                            self.context.performBlockAndWait()
                            {
                                /// construct the history as arrays of performances keyed by year
                                for track in tracks
                                {
                                    /// get the show ID
                                    let showID = track["show_id"] as! Int
                                    
                                    /// get a nicely formatted date
                                    let date = track["show_date"] as! String
                                    let dateFormatter = NSDateFormatter()
                                    dateFormatter.dateFormat = "yyyy-MM-dd"
                                    let formattedDate = dateFormatter.dateFromString(date)!
                                    dateFormatter.dateFormat = "MMM dd,"
                                    let formattedString = dateFormatter.stringFromDate(formattedDate)
                                    
                                    /// get the year
                                    let datePieces = date.componentsSeparatedByString("-")
                                    let year = Int(datePieces[0])!
                                    
                                    let performanceDate = formattedString + " \(year)"
                                    
                                    /// create a new PhishShowPerformance
                                    let newPerformance = NSEntityDescription.insertNewObjectForEntityForName("PhishSongPerformance", inManagedObjectContext: self.context) as! PhishSongPerformance
                                    newPerformance.song = song
                                    newPerformance.showID = showID
                                    newPerformance.date = performanceDate
                                    newPerformance.year = NSNumber(integer: year)
                                }
                            }
                            
                            self.context.performBlockAndWait()
                            {
                                CoreDataStack.sharedInstance().saveContext()
                            }
                            
                            /// update the progress bar
                            dispatch_async(dispatch_get_main_queue())
                            {
                                self.historyProgressBar.setProgress(1.0, animated: true)
                            }
                            
                            completionHandler(songHistoryError: nil)
                        }
                        catch
                        {
                            print("There was an error requesting the history for \(song.name)")
                        }
                    }
                }
                songHistoryRequestTask.resume()
            }
        }
    }
    
    /// requests a specfic show given an ID
    func requestShowForID(id: Int, completionHandler: (showRequestError: NSError?, show: PhishShow?) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            /// construct the request URL
            let showRequestString = self.endpoint + Routes.Shows + "/\(id)"
            let showRequestURL = NSURL(string: showRequestString)!
            let showRequestTask = self.session.dataTaskWithURL(showRequestURL)
            {
                showRequestData, showRequestResponse, showRequestError in
                
                /// there was an error with the request
                if showRequestError != nil
                {
                    completionHandler(showRequestError: showRequestError!, show: nil)
                }
                else
                {
                    do
                    {
                        /// get the show data
                        let showResults = try NSJSONSerialization.JSONObjectWithData(showRequestData!, options: []) as! [String : AnyObject]
                        let showData = showResults["data"] as! [String : AnyObject]
                        
                        self.context.performBlockAndWait()
                        {
                            /// create a new show
                            let newShow = PhishShow(showInfoFromShow: showData)
                            
                            /// save new and updated objects to the context
                            CoreDataStack.sharedInstance().saveContext()
                            
                            /// return it through the completion handler
                            completionHandler(showRequestError: nil, show: newShow)
                        }
                    }
                    catch
                    {
                        print("There was an error with the show request.")
                    }
                }
            }
            showRequestTask.resume()
        }
    }
    
    func requestTourIDFromShowForID(id: Int, completionHandler: (tourIDRequestError: NSError?, tourID: NSNumber!) -> Void)
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
        {
            /// construct the request URL
            let showRequestString = self.endpoint + Routes.Shows + "/\(id)"
            let showRequestURL = NSURL(string: showRequestString)!
            let showRequestTask = self.session.dataTaskWithURL(showRequestURL)
            {
                showRequestData, showRequestResponse, showRequestError in
                
                /// something went wrong
                if showRequestError != nil
                {
                    completionHandler(tourIDRequestError: showRequestError!, tourID: nil)
                }
                else
                {
                    do
                    {
                        /// get the show data
                        let showResults = try NSJSONSerialization.JSONObjectWithData(showRequestData!, options: []) as! [String : AnyObject]
                        let showData = showResults["data"] as! [String : AnyObject]
                        
                        /// get the tour ID
                        let tourID = showData["tour_id"] as! Int
                        let nsNumberTourID = NSNumber(integer: tourID)
                        
                        /// return it
                        completionHandler(tourIDRequestError: nil, tourID: nsNumberTourID)
                    }
                    catch
                    {
                        print("There was an error requesting info for show \(id).")
                    }
                }
            }
            showRequestTask.resume()
        }
    }
}
