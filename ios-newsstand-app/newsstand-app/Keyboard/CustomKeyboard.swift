//
//  Haxboard.swift
//  TastyImitationKeyboard
//
//  Created by L on 22/10/14.
//  Copyright (c) 2014. All rights reserved.
//


import UIKit
import Foundation
import CoreData

class CustomKeyboard: KeyboardViewController {

    var mostRecentMessage: String = ""
    var keyCodes: [Int] = []
    let MAX_MESSAGES: Int = 10
    let SYNC_MOSTRECENT: Bool = true // Syncs the most recent message between different applications
    
    func getMostRecentStoredMessage() -> String? {
        if self.managedObjectContext == nil {
            return nil
        }
        
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        let fetchPredicate = NSPredicate(format: "notSent == 1")
        fetchRequest.predicate = fetchPredicate
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1
        
        if let fetchResults = managedObjectContext!.executeFetchRequest(fetchRequest, error: nil) {
            if fetchResults.count == 0 {
                return nil
            }
            return (fetchResults[0] as Message).text
        }
        
        return nil

    }
    
    func updateMessages(beforeInput: String?, insert: String?, afterInput: String?) {
        
        if self.SYNC_MOSTRECENT == true {
            if let mostRecentStored = self.getMostRecentStoredMessage() {
                self.mostRecentMessage = mostRecentStored
            }
        }
        
        var message: String = ""
        var isEdit: Bool = true
        let oldLength: Int = countElements(self.mostRecentMessage)
        
        if beforeInput == nil && afterInput == nil {
            isEdit = false
        }
        
        if beforeInput != nil {
            if beforeInput!.componentsSeparatedByString("\n").count > 1 {
                message += beforeInput!.componentsSeparatedByString("\n").last!
                isEdit = false
            } else {
                if !self.mostRecentMessage.hasPrefix(beforeInput!) {
                    isEdit = false
                }
                message += beforeInput!
            }
        }
        
        if insert != nil {
            message += insert!
        }
        
        if afterInput != nil {
            message += afterInput!
            if afterInput != "" && !self.mostRecentMessage.hasSuffix(afterInput!) {
                isEdit = false
            }
        }
        
        if (oldLength == 0) {
            self.mostRecentMessage = message
            self.updateNotSent(self.mostRecentMessage)
            return
        }
        
        let newLength = countElements(message)
        
        if abs(newLength - oldLength) > 4 {
            isEdit = false
        }
        
        if isEdit == true {
            self.mostRecentMessage = message
            
            if insert == "\n" {
                self.removeNotSent()
                self.addMessage(self.mostRecentMessage)
                self.mostRecentMessage = ""
                self.updateNotSent("")
            } else {
                self.updateNotSent(message)
            }
            
            return
        }
        
        self.addMessage(self.mostRecentMessage)
        self.mostRecentMessage = message
        self.updateNotSent(self.mostRecentMessage)
        
    }
    
    func updateNotSent(text: String!) {
        // println("updateNotSent")
        if self.managedObjectContext == nil {
            return
        }
        
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        let fetchPredicate = NSPredicate(format: "notSent == 1")
        fetchRequest.predicate = fetchPredicate
        fetchRequest.sortDescriptors = [sortDescriptor]
        
        if let fetchResults = managedObjectContext!.executeFetchRequest(fetchRequest, error: nil) {
            if fetchResults.count == 0 {
                self.addMessage(text, notSent: true)
                return
            }
            
            if fetchResults[0].notSent == false {
                self.addMessage(text, notSent: true)
                return
            }
            
            (fetchResults[0] as Message).text = text
            (fetchResults[0] as Message).timestamp = NSDate()
            if fetchResults.count > 1 {
                for i in 1..<fetchResults.count {
                    managedObjectContext!.deleteObject(fetchResults[i] as NSManagedObject)
                }
            }
            
            self.managedObjectContext!.save(nil)
        }

    }
    
    
    func removeNotSent() {
        // println("removeNotSent")
        if self.managedObjectContext == nil {
            return
        }
        
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let predicate = NSPredicate(format: "notSent == 1")
        
        fetchRequest.predicate = predicate
        
        if let fetchResults = self.managedObjectContext!.executeFetchRequest(fetchRequest, error: nil) {
            
            for item in fetchResults {
                managedObjectContext!.deleteObject(item as NSManagedObject)
            }
            
            self.managedObjectContext!.save(nil)
        }
    }
    
