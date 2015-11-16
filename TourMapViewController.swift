//
//  ViewController.swift
//  new phishtour navbar test
//
//  Created by Aaron Justman on 10/26/15.
//  Copyright © 2015 AaronJ. All rights reserved.
//

import UIKit
import MapKit

class TourMapViewController: UIViewController,
    TourNavControlsDelegate, MKMapViewDelegate, CalloutCellDelegate, TourListCellDelegate
{
    var tourMap: MKMapView!
    
    // impermanent UI elements
    var tourSelecter: UIVisualEffectView?
    var tourNavControls: TourNavControls?
    var tourTitleLabel: UILabel?
    var tourList: UIVisualEffectView?
    var progressBar: UIProgressView?
    
    // nav bar buttons
    var resetButton: UIButton!
    var selectTourButton: UIButton!
    
    // the region to reset the map to
    let defaultRegion = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.8282, longitude: -98.5795), span: MKCoordinateSpan(latitudeDelta: 50.0, longitudeDelta: 50.0))
    
    // the pin callout that is currently showing
    var currentCallout: SMCalloutView?
    
    // use this to prevent the map from dismissing the callout when it sets a new center on the selected annotation
    var didSelectAnnotationView: Bool = false
    
    // flag to indicate the map is being reloaded from the song history
    var isComingFromSongHistory: Bool = false
    var didComeFromSongHistory: Bool = false
    
    /// prevent the reset button from being active on app-re-launch
    var didReset: Bool = false
    
    // MARK: Setup methods
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        // UIApplication.sharedApplication().statusBarStyle = .LightContent
        // self.restorationIdentifier = "TourMapViewController"
        setupNavBar()
        addMap()
    }
    
    override func viewWillAppear(animated: Bool)
    {
        setupNavBar()
        
        // if a show/tour was selected from the song history, reset the map, and show the tour
        if self.isComingFromSongHistory
        {
            self.isComingFromSongHistory = false
            self.didComeFromSongHistory = true
            self.reset(true)
            self.followTour()
        }
        else
        {
            if let previousSetlistSettings = NSUserDefaults.standardUserDefaults().objectForKey("previousSetlistSettings")
            {
                // self.shouldGoToSetlist = true
                if let previousShowIDData = previousSetlistSettings["previousShow"] as? NSData
                {
                    print("Got the setlist from NSUserDefaults...")
                    let previousShowID = NSKeyedUnarchiver.unarchiveObjectWithData(previousShowIDData) as! Int
                    let documentsPath: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
                    let documentsURL = NSURL(string: documentsPath)!
                    let filename = "show\(previousShowID)"
                    let fileURL = documentsURL.URLByAppendingPathComponent(filename)
                    let savedShow = NSKeyedUnarchiver.unarchiveObjectWithFile(fileURL.path!) as! PhishShow
                    
                    let setlistViewController = SetlistViewController()
                    setlistViewController.show = savedShow
                    setlistViewController.isRelaunchingApp = true
                    self.showViewController(setlistViewController, sender: self)
                }
            }
            
            if let previousSettings = NSUserDefaults.standardUserDefaults().objectForKey("previousSettings")
            {
                print("Got the previous settings!!!")
                if let previousYearData = previousSettings["previousYear"] as? NSData
                {
                    let previousYear = NSKeyedUnarchiver.unarchiveObjectWithData(previousYearData) as! Int
                    print("previousYear: \(previousYear)")
                    PhishModel.sharedInstance().previousYear = previousYear
                    print("Set previousYear!!!")
                }
                
                print("Checking previousTourData...")
                if let previousTourData = previousSettings["previousTour"] as? NSData
                {
                    let previousTour = NSKeyedUnarchiver.unarchiveObjectWithData(previousTourData) as! Int
                    print("previousTour: \(previousTour)")
                    PhishModel.sharedInstance().previousTour = previousTour
                }
                
                if let selectedTourIDData = previousSettings["selectedTourID"] as? NSData
                {                
                    let selectedTourID = NSKeyedUnarchiver.unarchiveObjectWithData(selectedTourIDData) as! Int
                    print("selectedTour: \(selectedTourID)")
                    
                    let documentsPath: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
                    let documentsURL = NSURL(string: documentsPath)!
                    let filename = "tour\(selectedTourID)"
                    let fileURL = documentsURL.URLByAppendingPathComponent(filename)
                    let savedTour = NSKeyedUnarchiver.unarchiveObjectWithFile(fileURL.path!) as! PhishTour
                    PhishModel.sharedInstance().selectedTour = savedTour
                }
                
                /// reload the previously selected tour, but do nothing if the app was shut down after a map reset
                if let _ = previousSettings["didReset"] as? Bool
                {
                    
                }
                else
                {
                    self.followTour()
                }
            }
        }
    }
    
