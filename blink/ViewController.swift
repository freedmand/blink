//
//  ViewController.swift
//  blink
//
//  Created by Dylan Freedman on 7/10/21.
//

import Cocoa

// Define a clamped routine to bound a double
// from https://stackoverflow.com/a/40868784
extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

class ViewController: NSViewController, NSTextFieldDelegate {
    // UI controls
    @IBOutlet weak var onButton: NSButton!
    @IBOutlet weak var descriptiveText1: NSTextField!
    @IBOutlet weak var descriptiveText2: NSTextField!
    @IBOutlet weak var awakeField: NSTextField!
    @IBOutlet weak var sleepField: NSTextField!
    @IBOutlet weak var outField: NSTextField!
    @IBOutlet weak var inField: NSTextField!
    @IBOutlet weak var noFadeField: NSTextField!
    
    // User defaults
    let defaults = UserDefaults.standard
    lazy var params = defaults.object(forKey: "params") as? [String: Double] ?? [
        "outDuration": 2.0,
        "inDuration": 1.0,
        "sleepDuration": 1.0,
        "awakeDuration": 60.0,
        "fullFade": 1.0,
    ]
    
    // Parameter get functions
    func getOutDuration() -> CGDisplayFadeInterval {
        return CGDisplayFadeInterval((params["outDuration"] ?? 2.0).clamped(to: 0.0 ... 7.0))
    }
    
    func getInDuration() -> CGDisplayFadeInterval {
        return CGDisplayFadeInterval((params["inDuration"] ?? 1.0).clamped(to: 0.0 ... 7.0))
    }
    
    func getSleepDuration() -> CGDisplayFadeInterval {
        return CGDisplayFadeInterval((params["sleepDuration"] ?? 60.0).clamped(to: 1.0 ... 10000.0))
    }
    
    func getAwakeDuration() -> Double {
        return (params["awakeDuration"] ?? 1.0).clamped(to: 1.0 ... 10000.0)
    }
    
    func getFullFade() -> CGDisplayBlendFraction {
        return CGDisplayBlendFraction((params["fullFade"] ?? 1.0).clamped(to: 0.0 ... 1.0))
    }
    
    // Other constants
    let fadeLockTimePadding: CGDisplayFadeInterval = 2.0
    let noFade: CGDisplayBlendFraction = 0.0
    
    var isOn = false
    var task: DispatchWorkItem? = nil
    
    @IBAction func turnOn(_ sender: Any) {
        // Toggle the program being on or off
        setIsOn(on: !self.isOn)
    }
    
    func setIsOn(on: Bool) {
        updateFields()
        if on {
            setTimeout(time: 0)
        } else {
            clearTimeout()
        }
        // Hide the text describing what to do when it's on
        descriptiveText1.isHidden = on
        descriptiveText2.isHidden = on
        onButton.title = on ? "Stop Blink" : "Start Blink"
        isOn = on
    }
    
    func controlTextDidChange(_ obj: Notification) {
        changeAction()
    }
    
    func updateFields() {
        // Update the parameter values based on the UI fields
        params["awakeDuration"] = awakeField.doubleValue.clamped(to: 1.0 ... 10000.0)
        params["sleepDuration"] = sleepField.doubleValue.clamped(to: 1.0 ... 10000.0)
        
        params["outDuration"] = outField.doubleValue.clamped(to: 0.0 ... 7.0)
        params["inDuration"] = inField.doubleValue.clamped(to: 0.0 ... 7.0)
        
        params["fullFade"] = ((100.0 - noFadeField.doubleValue) / 100.0).clamped(to: 0.0 ... 1.0)
        
        // Update defaults
        defaults.set(params,forKey: "params")
    }
    
    func changeAction() {
        // When changing UI, turn the blinking off
        setIsOn(on: false)
        updateFields()
    }
    
    func fadeOutIn() {
        // The main fade routine
        // Run in a background thread for performance
        DispatchQueue.global(qos: .background).async {
            // Only run if blink is currently on
            if self.isOn {
                // Get all the parameter constants
                let inDuration = self.getInDuration()
                let outDuration = self.getOutDuration()
                let sleepDuration = self.getSleepDuration()
                let awakeDuration = self.getAwakeDuration()
                let fullFade = self.getFullFade()

                // Reserve a fade token to apply to fade effects
                var fadeToken: CGDisplayFadeReservationToken = 0
                let err = CGAcquireDisplayFadeReservation(Float(inDuration + outDuration + sleepDuration + self.fadeLockTimePadding), &fadeToken)
                if err != CGError.success {
                    return
                }
                
                // Once all is faded, set the timeout to repeat
                defer {
                    CGReleaseDisplayFadeReservation(fadeToken)
                    self.setTimeout(time: awakeDuration)
                }
            
                // Fade out
                CGDisplayFade(fadeToken, outDuration,
                              self.noFade, fullFade,
                              0.0, 0.0, 0.0,
                              boolean_t(1))
                // Sleep
                CGDisplayFade(fadeToken, sleepDuration, fullFade, fullFade, 0.0, 0.0, 0.0, boolean_t(1))
                // Fade in
                CGDisplayFade(fadeToken, inDuration,
                              fullFade, self.noFade,
                              0.0, 0.0, 0.0,
                              boolean_t(1))
            }
        }
    }
    
    func clearTimeout() {
        // Clear a timeout if previously set
        DispatchQueue.global(qos: .background).async {
            if let _task = self.task {
                _task.cancel()
                self.task = nil
            }
        }
    }
    
    func setTimeout(time: Double) {
        // Set a timeout to run the fade routine
        // Time is specified in seconds
        DispatchQueue.global(qos: .background).async {
            if let _task = self.task {
                _task.cancel()
                self.task = nil
            }
            self.task = DispatchWorkItem {
                self.fadeOutIn()
                self.task = nil
            }
            if let _task = self.task {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + time, execute: _task)
            }
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        // Set the UI fields based on stored params
        awakeField.doubleValue = getAwakeDuration()
        sleepField.doubleValue = Double(getSleepDuration())
        outField.doubleValue = Double(getOutDuration())
        inField.doubleValue = Double(getInDuration())
        noFadeField.doubleValue = Double((1.0 - getFullFade()) * 100.0)
        
        // Set UI controls' delegates to self to pick up text change events
        awakeField.delegate = self
        sleepField.delegate = self
        outField.delegate = self
        inField.delegate = self
        noFadeField.delegate = self
    }
}