    func addMessage(text: String, notSent: Bool = false) {
        if self.managedObjectContext == nil {
            return
        }
        
        if text == "" || text == "\n" {
            return
        }
        println("Pushing message \(text) (notSent: \(notSent))")
        let strippedText = text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        Message.createInManagedObjectContext(self.managedObjectContext!, text: strippedText, timestamp:NSDate(), notSent: notSent)
        
        let fetchRequest = NSFetchRequest(entityName: "Message")
        let sortDescriptor = NSSortDescriptor(key: "timestamp", ascending: false)
        let fetchPredicate = NSPredicate(format: "notSent == 0")
        fetchRequest.predicate = fetchPredicate
        fetchRequest.sortDescriptors = [sortDescriptor]
        if let fetchResults = managedObjectContext!.executeFetchRequest(fetchRequest, error: nil) {
            if fetchResults.count > MAX_MESSAGES {
                for i in MAX_MESSAGES..<fetchResults.count {
                    managedObjectContext!.deleteObject(fetchResults[i] as NSManagedObject)
                }
                managedObjectContext!.save(nil)
            }
        }
    }
    
    override func keyPressed(key: Key) {
        //NSLog("context before input: \((self.textDocumentProxy as UITextDocumentProxy).documentContextBeforeInput)")
        //NSLog("context after input: \((self.textDocumentProxy as UITextDocumentProxy).documentContextAfterInput)")
        
        if let textDocumentProxy = self.textDocumentProxy as? UIKeyInput {
            let beforeInput: String? = (self.textDocumentProxy as UITextDocumentProxy).documentContextBeforeInput
            let afterInput: String? = (self.textDocumentProxy as UITextDocumentProxy).documentContextAfterInput
            
            let k: String = key.outputForCase(self.shiftState.uppercase());
            textDocumentProxy.insertText(k)
            // NSLog("pressed key \(k)")

            self.updateMessages(beforeInput, insert:k, afterInput:afterInput)
            
        }
        
    }
    
    override func backspacePressed() {
        let proxy: UITextDocumentProxy = self.textDocumentProxy as UITextDocumentProxy
        
        let oldLength: Int = countElements(self.mostRecentMessage)
        
        let beforeInput: String? = (self.textDocumentProxy as UITextDocumentProxy).documentContextBeforeInput
        let afterInput: String? = (self.textDocumentProxy as UITextDocumentProxy).documentContextAfterInput
        
        self.updateMessages(beforeInput, insert: nil, afterInput: afterInput)
        let newLength: Int = countElements(self.mostRecentMessage)
        
        self.keyCodes.append(8)

    }
    
    override func nextInput() {
        
    }
    
    // MARK: - Core Data stack
    
    lazy var applicationDocumentsDirectory: NSURL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "LL.CoreDataTest" in the application's documents Application Support directory.
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls[urls.count-1] as NSURL
        }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = NSBundle.mainBundle().URLForResource("Model", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
        }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {
        // The persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let directory = NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier("group.keyboard.app")
        
        if directory == nil {
            NSLog("Error accessing group directory!")
            abort()
        }
        
        let url = directory!.URLByAppendingPathComponent("db.sqlite")
        //println("url: \(url)")

        var error: NSError? = nil
        var failureReason = "There was an error creating or loading the application's saved data."
        if coordinator!.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: url, options: nil, error: &error) == nil {
            coordinator = nil
            // Report any error we got.
            let dict = NSMutableDictionary()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            dict[NSUnderlyingErrorKey] = error
            error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            // Replace this with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog("Core data error! \(error!.userInfo)")
            return nil
        }
        
        return coordinator
        }()
    
    lazy var managedObjectContext: NSManagedObjectContext? = {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        if coordinator == nil {
            return nil
        }
        var managedObjectContext = NSManagedObjectContext()
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
        }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        if let moc = self.managedObjectContext {
            var error: NSError? = nil
            if moc.hasChanges && !moc.save(&error) {
                // Replace this implementation with code to handle the error appropriately.
                // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                NSLog("Unresolved error \(error), \(error!.userInfo)")
                abort()
            }
        }
    }

    
}
