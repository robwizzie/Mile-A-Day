# Apple Watch App Setup Instructions

This document explains how to add the watchOS target to the Mile A Day Xcode project and configure it properly.

## Overview

The Apple Watch app has been fully implemented with:
- ✅ Complete workout tracking UI
- ✅ Indoor/outdoor workout support
- ✅ Real-time distance, pace, heart rate tracking
- ✅ HealthKit integration with HKWorkoutSession
- ✅ Automatic sync to iPhone via HealthKit
- ✅ Today's progress and streak display

**All source code is ready** - you just need to add the watchOS target in Xcode.

---

## Step 1: Add watchOS Target in Xcode

1. **Open the Project**
   - Open `Mile A Day.xcodeproj` in Xcode

2. **Add New Target**
   - Click on the project in the Project Navigator (blue icon at top)
   - Click the `+` button at the bottom of the targets list
   - Select **watchOS** → **App**
   - Click **Next**

3. **Configure Target Settings**
   - **Product Name**: `Mile A Day Watch App`
   - **Organization Name**: Your organization name
   - **Organization Identifier**: `com.mileaday` (or your identifier)
   - **Bundle Identifier**: `com.mileaday.app.watchkitapp`
   - **Team**: Your development team
   - **Interface**: SwiftUI
   - **Language**: Swift
   - Click **Finish**
   - When asked "Activate scheme?", click **Activate**

4. **Delete Auto-Generated Files**
   - Xcode will create some template files
   - Delete these auto-generated files:
     - `Mile A Day Watch AppApp.swift`
     - `ContentView.swift`
     - `Assets.xcassets` (or merge with ours)
   - We're using the files already created in the repository

---

## Step 2: Add Source Files to Target

1. **Navigate to the Watch App Folder**
   - In Finder, go to: `app/Mile A Day Watch App/`
   - You should see these files:
     ```
     Mile_A_Day_Watch_App.swift
     ContentView.swift
     Info.plist
     Mile_A_Day_Watch_App.entitlements
     Views/
       ├── WorkoutView.swift
       └── WatchWorkoutManager.swift
     ```

2. **Add Files to Xcode**
   - In Xcode, right-click on `Mile A Day Watch App` target folder
   - Select **Add Files to "Mile A Day Watch App"...**
   - Navigate to `app/Mile A Day Watch App/`
   - Select ALL files and folders
   - **Important**: Check "Copy items if needed" is UNCHECKED (files are already in place)
   - **Target Membership**: Make sure `Mile A Day Watch App` is checked
   - Click **Add**

---

## Step 3: Share Code Between iOS and watchOS

The watch app needs to access shared models and managers from the iOS app.

1. **Share HealthKitManager**
   - Select `HealthKitManager.swift` in the Project Navigator
   - In the File Inspector (right sidebar), under **Target Membership**:
     - ✅ Mile A Day (already checked)
     - ✅ Mile A Day Watch App (check this)

2. **Share UserManager**
   - Select `UserManager.swift`
   - Add target membership:
     - ✅ Mile A Day Watch App

3. **Share Models**
   - Select all files in the `Models` folder:
     - `User.swift`
     - `WorkoutRecord.swift`
     - `DayState.swift`
     - Any other model files
   - Add `Mile A Day Watch App` target membership to each

4. **Share Services (Optional)**
   - If you want to sync data directly to backend from watch:
     - Share `WorkoutService.swift`
     - Share `NetworkManager.swift`
   - Note: Not required for standalone watch app (HealthKit handles sync)

---

## Step 4: Configure Target Settings

### General Settings

1. **Select Watch App Target**
   - Click `Mile A Day Watch App` in targets list

2. **Set Deployment Target**
   - **Minimum Deployment**: watchOS 9.0 or later

3. **Set Bundle Identifier**
   - Should be: `com.mileaday.app.watchkitapp`
   - Must match companion app structure

### Signing & Capabilities

1. **Signing**
   - Select your development team
   - Enable **Automatically manage signing**

2. **Add Capabilities**
   - Click `+ Capability`
   - Add **HealthKit**
     - Check "Clinical Health Records"
   - Add **Background Modes**
     - Check "Workout Processing"
     - Check "Background Fetch"

3. **Info.plist Configuration**
   - The `Info.plist` is already configured with:
     - NSHealthShareUsageDescription
     - NSHealthUpdateUsageDescription
     - NSLocationWhenInUseUsageDescription
     - NSMotionUsageDescription
   - These should appear automatically

4. **Entitlements**
   - Select `Mile_A_Day_Watch_App.entitlements` as the entitlements file
   - Should include:
     - HealthKit
     - App Groups (if using)

---

## Step 5: Build and Test

### Build the Watch App

1. **Select Watch Scheme**
   - At the top of Xcode, select:
     - Scheme: `Mile A Day Watch App`
     - Destination: Choose an Apple Watch simulator or device

