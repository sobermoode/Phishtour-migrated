//
//  PhishYear.swift
//  PhishTour
//
//  Created by Aaron Justman on 10/1/15.
//  Copyright (c) 2015 AaronJ. All rights reserved.
//

import UIKit
import CoreData

class PhishYear: NSManagedObject
{
    /// the year
    @NSManaged var year: NSNumber
    
    /// a year is composed of a set of tours
    @NSManaged var tours: [PhishTour]?
    
    override init(entity: NSEntityDescription, insertIntoManagedObjectContext context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertIntoManagedObjectContext: context)
    }
    
    init(year: Int)
    {
        /// insert the object into the core data context
        let context = CoreDataStack.sharedInstance().managedObjectContext
        let yearEntity = NSEntityDescription.entityForName("PhishYear", inManagedObjectContext: context)!
        super.init(entity: yearEntity, insertIntoManagedObjectContext: context)
        
        self.year = year
    }
}
