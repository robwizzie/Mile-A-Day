# Split Times Data Structure

## Overview
Split times represent the time (in seconds) it took to complete each mile during a workout. They are stored as an array of numbers, where each number represents one mile split.

## Field Name
- **API Field**: `splitTimes` (camelCase)
- **Type**: `number[]` (array of numbers)
- **Unit**: Seconds per mile
- **Required**: Yes (can be empty array `[]` if no splits available)

## Data Format

### Example 1: 2-mile run with consistent pace
```json
{
  "workoutId": "ABC123",
  "distance": 2.0,
  "localDate": "2025-10-26",
  "timezoneOffset": -240,
  "workoutType": "running",
  "deviceEndDate": "2025-10-26T08:30:00Z",
  "calories": 200,
  "totalDuration": 720,
  "splitTimes": [360, 360]
}
```
**Explanation**: 
- First mile: 360 seconds = 6:00 minutes
- Second mile: 360 seconds = 6:00 minutes
- Total: 2 miles in 12:00 minutes

### Example 2: 3-mile run with varying pace
```json
{
  "workoutId": "XYZ789",
  "distance": 3.0,
  "localDate": "2025-10-27",
  "timezoneOffset": -240,
  "workoutType": "running",
  "deviceEndDate": "2025-10-27T09:15:00Z",
  "calories": 300,
  "totalDuration": 1020,
  "splitTimes": [330, 345, 345]
}
```
**Explanation**:
- First mile: 330 seconds = 5:30 minutes
- Second mile: 345 seconds = 5:45 minutes
- Third mile: 345 seconds = 5:45 minutes
- Total: 3 miles in 17:00 minutes

### Example 3: Partial mile workout (no complete splits)
```json
{
  "workoutId": "DEF456",
  "distance": 0.75,
  "localDate": "2025-10-28",
  "timezoneOffset": -240,
  "workoutType": "walking",
  "deviceEndDate": "2025-10-28T10:00:00Z",
  "calories": 75,
  "totalDuration": 900,
  "splitTimes": []
}
```
**Explanation**: 
- Distance is less than 1 mile, so no complete mile splits are recorded
- Array is empty `[]`

## Validation Rules

The iOS app validates split times before sending:
- **Minimum**: 180 seconds (3:00 minutes per mile)
- **Maximum**: 1200 seconds (20:00 minutes per mile)
- Splits outside this range are filtered out and not sent to the backend

## Database Storage

Split times are stored in the `workout_splits` table with the following structure:
- `workout_id`: References the workout
- `split_number`: Index of the split (0-based: 0 = first mile, 1 = second mile, etc.)
- `split_time`: Time in seconds for that mile

### Example Database Records
For a workout with `splitTimes: [360, 360, 375]`:

| workout_id | split_number | split_time |
|------------|--------------|------------|
| ABC123     | 0            | 360        |
| ABC123     | 1            | 360        |
| ABC123     | 2            | 375        |

## Best Split Time

The backend also provides a `best_split_time` field in user stats, which represents the fastest mile split time (in seconds) across all workouts.

### Example Response
```json
{
  "best_split_time": 420,
  "workout": {
    "workout_id": "ABC123",
    "local_date": "2025-10-26"
  }
}
```
**Explanation**: Fastest mile was 420 seconds = 7:00 minutes per mile

## Notes
- Split times are calculated from HealthKit distance samples
- Only complete miles (1.0+ miles) generate split times
- The array index corresponds to the mile number (0 = mile 1, 1 = mile 2, etc.)
- If a workout has no valid splits, the array will be empty `[]`