//    override func viewDidAppear(animated: Bool)
//    {
//        if self.shouldGoToSetlist
//        {
//            let previousSetlistSettings = NSUserDefaults.standardUserDefaults().objectForKey("previousSetlistSettings")!
//            
//            if let previousShowIDData = previousSetlistSettings["previousShow"] as? NSData
//            {
//                print("Got the setlist from NSUserDefaults...")
//                let previousShowID = NSKeyedUnarchiver.unarchiveObjectWithData(previousShowIDData) as! Int
//                let documentsPath: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
//                let documentsURL = NSURL(string: documentsPath)!
//                let filename = "show\(previousShowID)"
//                let fileURL = documentsURL.URLByAppendingPathComponent(filename)
//                let savedShow = NSKeyedUnarchiver.unarchiveObjectWithFile(fileURL.path!) as! PhishShow
//                
//                let setlistViewController = SetlistViewController()
//                setlistViewController.show = savedShow
//                setlistViewController.isRelaunchingApp = true
//                self.showViewController(setlistViewController, sender: self)
//            }
//        }
//    }
    
    func setupNavBar()
    {
        // create a reset button for the navigation bar
        let resetButton = UIButton()
        resetButton.titleLabel?.font = UIFont(name: "AppleSDGothicNeo-SemiBold", size: 16)
        let resetButtonColor: UIColor = (PhishModel.sharedInstance().selectedTour == nil) ? UIColor.lightGrayColor() : UIColor.whiteColor()
        resetButton.setTitleColor(resetButtonColor, forState: .Normal)
        resetButton.setTitle("Reset", forState: .Normal)
        resetButton.sizeToFit()
        resetButton.addTarget(self, action: "reset:", forControlEvents: .TouchUpInside)
        resetButton.enabled = (PhishModel.sharedInstance().selectedTour == nil) ? false : true
        let navResetButton = UIBarButtonItem(customView: resetButton)
        
        // the select tour button
        let selectTourButton = UIButton()
        selectTourButton.titleLabel?.font = UIFont(name: "AppleSDGothicNeo-SemiBold", size: 16)
        selectTourButton.setTitle("Select Tour", forState: .Normal)
        selectTourButton.sizeToFit()
        selectTourButton.addTarget(self, action: "showTourSelecter", forControlEvents: .TouchUpInside)
        let navSelectTourButton = UIBarButtonItem(customView: selectTourButton)
        
        // keep references to the buttons to manipulate them later
        self.resetButton = resetButton
        self.selectTourButton = selectTourButton
        
        let navBarTitle = UILabel()
        navBarTitle.font = UIFont(name: "AppleSDGothicNeo-Bold", size: 20)
        navBarTitle.textColor = UIColor.whiteColor()
        navBarTitle.text = "PhishTour"
        navBarTitle.sizeToFit()
        
        self.navigationItem.leftBarButtonItem = navResetButton
        self.navigationItem.titleView = navBarTitle
        self.navigationItem.rightBarButtonItem = navSelectTourButton
        
        self.navigationController?.navigationBar.barTintColor = UIColor.orangeColor()
    }
    
    func addMap()
    {
        self.tourMap = MKMapView(frame: CGRect(x: CGRectGetMinX(self.view.bounds), y: self.navigationController!.navigationBar.bounds.height, width: self.view.bounds.width, height: self.view.bounds.height))
        self.tourMap.delegate = self
        
        self.view.addSubview(tourMap)
        
        PhishModel.sharedInstance().tourMap = self.tourMap
        PhishModel.sharedInstance().tourMapVC = self
    }
    
    func saveToUserDefaults()
    {
        var previousSettings = [String : AnyObject]()
        
        if let previousYear = PhishModel.sharedInstance().previousYear
        {
            print("Saving \(previousYear) to the NSUserDefaults...")
            let previousYearData: NSData = NSKeyedArchiver.archivedDataWithRootObject(previousYear)
            previousSettings.updateValue(previousYearData, forKey: "previousYear")
        }
        if let previousTour = PhishModel.sharedInstance().previousTour
        {
            print("Saving \(previousTour) to the NSUserDefaults...")
            let previousTourData: NSData = NSKeyedArchiver.archivedDataWithRootObject(previousTour)
            previousSettings.updateValue(previousTourData, forKey: "previousTour")
        }
        /*
        if let currentTours = PhishModel.sharedInstance().currentTours
        {
            let currentToursData: NSData = NSKeyedArchiver.archivedDataWithRootObject(currentTours)
            previousSettings.updateValue(currentToursData, forKey: "currentTours")
        }
        */
        if let selectedTour = PhishModel.sharedInstance().selectedTour
        {
            let selectedTourID: Int = selectedTour.tourID
            let selectedTourIDData: NSData = NSKeyedArchiver.archivedDataWithRootObject(selectedTourID)
            previousSettings.updateValue(selectedTourIDData, forKey: "selectedTourID")
        }
        
        if self.didReset
        {
            previousSettings.updateValue(self.didReset, forKey: "didReset")
        }
        
        
        NSUserDefaults.standardUserDefaults().setObject(previousSettings, forKey: "previousSettings")
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    // MARK: UI methods
    
    func showTourSelecter()
    {
        /// change the "select tour" button to "cancel"
        self.selectTourButton.setTitleColor(UIColor.redColor(), forState: .Normal)
        self.selectTourButton.setTitle("Cancel", forState: .Normal)
        
        /// create the tour selecter
        if self.tourSelecter == nil
        {
            self.tourSelecter = UIVisualEffectView(effect: UIBlurEffect(style: .Light))
            self.tourSelecter?.frame = CGRect(x: CGRectGetMinX(self.view.bounds), y: self.navigationController!.navigationBar.bounds.height, width: self.view.bounds.width, height: self.view.bounds.height)
            
            let yearPicker = UIPickerView()
            yearPicker.tag = 201
            yearPicker.frame = CGRect(x: CGRectGetMidX(self.tourSelecter!.contentView.bounds) - (yearPicker.bounds.width / 2), y: CGRectGetMinY(self.tourSelecter!.contentView.bounds) + 25, width: yearPicker.bounds.width, height: yearPicker.bounds.height)
            yearPicker.dataSource = PhishModel.sharedInstance()
            yearPicker.delegate = PhishModel.sharedInstance()
            
            let tourPicker = UIPickerView()
            tourPicker.tag = 202
            tourPicker.frame = CGRect(x: CGRectGetMidX(self.tourSelecter!.contentView.bounds) - (tourPicker.bounds.width / 2), y: yearPicker.bounds.height + 25, width: tourPicker.bounds.width, height: tourPicker.bounds.height)
            tourPicker.dataSource = PhishModel.sharedInstance()
            tourPicker.delegate = PhishModel.sharedInstance()
            
            let followTourButton = UIButton()
            followTourButton.titleLabel?.font = UIFont(name: "AppleSDGothicNeo-Bold", size: 16)
            followTourButton.setTitleColor(UIColor.orangeColor(), forState: .Normal)
            followTourButton.setTitle("Follow Tour", forState: .Normal)
            followTourButton.sizeToFit()
            
            /// find the middle of the area between the bottom of the tour picker and the bottom of the screen
            let buttonSpace: CGFloat = self.tourSelecter!.contentView.bounds.height - (tourPicker.frame.origin.y + tourPicker.bounds.height)
            followTourButton.frame = CGRect(x: CGRectGetMidX(self.tourSelecter!.contentView.bounds) - (followTourButton.bounds.width / 2), y: (tourPicker.frame.origin.y + tourPicker.bounds.height) + (buttonSpace / 2) - followTourButton.bounds.height, width: followTourButton.bounds.width, height: followTourButton.bounds.height)
            followTourButton.addTarget(self, action: "followTour", forControlEvents: .TouchUpInside)
            
            self.tourSelecter!.contentView.addSubview(yearPicker)
            self.tourSelecter!.contentView.addSubview(tourPicker)
            self.tourSelecter!.contentView.addSubview(followTourButton)
            
            /// create a progress bar to track the progress of the years and tours requests
            /// give the PhishinClient a reference to the progress bar, so it can update the bar as it does its thing
            let progressBar = UIProgressView(progressViewStyle: .Default)
            progressBar.frame = CGRect(x: CGRectGetMinX(self.view.bounds), y: CGRectGetMinY(self.tourSelecter!.contentView.bounds) + UIApplication.sharedApplication().statusBarFrame.height + self.navigationController!.navigationBar.bounds.height - 41, width: CGRectGetWidth(self.view.bounds), height: 10)
            progressBar.progressTintColor = UIColor.orangeColor()
            progressBar.trackTintColor = UIColor.lightGrayColor()
            progressBar.transform = CGAffineTransformMakeScale(1, 2.5)
            self.progressBar = progressBar
            PhishinClient.sharedInstance().tourSelecterProgressBar = self.progressBar
            self.tourSelecter!.contentView.addSubview(progressBar)
            
            /// get the years from the model
            PhishModel.sharedInstance().getYears()
            {
                yearsError in
                
                /// someting went wrong
                if yearsError != nil
                {
                    /// create an alert for the problem and dismiss the tour selecter
                    let alert = UIAlertController(title: "Whoops!", message: "\(yearsError!.localizedDescription)", preferredStyle: .Alert)
                    let alertAction = UIAlertAction(title: "OK", style: .Default)
                    {
                        action in
                        
                        // revert the "select tour" button
                        self.selectTourButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
                        self.selectTourButton.setTitle("Select Tour", forState: .Normal)
                        
                        self.tourSelecter?.removeFromSuperview()
                        self.tourSelecter = nil
                    }
                    alert.addAction(alertAction)
                    
                    dispatch_async(dispatch_get_main_queue())
                    {
                        self.presentViewController(alert, animated: true, completion: nil)
                    }
                }
                else
                {
                    var reloadYear: PhishYear?
                    
                    dispatch_async(dispatch_get_main_queue())
                    {
                        yearPicker.reloadAllComponents()
                        
                        /// set the picker to whatever it was at the last time
                        if let previousYear = PhishModel.sharedInstance().previousYear
                        {
                            reloadYear = PhishModel.sharedInstance().years![previousYear]
                            print("Reloading \(reloadYear!.year)")
                            
                            yearPicker.selectRow(previousYear, inComponent: 0, animated: false)
                        }
                        
                        // get the tours for the most current year, or whichever year was previously selected
                        let yearToGet: PhishYear = (reloadYear != nil) ? reloadYear! : PhishModel.sharedInstance().years!.first!
                        print("Getting tours for \(yearToGet.year)")
                        PhishModel.sharedInstance().getToursForYear(yearToGet)
                        {
                            toursError, tours in
                            
                            if toursError != nil
                            {
                                /// create an alert for the problem and dismiss the tour selecter
                                let alert = UIAlertController(title: "Whoops!", message: "There was an error requesting the tours for \(yearToGet.year): \(toursError!.localizedDescription)", preferredStyle: .Alert)
                                let alertAction = UIAlertAction(title: "OK", style: .Default)
                                {
                                    action in
                                    
                                    // revert the "select tour" button
                                    self.selectTourButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
                                    self.selectTourButton.setTitle("Select Tour", forState: .Normal)
                                    
                                    self.tourSelecter?.removeFromSuperview()
                                    self.tourSelecter = nil
                                }
                                alert.addAction(alertAction)
                                
                                dispatch_async(dispatch_get_main_queue())
                                {
                                    self.presentViewController(alert, animated: true, completion: nil)
                                }
                            }
                            else
                            {
                                dispatch_async(dispatch_get_main_queue())
                                {
                                    tourPicker.reloadAllComponents()
                                    
                                    if let previousTour = PhishModel.sharedInstance().previousTour
                                    {
                                        print("Selecting the previous tour: \(previousTour)")
                                        tourPicker.selectRow(previousTour, inComponent: 0, animated: false)
                                        
                                        PhishModel.sharedInstance().selectedTour = tours![previousTour] // PhishModel.sharedInstance().currentTours![previousTour]
                                        // PhishModel.sharedInstance().previousTour = 0
                                    }
                                    else
                                    {
                                        print("There wasn't a previously selected tour!!!")
                                        PhishModel.sharedInstance().selectedTour = PhishModel.sharedInstance().currentTours!.first!
                                        PhishModel.sharedInstance().previousTour = 0
                                    }
                                }
                                
                                
                                
                                // self.saveToUserDefaults()
                                
                                
                                
                                /// make the progress bar green when it finishes successfully
                                /// then, remove it after a short delay
                                dispatch_async(dispatch_get_main_queue())
                                {
                                    self.progressBar?.progressTintColor = UIColor.greenColor()
                                    
                                    let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.5 * Double(NSEC_PER_SEC)))
                                    dispatch_after(delayTime, dispatch_get_main_queue())
                                    {
                                        self.progressBar?.removeFromSuperview()
                                        self.progressBar = nil
                                    }
                                }
                            }
                        }
                    }
                    
                    
                }
            }
            
            self.view.addSubview(tourSelecter!)
        }
        // dismiss the tour selecter
        else
        {
            // revert the "select tour" button
            self.selectTourButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
            self.selectTourButton.setTitle("Select Tour", forState: .Normal)
            
            self.tourSelecter?.removeFromSuperview()
            self.tourSelecter = nil
        }
    }
    
    func showTourNavControls()
    {
        // create the tour nav controls
        if self.tourNavControls == nil
        {
            self.tourNavControls = TourNavControls(parentView: self.view)
            self.tourNavControls?.delegate = self
            
            // add the buttons to the view
            self.tourNavControls?.addButtons()
        }
        // dismiss the tour nav controls
        else
        {
            self.tourNavControls?.removeButtons()
            self.tourNavControls = nil
        }
    }
    
    // MARK: Map methods
    
    func reset(saveTour: Bool = false)
    {
        // disable the "reset" button
        self.resetButton.setTitleColor(UIColor.lightGrayColor(), forState: .Normal)
        self.resetButton.enabled = false
        
        // blank the selected tour
        if !saveTour
        {
            PhishModel.sharedInstance().selectedTour = nil
            PhishModel.sharedInstance().previousTour = nil
            PhishModel.sharedInstance().previousYear = nil
            self.didReset = true
            self.saveToUserDefaults()
        }
        
        // dismiss the tour selecter
        if self.tourSelecter != nil
        {
            self.showTourSelecter()
        }
        
        // dismiss the tour title
        if self.tourTitleLabel != nil
        {
            self.showTourTitle()
        }
        
        // dismiss the tour nav controls
        if self.tourNavControls != nil
        {
            self.showTourNavControls()
        }
        
        // dismiss the tour list
        if self.tourList != nil
        {
            self.didPressListButton()
        }
        
        // dismiss the info pane
        
        // reset the map
        if tourMap.annotations.count > 0
        {
            tourMap.removeAnnotations(tourMap.annotations)
            tourMap.removeOverlays(tourMap.overlays)
        }
        if self.currentCallout != nil
        {
            self.currentCallout = nil
        }
        
        // put the map back at the default region
        tourMap.setRegion(self.defaultRegion, animated: true)
    }
    
    func followTour()
    {
        // reset everything
        self.reset(true)
        
        // enable the "reset" button
        self.resetButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
        self.resetButton.enabled = true
        
        // make sure we've got a tour selected
        guard let selectedTour = PhishModel.sharedInstance().selectedTour
        else
        {
            print("A tour hasn't been selected!!!")
            
            return
        }
        
        /// create a progress bar to track the progress of the location geocoding
        /// give the MapquestClient a reference to the progress bar, so it can update the bar as it does its thing
        let progressBar = UIProgressView(progressViewStyle: .Default)
        progressBar.frame = CGRect(x: CGRectGetMinX(self.view.bounds), y: CGRectGetMinY(self.view.bounds) + UIApplication.sharedApplication().statusBarFrame.height + self.navigationController!.navigationBar.bounds.height, width: CGRectGetWidth(self.view.bounds), height: 10)
        progressBar.progressTintColor = UIColor.blueColor()
        progressBar.trackTintColor = UIColor.lightGrayColor()
        progressBar.transform = CGAffineTransformMakeScale(1, 2.5)
        self.progressBar = progressBar
        MapquestClient.sharedInstance().tourMapProgressBar = self.progressBar
        self.view.addSubview(progressBar)
        
        /// geocode the show locations before dropping the pins
        MapquestClient.sharedInstance().geocodeShowsForTour(selectedTour, withType: .Batch)
        {
            geocodingError in
            
            /// something went wrong
            if geocodingError != nil
            {
                /// create an alert for the problem
                let alert = UIAlertController(title: "Whoops!", message: "There was an error getting info for the \(selectedTour.name): \(geocodingError!.localizedDescription)", preferredStyle: .Alert)
                let alertAction = UIAlertAction(title: "OK", style: .Default)
                {
                    action in
                    
                    /// set the tour selecter to display the previous successfully requested year and its tours
                    PhishModel.sharedInstance().selectedYear = PhishModel.sharedInstance().years![PhishModel.sharedInstance().previousYear!]
                    PhishModel.sharedInstance().currentTours = PhishModel.sharedInstance().selectedYear!.tours
                    
                    /// reset the flag
                    self.didComeFromSongHistory = false
                    
                    /// reset the map, flash the progress bar red, then, remove it after a short delay
                    dispatch_async(dispatch_get_main_queue())
                    {
                        self.reset()
                        
                        self.progressBar?.progressTintColor = UIColor.redColor()
                        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.5 * Double(NSEC_PER_SEC)))
                        dispatch_after(delayTime, dispatch_get_main_queue())
                        {
                            self.progressBar?.removeFromSuperview()
                            self.progressBar = nil
                        }
                    }
                }
                alert.addAction(alertAction)
                
                dispatch_async(dispatch_get_main_queue())
                {
                    self.presentViewController(alert, animated: true, completion: nil)
                }
            }
            else
            {
                dispatch_async(dispatch_get_main_queue())
                {
                    /// make the progress bar green when it finishes successfully
                    /// then, remove it after a short delay
                    self.progressBar?.progressTintColor = UIColor.greenColor()
                    dispatch_async(dispatch_get_main_queue())
                    {
                        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.5 * Double(NSEC_PER_SEC)))
                        dispatch_after(delayTime, dispatch_get_main_queue())
                        {
                            self.progressBar?.removeFromSuperview()
                            self.progressBar = nil
                        }
                    }
                    
                    // show the tour title
                    self.showTourTitle()
                    
                    // center the map on the first show
                    self.centerOnFirstShow()
                    
                    // drop the pins on the map after a short delay
                    // NOTE: dispatch_after trick cribbed from http://stackoverflow.com/a/24034838
                    let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(2 * Double(NSEC_PER_SEC)))
                    dispatch_after(delayTime, dispatch_get_main_queue())
                    {
                        self.tourMap.addAnnotations(selectedTour.uniqueLocations!)
                        
                        // if a show was selected from the song history, select the annotation associated with the show,
                        // so the callout will be presented
                        if self.didComeFromSongHistory
                        {
                            let venue = PhishModel.sharedInstance().currentShow!.venue
                            let locations = PhishModel.sharedInstance().selectedTour!.locationDictionary[venue]
                            let show = locations!.first!
                            
                            self.tourMap.selectAnnotation(show, animated: true)
                            self.didComeFromSongHistory = false
                        }
                    }
                                        
                    // show the tour nav controls, if they aren't already up
                    if self.tourNavControls == nil
                    {
                        self.showTourNavControls()
                    }
                }
                
                /// reset the flag if the app was re-launched after a map reset
                if self.didReset
                {
                    self.didReset = false
                }
                
                self.saveToUserDefaults()
            }
        }
    }
    
    func showTourTitle()
    {
        // remove the old label is one is already onscreen
        if self.tourTitleLabel != nil
        {
            self.tourTitleLabel?.removeFromSuperview()
            
            self.tourTitleLabel = nil
        }
        
        // make sure a tour is selected
        guard let selectedTour = PhishModel.sharedInstance().selectedTour
        else
        {
            print("A tour wasn't selected.")
            
            return
        }
        
        // create the label with the name of the selected tour
        self.tourTitleLabel = UILabel()
        self.tourTitleLabel!.backgroundColor = UIColor.orangeColor()
        self.tourTitleLabel!.font = UIFont(name: "AppleSDGothicNeo-Bold", size: 16)
        self.tourTitleLabel!.textColor = UIColor.whiteColor()
        self.tourTitleLabel!.textAlignment = .Center
        self.tourTitleLabel!.text = selectedTour.name
        
        // center the label at the top of the screen
        self.tourTitleLabel!.sizeToFit()
        self.tourTitleLabel!.frame.size.width += 20
        self.tourTitleLabel!.frame.origin = CGPoint(x: CGRectGetMidX(view.bounds) - (self.tourTitleLabel!.bounds.width / 2), y: UIApplication.sharedApplication().statusBarFrame.size.height + self.navigationController!.navigationBar.bounds.height)
        
        // add the label to the view
        view.addSubview(self.tourTitleLabel!)
    }
    
    func centerOnFirstShow()
    {
        // make sure a tour is selected
        guard let selectedTour = PhishModel.sharedInstance().selectedTour
        else
        {
            print("A tour wasn't selected.")
            
            return
        }
        
        var firstShowRegion: MKCoordinateRegion
        if self.isComingFromSongHistory
        {
            firstShowRegion = MKCoordinateRegion(center: PhishModel.sharedInstance().currentShow!.coordinate, span: MKCoordinateSpan(latitudeDelta: 50.0, longitudeDelta: 50.0))
        }
        else
        {
            // set the map to be centered on the first show of the tour and zoomed far out
            firstShowRegion = MKCoordinateRegion(center: selectedTour.showCoordinates.first!, span: MKCoordinateSpan(latitudeDelta: 50.0, longitudeDelta: 50.0))
        }
        
        tourMap.setRegion(firstShowRegion, animated: true)
    }
    
    func makeTourTrail()
    {
        // make sure a tour is selected
        guard let selectedTour = PhishModel.sharedInstance().selectedTour
        else
        {
            print("A tour wasn't selected.")
            
            return
        }
        
        // get the coordinates for every location on the tour
        var showCoordinates = [CLLocationCoordinate2D]()
        for index in selectedTour.showCoordinates.indices
        {
            showCoordinates.append(selectedTour.showCoordinates[index])
        }
        
        dispatch_async(dispatch_get_main_queue())
        {
            // draw the trail between every coordinate
            let tourTrail = MKPolyline(coordinates: &showCoordinates, count: showCoordinates.count)
            self.tourMap.addOverlay(tourTrail)
        }
    }
    
    // MARK: MKMapViewDelegate methods
    
    // controls the look of the tour "trail"
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer
    {
        let trail = overlay as! MKPolyline
        let trailRenderer = MKPolylineRenderer(polyline: trail)
        
        trailRenderer.strokeColor = UIColor.blueColor()
        trailRenderer.lineWidth = 2
        
        return trailRenderer
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView?
    {
        // cast the annotation to a PhishShow to get at the consecutiveNights property
        let theShow = annotation as! PhishShow
        
        // re-use an annotation view, if possible
        if let reusedAnnotationView = mapView.dequeueReusableAnnotationViewWithIdentifier("mapPin") as? MKPinAnnotationView
        {
            // remove the number image view it came with
            // (the annotation view being re-used might not be the same one that was associated with the annotation last time)
            if let previousNumberImageView = reusedAnnotationView.viewWithTag(5)
            {
                previousNumberImageView.removeFromSuperview()
            }
            
            reusedAnnotationView.annotation = theShow
            
            // add a new number image view with the correct number
            let numberImageView = UIImageView(image: UIImage(named: "\(theShow.consecutiveNights)"))
            numberImageView.frame = CGRect(x: CGRectGetMidX(reusedAnnotationView.bounds) - (numberImageView.frame.size.width / 2) - 1, y: CGRectGetMaxY(reusedAnnotationView.bounds) - (numberImageView.frame.size.height), width: numberImageView.frame.size.width, height: numberImageView.frame.size.height)
            numberImageView.tag = 5
            reusedAnnotationView.addSubview(numberImageView)
            
            reusedAnnotationView.pinTintColor = UIColor.orangeColor()
            
            return reusedAnnotationView
        }
        else
        {
            let newAnnotationView = MKPinAnnotationView(annotation: theShow, reuseIdentifier: "mapPin")
            
            // use the consecutiveNights to add a number to the pin indicating the number of nights played at that location
            let numberImageView = UIImageView(image: UIImage(named: "\(theShow.consecutiveNights)"))
            numberImageView.frame = CGRect(x: CGRectGetMidX(newAnnotationView.bounds) - (numberImageView.frame.size.width / 2) - 1, y: CGRectGetMaxY(newAnnotationView.bounds) - (numberImageView.frame.size.height), width: numberImageView.frame.size.width, height: numberImageView.frame.size.height)
            numberImageView.tag = 5
            newAnnotationView.addSubview(numberImageView)
            
            newAnnotationView.pinTintColor = UIColor.orangeColor()
            newAnnotationView.animatesDrop = true
            newAnnotationView.canShowCallout = false
            
            return newAnnotationView
        }
    }
    
    func mapView(mapView: MKMapView, didSelectAnnotationView view: MKAnnotationView)
    {        
        // if another callout if showing, dismiss it first
        if self.currentCallout != nil
        {
            self.currentCallout?.dismissCalloutAnimated(true)
            self.currentCallout = nil
        }
        
        self.didSelectAnnotationView = true
        
        // set the selected show
        let selectedLocation = view.annotation as! PhishShow
        PhishModel.sharedInstance().currentShow = selectedLocation
        
        // create a container view to hold the callout cells
        let callout = CalloutCellView()
        
        // create a callout cell for every show at the location
        let venue = PhishModel.sharedInstance().currentShow!.venue
        print("selectedTour: \(PhishModel.sharedInstance().selectedTour!)")
        let showsAtVenue = PhishModel.sharedInstance().selectedTour!.locationDictionary[venue]!
        var showCells = [CalloutCell]()
        for (index, show) in showsAtVenue.enumerate()
        {
            let showCell = CalloutCell()
            
            // set the relevant info for each show
            showCell.dateLabel.text = show.date
            showCell.yearLabel.text = show.year.description
            showCell.venueLabel.text = show.venue + ", "
            showCell.cityLabel.text = show.city
            showCell.cellNumber = index
            showCell.show = show
            
            // set the delegate
            showCell.delegate = self
            
            // set the background color of the cell
            showCell.setBackgroundColor()
            
            // place all the cell views
            showCell.layoutSubviews()
            
            // add the new cell to an array of all the cells that are going to be added to the container view
            showCells.append(showCell)
        }
        
        // add all the cells to the container view
        callout.addCells(showCells)
        
        // create the custom callout view
        let calloutView = SMCalloutView()
        
        // set the current callout
        self.currentCallout = calloutView
        
        // the content of the callout view is the container view that holds all the cells for each show
        calloutView.contentView = callout
        
        // set the SMCalloutView's arrow image to be the same as the background color of the last cell in the callout
        let bgView: SMCalloutMaskedBackgroundView = calloutView.backgroundView as! SMCalloutMaskedBackgroundView
        let lastCell = callout.subviews.last as! CalloutCell
        bgView.arrowImageColor(lastCell.backgroundColor!)
        
        // present the callout from the middle of the screen;
        // set map center to the annotation coordinate
        let viewPosition = mapView.convertCoordinate(self.tourMap.centerCoordinate, toPointToView: mapView)
        self.tourMap.setCenterCoordinate(selectedLocation.coordinate, animated: true)
        
        // present the custom callout after a short delay
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(0.5 * Double(NSEC_PER_SEC)))
        dispatch_after(delayTime, dispatch_get_main_queue())
        {
            calloutView.presentCalloutFromRect(CGRect(x: viewPosition.x, y: viewPosition.y - 40, width: calloutView.frame.size.width, height: calloutView.frame.size.height), inView: self.tourMap, constrainedToView: self.tourMap, animated: true)
        }
        
        self.didSelectAnnotationView = false
    }
    
    func mapView(mapView: MKMapView, didDeselectAnnotationView view: MKAnnotationView)
    {
        // remove the current callout if one is showing
        if currentCallout != nil
        {
            currentCallout?.dismissCalloutAnimated( true )
            
            CalloutCell.cellWidth = 0
        }
    }
    
    func mapView(mapView: MKMapView, didAddAnnotationViews views: [MKAnnotationView])
    {
        // draw the tour trail a short delay after the pins drop
        let delayTime = dispatch_time(DISPATCH_TIME_NOW, Int64(1.5 * Double(NSEC_PER_SEC)))
        dispatch_after(delayTime, dispatch_get_main_queue())
        {
            self.makeTourTrail()
        }
    }
    
    // dismiss the current callout when scrolling the map;
    // don't dismiss the callout when setting the map's center coordinate prior to presenting the callout
    func mapView(mapView: MKMapView, regionWillChangeAnimated animated: Bool)
    {
        guard self.didSelectAnnotationView == true
            else
        {
            if self.currentCallout != nil
            {
                self.currentCallout?.dismissCalloutAnimated(true)
                self.currentCallout = nil
            }
            
            return
        }
    }
    
    // MARK: TourNavControlsDelegate methods
    
    /*
    func didPressBackButton()
    {
        print( "didPressBackButton" )
    }
    
    func didPressNextButton()
    {
        print( "didPressNextButton" )
    }
    
    func didPressZoomOutButton()
    {
        print( "didPressZoomOutButton" )
    }
    */
    
    func didPressListButton()
    {
        // create the tour list
        if self.tourList == nil
        {
            self.tourList = UIVisualEffectView(effect: UIBlurEffect(style: .Dark))
            
            let usedHeight: CGFloat = UIApplication.sharedApplication().statusBarFrame.size.height + self.navigationController!.navigationBar.bounds.height + self.tourTitleLabel!.bounds.height
            self.tourList?.frame = CGRect(x: 25, y: usedHeight + 25, width: self.view.bounds.width - 50, height: self.view.bounds.height - usedHeight - 90)
            
            let tourListTable = UITableView(frame: CGRect(x: 10, y: 10, width: tourList!.bounds.width - 20, height: tourList!.bounds.height - 20), style: .Plain)
            tourListTable.separatorStyle = .None
            tourListTable.dataSource = PhishModel.sharedInstance()
            tourListTable.delegate = PhishModel.sharedInstance()
            tourListTable.registerClass(TourListCell.self, forCellReuseIdentifier: "tourListCell")
            
            self.tourList?.contentView.addSubview(tourListTable)
            self.view.addSubview(tourList!)
        }
        // dismiss the tour list
        else
        {
            self.tourList?.removeFromSuperview()
            self.tourList = nil
        }
    }
    
    // MARK: CalloutCellDelegate method
    
    // segue to setlist view controller when the button is pressed in the callout view cell
    func didPressSetlistButton(cell: CalloutCell)
    {
        PhishModel.sharedInstance().currentShow = cell.show
        
        let setlistViewController = SetlistViewController()
        setlistViewController.show = cell.show
        
        self.showViewController(setlistViewController, sender: self)
        // self.showDetailViewController(setlistViewController, sender: self)
    }
    
    // MARK: TourListCellDelegate method
    
    // segue to setlist view controller when the button is pressed in the table view cell
    func didPressSetlistButtonInTourListCell(cell: TourListCell)
    {
        PhishModel.sharedInstance().currentShow = cell.show
        
        let setlistViewController = SetlistViewController()
        setlistViewController.show = cell.show
        
        self.showViewController(setlistViewController, sender: self)
        // self.showDetailViewController(setlistViewController, sender: self)
    }
}