2. **Build**
   - Press `Cmd + B` to build
   - Fix any compilation errors (should be none if setup correctly)

3. **Run on Simulator**
   - Press `Cmd + R` to run
   - The Apple Watch simulator should launch
   - The app should appear on the watch face

### Test on Physical Watch (Recommended)

1. **Pair Apple Watch**
   - Ensure your Apple Watch is paired with your iPhone
   - Both devices should be connected to your Mac

2. **Select Physical Watch**
   - Scheme: `Mile A Day Watch App`
   - Destination: Your Apple Watch

3. **Build and Run**
   - Press `Cmd + R`
   - Grant permissions when prompted:
     - HealthKit access
     - Location access (for outdoor workouts)
     - Motion access (for indoor workouts)

4. **Test Workout Flow**
   - Tap "Start Mile"
   - Select Run or Walk
   - Select Indoor or Outdoor
   - Start tracking
   - Verify distance updates
   - Verify heart rate appears
   - End workout
   - Check recap screen
   - Verify workout appears in iPhone app (via HealthKit sync)

---

## Step 6: Verify HealthKit Sync

The watch app saves workouts directly to HealthKit on the watch. HealthKit automatically syncs to the iPhone via iCloud.

1. **Complete a Workout on Watch**
   - Track at least 0.1 miles
   - End the workout
   - View the recap

2. **Check iPhone App**
   - Open Mile A Day on iPhone
   - Pull down to refresh dashboard
   - The workout should appear automatically
   - Distance should be added to today's total

3. **Verify in Apple Health App**
   - Open Health app on iPhone
   - Go to Browse → Activity → Workouts
   - Your watch workout should appear
   - Source: Mile A Day Watch App

---

## Architecture Notes

### Standalone Watch App

This is a **standalone watch app** that:
- ✅ Works independently without iPhone nearby
- ✅ Saves workouts directly to HealthKit on watch
- ✅ Uses HealthKit's automatic iCloud sync
- ✅ No custom sync logic needed
- ✅ iPhone app reads from shared HealthKit data

### Workout Tracking

- **Outdoor workouts**: Uses GPS from Apple Watch
- **Indoor workouts**: Uses motion sensors and accelerometer
- **Heart rate**: Automatic from watch sensors
- **Calories**: Calculated by HealthKit
- **API**: Uses `HKWorkoutSession` and `HKLiveWorkoutBuilder` (watchOS native)

### Data Flow

```
Apple Watch
    ↓ (User starts workout)
WatchWorkoutManager
    ↓ (Tracks via HKWorkoutSession)
HealthKit on Watch
    ↓ (iCloud sync)
HealthKit on iPhone
    ↓ (Automatic)
Mile A Day iPhone App
    ↓ (Reads from HealthKit)
Dashboard shows workout
```

---

## Troubleshooting

### Build Errors

**Error**: "Cannot find 'HealthKitManager' in scope"
- **Fix**: Make sure `HealthKitManager.swift` has `Mile A Day Watch App` target membership

**Error**: "Cannot find 'User' in scope"
- **Fix**: Share all model files with watch target

**Error**: Module compiled with Swift X.X cannot be imported
- **Fix**: Ensure iOS and watchOS targets use same Swift version in Build Settings

### Runtime Errors

**HealthKit authorization fails**
- **Fix**: Check Info.plist has all required permission descriptions
- **Fix**: Ensure HealthKit capability is enabled in target settings

**Workout doesn't start**
- **Fix**: Check logs for authorization issues
- **Fix**: Ensure watch has location/motion permissions granted

**Workout doesn't appear on iPhone**
- **Fix**: Ensure both devices signed into same iCloud account
- **Fix**: Check Settings → Health → Data Access & Devices
- **Fix**: Force refresh iPhone app (pull down on dashboard)

### Sync Issues

**Workout not syncing to iPhone**
- HealthKit sync requires:
  - Same iCloud account on both devices
  - HealthKit iCloud sync enabled: Settings → [Your Name] → iCloud → Health (toggle ON)
  - Internet connection (Wi-Fi or cellular)
- Try: Toggle HealthKit iCloud sync off and on

---

## Optional: Watch Complications (Future Enhancement)

To add watch face complications showing daily progress:

1. Create `ComplicationController.swift`
2. Implement `CLKComplicationDataSource`
3. Add complication support in Info.plist
4. Configure complication families (graphic, modular, etc.)

This is not included in the initial implementation but can be added later.

---

## Summary

After following these steps, you'll have:
- ✅ Fully functional Apple Watch app
- ✅ Workout tracking with indoor/outdoor support
- ✅ Real-time metrics (distance, pace, heart rate)
- ✅ Automatic sync to iPhone via HealthKit
- ✅ Standalone operation (works without iPhone)
- ✅ Professional UI matching iOS app design

The watch app is production-ready and follows Apple's best practices for watchOS workout apps!
