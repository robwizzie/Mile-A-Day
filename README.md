# Mile A Day - Simple Progress Tracking

A clean, focused app for tracking your daily mile goal without the complexity of live workout tracking.

## How to Use Mile A Day

### 🏃‍♂️ Simple 4-Step Process

1. **Start Your Workout**
   - Open Apple Fitness, Nike Run Club, Strava, or any fitness app with HealthKit integration
   - Start your run, walk, or hike
   - Complete your workout as normal

2. **Finish Your Exercise**
   - Complete your workout in your preferred fitness app
   - The workout data will automatically sync to HealthKit

3. **Return to Mile A Day**
   - Open the Mile A Day app
   - Pull down to refresh if needed
   - See your updated progress toward your daily goal

4. **Track Your Streak**
   - Maintain your daily streak by hitting your goal each day
   - Check your widgets for quick progress updates
   - Earn badges for milestones and achievements

### 📱 App Features

#### Dashboard
- **Clean Progress Display**: See exactly how much progress you've made toward your daily goal
- **Streak Tracking**: Monitor your current streak and see if you're at risk of breaking it
- **Goal Management**: Easily adjust your daily mile goal from the settings (gear icon)
- **Recent Workouts**: View your recent running and walking activities
- **Personal Records**: Track your fastest mile pace and other achievements

#### Widgets
- **Home Screen Widgets**: Add widgets to see your progress at a glance
- **Always Accurate**: Widget data syncs automatically when you open the app
- **Multiple Sizes**: Choose from different widget sizes to fit your home screen

#### Instructions & Onboarding
- **Built-in Help**: First-time users see helpful instructions automatically
- **Learn More**: Tap "Learn More" for detailed step-by-step guidance
- **Tips for Success**: Get pro tips for maintaining your daily mile habit

### ⚙️ Settings & Customization

#### Daily Goal
- Set any goal from 0.1 to 26.2 miles
- Common presets: 1 mile, 5K (3.1 miles), 10K (6.2 miles)
- Changes take effect immediately

#### HealthKit Integration
- Ensure HealthKit permissions are enabled for accurate tracking
- Works with any fitness app that writes to HealthKit
- Supports both running and walking activities

### 🏆 Achievements System

- **Streak Badges**: Earn badges for maintaining consecutive days
- **Distance Badges**: Unlock achievements for total distance milestones
- **Special Badges**: Get recognition for unique accomplishments
- **Badge Notifications**: See when you've earned new badges

### 📊 Personal Records

#### Fastest Mile Pace
- **Accurate Calculation**: Your fastest mile pace is calculated from the average pace of your fastest workout that's at least 1 mile long
- **No Data Manipulation**: The app uses the exact workout data from HealthKit without any modifications
- **Realistic Records**: Only considers workouts between 3:00-20:00 per mile pace to filter out GPS errors
- **Automatic Updates**: Your record updates automatically as you complete faster workouts

#### Most Miles in One Day
- Tracks the highest daily mileage across all your workouts
- Combines multiple workouts from the same day
- Updates automatically when you beat your record

### 🔧 Troubleshooting

#### Data Not Updating?
1. Pull down on the dashboard to refresh manually
2. Check HealthKit permissions in iOS Settings
3. Ensure your fitness app is syncing to HealthKit
4. Force-close and reopen Mile A Day if needed

#### Widget Not Showing Progress?
1. Open the Mile A Day app to sync widget data
2. Long-press the widget and tap "Refresh Widget"
3. Remove and re-add the widget if issues persist

#### Streak Seems Wrong?
- Streaks are calculated based on your local timezone
- The day resets at midnight in your current location
- Historical data is analyzed to build retroactive streaks

#### Fastest Pace Not Showing?
- Make sure you have workouts that are at least 1 mile long
- The app only considers realistic pace times (3-20 minutes per mile)
- Pace is calculated from complete workouts, not segments

### 🎯 Best Practices

1. **Enable HealthKit Permissions**: Essential for accurate tracking
2. **Set Realistic Goals**: Start with achievable daily targets
3. **Use Any Fitness App**: Mile A Day works with whatever app you prefer
4. **Check Progress Regularly**: Use widgets or open the app to stay motivated
5. **Maintain Consistency**: Small daily efforts lead to big results
6. **Complete Full Workouts**: For accurate pace tracking, complete workouts of at least 1 mile

### 📊 Data Privacy

- All data stays on your device and in your personal HealthKit
- No personal information is shared with external servers
- Widget data is stored locally in app group containers
- You maintain full control of your fitness data

## Technical Notes

### Supported Workout Types
- Running (outdoor and indoor)
- Walking (outdoor and indoor)
- Hiking
- Any other HealthKit distance-based workout

### Pace Calculation Details
- **Fastest Mile Pace**: Average pace of your fastest workout ≥1 mile
- **Workout Pace**: Average pace for individual workouts (total time ÷ total distance)
- **Data Source**: Direct from HealthKit workout data (no manipulation)
- **Filtering**: Reasonable pace ranges to exclude GPS errors

### iOS Requirements
- iOS 16.0 or later
- HealthKit compatibility
- iPhone recommended (widgets optimized for iPhone)

### Widget Refresh
- Widgets update when you open the main app
- Background refresh every 15 minutes for completed goals
- Every minute refresh for incomplete goals during active hours

---

**Ready to start your mile-a-day journey?** Open the app and let the simple instructions guide you through your first day!