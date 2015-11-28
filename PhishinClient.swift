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
                        
                        /// create PhishYear objects for every year and bump the progress bar
                        var phishYears = [PhishYear]()
                        let progressBump: Float = 1.0 / 20.0
                        var totalProgress: Float = 0
                        for year in years
                        {
                            if let intYear = Int(year)
                            {
                                let newYear = PhishYear(year: intYear)
                                
                                phishYears.append(newYear)
                                
                                totalProgress += progressBump
                                dispatch_async(dispatch_get_main_queue())
                                {
                                    self.tourSelecterProgressBar.setProgress(totalProgress, animated: true)
                                }
                            }
                        }
                        
                        /// reverse the results so that the most recent tours and shows appear first in the list
                        phishYears.sortInPlace
                        {
                            year1, year2 in
                            
                            Int(year1.year) > Int(year2.year)
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
                        var showsForID = [Int : [PhishShow]]()
                        for show in showsForTheYear
                        {
                            /// create a new PhishShow
                            let newShow = PhishShow(showInfoFromYear: show)
                            
                            /// only append unique tour IDs
                            let tourID = show["tour_id"] as! Int
                            if !tourIDs.contains(tourID) && tourID != self.notPartOfATour
                            {
                                /// for every unique tour, create an array for its corresponding shows
                                tourIDs.append(tourID)
                                showsForID.updateValue([PhishShow](), forKey: tourID)
                            }
                            
                            /// append the show to the tour
                            showsForID[tourID]?.append(newShow)
                        }
                        
                        /// get the names of each tour
                        self.requestTourNamesForIDs(tourIDs, year: year, showsForID: showsForID)
                        {
                            tourNamesRequestError, tours in
                            
                            /// something went wrong
                            if tourNamesRequestError != nil
                            {
                                completionHandler(toursRequestError: tourNamesRequestError, tours: nil)
                            }
                            else
                            {
                                /// send the tours back through the completion handler
                                completionHandler(toursRequestError: nil, tours: tours)
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
    
    /// requests tour data for a given tour ID
    func requestTourForID(id: Int, completionHandler: (tourRequestError: NSError?, tour: PhishTour?) -> Void)
    {
        let tourRequestString = endpoint + Routes.Tours + "/\(id)"
        let tourRequestURL = NSURL(string: tourRequestString)!
        let tourRequestTask = session.dataTaskWithURL(tourRequestURL)
        {
            tourData, tourResponse, tourError in
            
            /// something went wrong
            if tourError != nil
            {
                completionHandler(tourRequestError: tourError!, tour: nil)
            }
            else
            {
                do
                {
                    let tourResults = try NSJSONSerialization.JSONObjectWithData(tourData!, options: []) as! [String : AnyObject]
                    let tourData = tourResults["data"] as! [String : AnyObject]
                    
                    /// get the tour name
                    let tourName = tourData["name"] as! String
                    
                    /// create the shows on the tour
                    let shows = tourData["shows"] as! [[String : AnyObject]]
                    var showArray = [PhishShow]()
                    for show in shows
                    {
                        // let newShow = PhishShow(showInfoFromYear: show)
                        let newShow = NSEntityDescription.insertNewObjectForEntityForName("PhishShow", inManagedObjectContext: self.context) as! PhishShow
                        newShow.updateProperties(showInfoFromYear: show)
                        
                        showArray.append(newShow)
                    }
                    
                    /// get a year to fetch a PhishYear with
                    let startDate = tourData["starts_on"] as! String
                    let intYear = Int(NSString(string: startDate).substringToIndex(4))!
                    let nsNumberYear = NSNumber(integer: intYear) 
                    let yearFetchRequest = NSFetchRequest(entityName: "PhishYear")
                    let yearFetchPredicate = NSPredicate(format: "%K == %@", "year", nsNumberYear)
                    yearFetchRequest.predicate = yearFetchPredicate
                    
                    self.context.performBlockAndWait()
                    {
                        do
                        {
                            /// fetch the specified year
                            let years = try self.context.executeFetchRequest(yearFetchRequest) as! [PhishYear]
                            if let year: PhishYear = years.first
                            {
                                print("year: \(year)")
                                PhishModel.sharedInstance().selectedYear = year
                            }
                            else
                            {
                                print("I dunno what happened with the fetched year...")
                            }
                            
                            /// create a tour and set relationships
                            // let newTour = PhishTour(year: PhishModel.sharedInstance().selectedYear!, name: tourName, tourID: id)
                            let newTour = NSEntityDescription.insertNewObjectForEntityForName("PhishTour", inManagedObjectContext: self.context) as! PhishTour
                            newTour.year = PhishModel.sharedInstance().selectedYear!
                            newTour.name = tourName
                            newTour.tourID = id
                            for show in showArray
                            {
                                show.tour = newTour
                            }
                            let _ = newTour.locationDictionary!
                            
                            /// save new and updated objects to the context
                            self.context.performBlockAndWait()
                            {
                                CoreDataStack.sharedInstance().saveContext()
                            }
                            
                            /// send the tour back through the completion handler
                            completionHandler(tourRequestError: nil, tour: newTour)
                        }
                        catch
                        {
                            print("Couldn't fetch \(intYear) from Core Data.")
                        }
                    }
                    
                }
                catch
                {
                    print("There was a problem requesting info for tour \(id)")
                }
            }
        }
        tourRequestTask.resume()
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
                        
                        /// create the new tour
                        let newTour = PhishTour(tourInfo: tourData)
                        
                        /// send the tour name back through the completion handler
                        completionHandler(tourNameRequestError: nil, tourName: newTour.name)
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
    func requestTourNamesForIDs(tourIDs: [Int], year: PhishYear, showsForID: [Int : [PhishShow]], completionHandler: (tourNamesRequestError: NSError!, tours: [PhishTour]!) -> Void)
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
                            
                            /// create a new tour, set the show/tour relationship, and create the location dictionary
                            let newTour = PhishTour(year: year, name: tourName, tourID: tourID)
                            let shows = showsForID[tourID]!
                            for show in shows
                            {
                                show.tour = newTour
                            }
                            let _ = newTour.locationDictionary!
                            
                            /// add the new tour to the array being sent back
                            tours.append(newTour)
                        }
                        catch
                        {
                            print("There was a problem processing the results for tour \(tourID).")
                        }
                    }
                    
                    /// sort the tours by ID
                    tours.sortInPlace()
                    {
                        tour1, tour2 in
                        
                        Int(tour1.tourID) < Int(tour2.tourID)
                    }
                    
                    /// return the tours through the completion handler
                    completionHandler(tourNamesRequestError: nil, tours: tours)
                }
                tourIDRequestTask.resume()
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
                            // let _ = PhishSong(songInfo: track, forShow: show)
                            let newSong = NSEntityDescription.insertNewObjectForEntityForName("PhishSong", inManagedObjectContext: self.context) as! PhishSong
                            newSong.updateProperties(track)
                            newSong.show = show
                            
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
    
    // new requestHistoryForSong, 11.27.2015
    func requestHistoryForSong(song: PhishSong, completionHandler: (songHistoryError: NSError?, songHistory: [Int : [PhishShow]]?) -> Void)
    {
        dispatch_async(dispatch_get_main_queue())
        {
            self.historyProgressBar.setProgress(0.8, animated: true)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
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
                    completionHandler(songHistoryError: songHistoryError!, songHistory: nil)
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
                        
                        /// the progress bar will update as each request is completed
                        var currentProgress: Float?
                        var progressBump: Float?
                        if let historyProgressBar = self.historyProgressBar
                        {
                            currentProgress = historyProgressBar.progress
                            progressBump = 0.2 / Float(tracks.count)
                        }
                        
                        /// the history will be arrays of shows keyed by the year the show took place in
                        var showsForTheYear = [PhishShow]()
                        var historyByYear = [Int : [PhishShow]]()
                        var currentYear: Int = 0
                        var previousYear: Int = 0
                        print("There are \(tracks.count) songs...")
                        for (index, track) in tracks.enumerate()
                        {
                            print("Processing track \(index + 1)...")
                            /// get the show id and request the show
                            let showID = track["show_id"] as! Int
                            
                            var fetchedShow: PhishShow?
                            let showFetchRequest = NSFetchRequest(entityName: "PhishShow")
                            let nsNumberID = NSNumber(integer: showID)
                            let showFetchPredicate = NSPredicate(format: "showID = %@", nsNumberID)
                            showFetchRequest.predicate = showFetchPredicate
                            
                            do
                            {
                                /// execute the fetch request
                                let shows = try self.context.executeFetchRequest(showFetchRequest) as! [PhishShow]
                                
                                /// make sure we got something from Core Data
                                if !shows.isEmpty
                                {
                                    /// get the show we're looking for
                                    fetchedShow = shows.first!
                                    
                                    showsForTheYear.append(fetchedShow!)
                                    currentYear = fetchedShow!.year.integerValue
                                    previousYear = currentYear
                                    if index == tracks.count - 1
                                    {
                                        /// sort the shows by date, descending
                                        showsForTheYear.sortInPlace()
                                        {
                                            show1, show2 in
                                            
                                            let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                            let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                            
                                            if show1TotalDays > show2TotalDays
                                            {
                                                return true
                                            }
                                            else
                                            {
                                                return false
                                            }
                                        }
                                        
                                        historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                        
                                        if currentProgress != nil
                                        {
                                            currentProgress! += progressBump!
                                            dispatch_async(dispatch_get_main_queue())
                                            {
                                                self.historyProgressBar.setProgress(currentProgress!, animated: true)
                                            }
                                        }
                                        
                                        historyByYear.removeValueForKey(0)
                                        
                                        /// set the history and save it
                                        song.history = historyByYear                        
                                        song.saveHistory()
                                        
                                        /// save new and updated objects to the context
                                        self.context.performBlockAndWait()
                                        {
                                            CoreDataStack.sharedInstance().saveContext()
                                        }
                                        
                                        /// send the history back through the completion handler
                                        completionHandler(songHistoryError: nil, songHistory: historyByYear)
                                        
                                        return
                                    }
                                    else
                                    {
                                        continue
                                    }
                                }
                            }
                            catch
                            {
                                print("Couldn't get show \(showID) from Core Data.")
                            }
                            
                            self.requestShowForID(showID)
                                // PhishModel.sharedInstance().getShowForID(showID)
                            {
                                showRequestError, show in
                                
                                /// something went wrong
                                if showRequestError != nil
                                {
                                    completionHandler(songHistoryError: showRequestError!, songHistory: nil)
                                }
                                else
                                {
                                    currentYear = show!.year.integerValue
                                    
                                    /// don't check that the first show has the same year as the previous year
                                    guard index != 0
                                    else
                                    {
                                        showsForTheYear.append(show!)
                                        
                                        previousYear = currentYear
                                        
                                        /// this might be the last show in the history
                                        if index == tracks.count - 1
                                        {
                                            /// sort the shows by date, descending
                                            showsForTheYear.sortInPlace()
                                            {
                                                show1, show2 in
                                                
                                                let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                                let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                                
                                                if show1TotalDays > show2TotalDays
                                                {
                                                    return true
                                                }
                                                else
                                                {
                                                    return false
                                                }
                                            }
                                            
                                            historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                            
                                            if currentProgress != nil
                                            {
                                                currentProgress! += progressBump!
                                                dispatch_async(dispatch_get_main_queue())
                                                {
                                                    self.historyProgressBar.setProgress(currentProgress!, animated: true)
                                                }
                                            }
                                            
                                            historyByYear.removeValueForKey(0)
                                            
                                            /// set the history and save it
                                            song.history = historyByYear                        
                                            song.saveHistory()
                                            
                                            /// save new and updated objects to the context
                                            self.context.performBlockAndWait()
                                            {
                                                CoreDataStack.sharedInstance().saveContext()
                                            }
                                            
                                            /// send the history back through the completion handler
                                            completionHandler(songHistoryError: nil, songHistory: historyByYear)
                                            
                                            return
                                        }
                                        
                                        return
                                    }
                                    
                                    /// if we're in the same year, add the show to the current array
                                    if currentYear == previousYear
                                    {
                                        showsForTheYear.append(show!)
                                        
                                        /// remember this show's year
                                        previousYear = currentYear
                                        
                                        /// if this is the last show in the history, update the dictionary
                                        if index == tracks.count - 1
                                        {
                                            showsForTheYear.sortInPlace()
                                            {
                                                show1, show2 in
                                                
                                                let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                                let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                                
                                                if show1TotalDays > show2TotalDays
                                                {
                                                    return true
                                                }
                                                else
                                                {
                                                    return false
                                                }
                                            }
                                            
                                            historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                            
                                            if currentProgress != nil
                                            {
                                                currentProgress! += progressBump!
                                                dispatch_async(dispatch_get_main_queue())
                                                {
                                                    self.historyProgressBar.setProgress(currentProgress!, animated: true)
                                                }
                                            }
                                            
                                            historyByYear.removeValueForKey(0)
                                            
                                            /// set the history and save it
                                            song.history = historyByYear                        
                                            song.saveHistory()
                                            
                                            /// save new and updated objects to the context
                                            self.context.performBlockAndWait()
                                            {
                                                CoreDataStack.sharedInstance().saveContext()
                                            }
                                            
                                            /// send the history back through the completion handler
                                            completionHandler(songHistoryError: nil, songHistory: historyByYear)
                                            
                                            return
                                        }
                                        
                                        return
                                    }
                                    /// we got to the next year
                                    else
                                    {
                                        showsForTheYear.sortInPlace()
                                        {
                                            show1, show2 in
                                            
                                            let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                            let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                            
                                            if show1TotalDays > show2TotalDays
                                            {
                                                return true
                                            }
                                            else
                                            {
                                                return false
                                            }
                                        }
                                        
                                        /// update the dictionary with last year's array of shows
                                        historyByYear.updateValue(showsForTheYear, forKey: previousYear)
                                        
                                        /// prepare the array for the new year by blanking it
                                        showsForTheYear.removeAll()
                                        
                                        /// then, add the current show as the first for the new year
                                        showsForTheYear.append(show!)
                                        
                                        // currentYear = show!.year.integerValue
                                        
                                        /// if this is the last show in the history, update the dictionary
                                        if index == tracks.count - 1
                                        {
                                            showsForTheYear.sortInPlace()
                                            {
                                                show1, show2 in
                                                
                                                let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                                let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                                
                                                if show1TotalDays > show2TotalDays
                                                {
                                                    return true
                                                }
                                                else
                                                {
                                                    return false
                                                }
                                            }
                                            
                                            historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                            
                                            if currentProgress != nil
                                            {
                                                currentProgress! += progressBump!
                                                dispatch_async(dispatch_get_main_queue())
                                                {
                                                    self.historyProgressBar.setProgress(currentProgress!, animated: true)
                                                }
                                            }
                                            
                                            historyByYear.removeValueForKey(0)
                                            
                                            /// set the history and save it
                                            song.history = historyByYear                        
                                            song.saveHistory()
                                            
                                            /// save new and updated objects to the context
                                            self.context.performBlockAndWait()
                                            {
                                                CoreDataStack.sharedInstance().saveContext()
                                            }
                                            
                                            /// send the history back through the completion handler
                                            completionHandler(songHistoryError: nil, songHistory: historyByYear)
                                            
                                            return
                                        }
                                        /// otherwise, remember the year for the next iteration
                                        else
                                        {
                                            previousYear = currentYear
                                            return
                                        }
                                    }
                                }
                            }
                        }
                        
                        /*
                        /// set the history and save it
                        song.history = historyByYear                        
                        song.saveHistory()
                        
                        /// save new and updated objects to the context
                        self.context.performBlockAndWait()
                        {
                            CoreDataStack.sharedInstance().saveContext()
                        }
                        
                        /// send the history back through the completion handler
                        completionHandler(songHistoryError: nil, songHistory: historyByYear)
                        */
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
    
    /*
    /// requests all the dates (as showIDs) a song was played on
    func requestHistoryForSong(song: PhishSong, completionHandler: (songHistoryError: NSError?, songHistory: [Int : [PhishShow]]?) -> Void)
    {
        dispatch_async(dispatch_get_main_queue())
        {
            self.historyProgressBar.setProgress(0.8, animated: true)
        }
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0))
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
                    completionHandler(songHistoryError: songHistoryError!, songHistory: nil)
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
                        
                        /// the progress bar will update as each request is completed
                        var currentProgress: Float?
                        var progressBump: Float?
                        if let historyProgressBar = self.historyProgressBar
                        {
                            currentProgress = historyProgressBar.progress
                            progressBump = 0.2 / Float(tracks.count)
                        }
                        
                        /// the history will be arrays of shows keyed by the year the show took place in
                        var showsForTheYear = [PhishShow]()
                        var historyByYear = [Int : [PhishShow]]()
                        var currentYear: Int = 0
                        var previousYear: Int = 0
                        for (index, track) in tracks.enumerate()
                        {
                            if currentProgress != nil
                            {
                                /// increment the progress bar
                                currentProgress! += progressBump!
                                dispatch_async(dispatch_get_main_queue())
                                {
                                    self.historyProgressBar.setProgress(currentProgress!, animated: true)
                                }
                            }
                            
                            /// get the show id and the date
                            let showID = track["show_id"] as! Int
                            let date = track["show_date"] as! String
                            
                            /// convert the date string (yyyy-dd-mm) into a year, day, and month
                            let year = Int(NSString(string: date).substringToIndex(4))!
                            currentYear = year
                            let monthRange = NSRange(5...6)
                            let month = Int(NSString(string: date).substringWithRange(monthRange))
                            let dayRange = NSRange(8...9)
                            let day = Int(NSString(string: date).substringWithRange(dayRange))
                            
                            /// don't check that the first show has the same year as the previous year
                            guard index != 0
                            else
                            {
                                // let newShow = PhishShow()
                                let newShow = NSEntityDescription.insertNewObjectForEntityForName("PhishShow", inManagedObjectContext: self.context) as! PhishShow
                                newShow.date = ""
                                newShow.year = 9999
                                newShow.venue = ""
                                newShow.city = ""
                                newShow.showID = 0
                                newShow.showID = showID
                                newShow.createDate(date)
                                newShow.day = day
                                newShow.month = month
                                newShow.year = currentYear
                                showsForTheYear.append(newShow)
                                previousYear = currentYear
                                
                                /// this might be the last show in the history
                                if index == tracks.count - 1
                                {
                                    /// sort the shows by date, descending
                                    showsForTheYear.sortInPlace()
                                    {
                                        show1, show2 in
                                        
                                        let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                        let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                        
                                        if show1TotalDays > show2TotalDays
                                        {
                                            return true
                                        }
                                        else
                                        {
                                            return false
                                        }
                                    }
                                    
                                    historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                }
                                
                                continue
                            }
                            
                            /// if we're in the same year, add the show to the current array
                            if currentYear == previousYear
                            {
                                // let newShow = PhishShow()
                                let newShow = NSEntityDescription.insertNewObjectForEntityForName("PhishShow", inManagedObjectContext: self.context) as! PhishShow
                                newShow.date = ""
                                newShow.year = 9999
                                newShow.venue = ""
                                newShow.city = ""
                                newShow.showID = 0
                                newShow.showID = showID
                                newShow.createDate(date)
                                newShow.day = day
                                newShow.month = month
                                newShow.year = currentYear
                                showsForTheYear.append(newShow)
                                
                                /// remember this show's year
                                previousYear = currentYear
                                
                                /// if this is the last show in the history, update the dictionary
                                if index == tracks.count - 1
                                {
                                    showsForTheYear.sortInPlace()
                                    {
                                        show1, show2 in
                                        
                                        let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                        let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                        
                                        if show1TotalDays > show2TotalDays
                                        {
                                            return true
                                        }
                                        else
                                        {
                                            return false
                                        }
                                    }
                                    
                                    historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                }
                                
                                continue
                            }
                            /// we got to the next year
                            else
                            {
                                showsForTheYear.sortInPlace()
                                {
                                    show1, show2 in
                                    
                                    let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                    let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                    
                                    if show1TotalDays > show2TotalDays
                                    {
                                        return true
                                    }
                                    else
                                    {
                                        return false
                                    }
                                }
                                
                                /// update the dictionary with last year's array of shows
                                historyByYear.updateValue(showsForTheYear, forKey: previousYear)
                                
                                /// prepare the array for the new year by blanking it
                                showsForTheYear.removeAll()
                                
                                /// create the new show and add it to the array for the new year
                                // let newShow = PhishShow()
                                let newShow = NSEntityDescription.insertNewObjectForEntityForName("PhishShow", inManagedObjectContext: self.context) as! PhishShow
                                newShow.date = ""
                                newShow.year = 9999
                                newShow.venue = ""
                                newShow.city = ""
                                newShow.showID = 0
                                newShow.showID = showID
                                newShow.createDate(date)
                                newShow.day = day
                                newShow.month = month
                                newShow.year = currentYear
                                showsForTheYear.append(newShow)
                                
                                /// if this is the last show in the history, update the dictionary
                                if index == tracks.count - 1
                                {
                                    showsForTheYear.sortInPlace()
                                    {
                                        show1, show2 in
                                        
                                        let show1TotalDays = (Int(show1.month!) * 31) + Int(show1.day!)
                                        let show2TotalDays = (Int(show2.month!) * 31) + Int(show2.day!)
                                        
                                        if show1TotalDays > show2TotalDays
                                        {
                                            return true
                                        }
                                        else
                                        {
                                            return false
                                        }
                                    }
                                    
                                    historyByYear.updateValue(showsForTheYear, forKey: currentYear)
                                }
                                /// otherwise, remember the year for the next iteration
                                else
                                {
                                    previousYear = currentYear
                                }
                            }
                        }
                        
                        /// set the history and save it
                        song.history = historyByYear                        
                        song.saveHistory()
                        
                        /// save new and updated objects to the context
                        self.context.performBlockAndWait()
                        {
                            CoreDataStack.sharedInstance().saveContext()
                        }
                        
                        /// send the history back through the completion handler
                        completionHandler(songHistoryError: nil, songHistory: historyByYear)
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
    */
    
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
                        
                        /// create a new show
                        let newShow = PhishShow(showInfoFromShow: showData)
                        print("requestShowForID: created this show: \(newShow)")
                        
                        /// save new and updated objects to the context
                        self.context.performBlockAndWait()
                        {
                            CoreDataStack.sharedInstance().saveContext()
                        }
                        
                        /// return it through the completion handler
                        completionHandler(showRequestError: nil, show: newShow)
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
    
    func requestTourIDFromShowForID(id: Int, completionHandler: (tourIDRequestError: NSError?, tourID: Int!) -> Void)
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
                        
                        /// return it
                        completionHandler(tourIDRequestError: nil, tourID: tourID)
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
