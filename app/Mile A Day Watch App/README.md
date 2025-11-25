# Mile A Day - Apple Watch App

A standalone Apple Watch app for tracking daily mile workouts with real-time metrics and HealthKit integration.

## Features

### ✅ Core Functionality
- **Standalone Operation**: Works independently without iPhone nearby
- **Workout Tracking**: Track runs and walks with accurate distance measurement
- **Indoor/Outdoor Support**: GPS for outdoor, motion sensors for indoor
- **Real-time Metrics**: Distance, pace, time, heart rate, calories
- **HealthKit Integration**: Automatic sync to iPhone via iCloud
- **Today's Progress**: View daily distance and goal completion
- **Streak Display**: See your current streak on the main screen

### 📱 User Interface
- **Activity Selection**: Choose Run or Walk
- **Location Selection**: Choose Indoor or Outdoor
- **Live Tracking**: Real-time workout metrics with progress ring
- **Workout Recap**: Summary of completed workout with all stats
- **Clean Design**: watchOS-optimized UI with large, readable metrics

### 🔧 Technical Features
- **HKWorkoutSession**: Native watchOS workout API
- **HKLiveWorkoutBuilder**: Real-time data collection
- **Heart Rate Monitoring**: Automatic from watch sensors
- **GPS Tracking**: Built-in for outdoor workouts
- **Pedometer**: Motion-based distance for indoor workouts
- **Background Modes**: Workout processing and background fetch

## Architecture

### Files Structure
```
Mile A Day Watch App/
├── Mile_A_Day_Watch_App.swift       # App entry point
├── ContentView.swift                  # Main screen (today's progress)
├── Views/
│   ├── WorkoutView.swift             # Workout flow and tracking UI
│   └── WatchWorkoutManager.swift     # Workout session manager
├── Info.plist                         # Permissions and configuration
├── Mile_A_Day_Watch_App.entitlements # Capabilities
├── SETUP_INSTRUCTIONS.md             # Detailed setup guide
└── README.md                          # This file
```

### Data Flow
1. User starts workout on Apple Watch
2. `WatchWorkoutManager` creates `HKWorkoutSession`
3. HealthKit collects distance, heart rate, calories in real-time
4. Workout saved to HealthKit on watch when complete
5. HealthKit automatically syncs to iPhone via iCloud
6. iPhone app reads workout from HealthKit
7. Workout appears in today's progress

### Shared Code
The watch app shares these files with the iOS app:
- `HealthKitManager.swift` - HealthKit operations
- `UserManager.swift` - User state management
- `Models/` - Data models (User, WorkoutRecord, DayState)

## Setup

**See [SETUP_INSTRUCTIONS.md](./SETUP_INSTRUCTIONS.md) for complete setup guide.**

Quick steps:
1. Add watchOS target in Xcode
2. Add source files to target
3. Share iOS code (HealthKitManager, models)
4. Enable HealthKit capability
5. Build and run on Apple Watch

## Usage

### Starting a Workout
1. Open app on Apple Watch
2. Tap "Start Mile" button
3. Select "Run" or "Walk"
4. Select "Outdoor" or "Indoor"
5. Workout begins automatically

### During Workout
- **Main metric**: Current distance in miles
- **Progress ring**: Percentage toward daily goal
- **Time**: Elapsed workout time
- **Pace**: Current pace per mile
- **Heart rate**: Live from watch sensors
- **End button**: Tap to finish workout

### After Workout
- View recap with all stats
- Workout automatically saved to HealthKit
- Syncs to iPhone within minutes
- Appears in iPhone app automatically

## Requirements

- **watchOS**: 9.0 or later
- **Swift**: 5.5+
- **Xcode**: 14.0+
- **Device**: Apple Watch Series 4 or later (recommended)
- **HealthKit**: Required
- **Location**: Required for outdoor workouts
- **Motion**: Required for indoor workouts

## Permissions

The app requires:
- **HealthKit**: Read/write workouts, distance, heart rate, calories
- **Location**: GPS tracking for outdoor workouts
- **Motion**: Pedometer for indoor workouts
- **Background Modes**: Workout processing

All permissions are requested on first launch.

## Testing

### Simulator Testing
- Basic UI testing
- Flow testing (activity selection, location selection)
- **Limitation**: No real workout data (heart rate, GPS)

### Physical Device Testing
- Full workout tracking
- Real GPS data
- Heart rate monitoring
- Background operation
- HealthKit sync verification

**Recommendation**: Test on physical Apple Watch for accurate results.

## Future Enhancements

Potential features for future versions:
- [ ] Watch complications (show streak/progress on watch face)
- [ ] Haptic feedback at mile markers
- [ ] Audio cues for splits
- [ ] Weekly summary view
- [ ] Multiple workout types (cycling, hiking)
- [ ] Custom goals per workout
- [ ] Social features

## Troubleshooting

**Workout not starting**
- Check HealthKit permissions granted
- Verify location permission for outdoor
- Check motion permission for indoor

**No heart rate data**
- Ensure watch worn snugly
- Check watch sensors are clean
- Verify HealthKit has heart rate permission

**Workout not syncing to iPhone**
- Ensure same iCloud account on both devices
- Enable HealthKit iCloud sync in Settings
- Check internet connection
- Wait a few minutes for sync

**Distance inaccurate**
- For outdoor: Ensure good GPS signal (clear sky)
- For indoor: Calibrate by doing outdoor workout first
- Check location/motion permissions

## Support

For issues or questions:
1. Check [SETUP_INSTRUCTIONS.md](./SETUP_INSTRUCTIONS.md)
2. Review this README
3. Check Xcode console for error messages
4. Verify all permissions granted in Watch settings

## License

Same license as Mile A Day iOS app.
