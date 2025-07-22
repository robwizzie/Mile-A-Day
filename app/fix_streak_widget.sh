#!/bin/bash

# Remove all live tracking references from StreakCountWidget
sed -i 's/entry\.isLiveMode ? "dot.radiowaves.left.and.right" : "flame.fill"/"flame.fill"/g' "./Mile A Day/Widgets/StreakCountWidget.swift"
sed -i 's/entry\.isLiveMode ? \.red : \.orange/\.orange/g' "./Mile A Day/Widgets/StreakCountWidget.swift"
sed -i 's/if entry\.isLiveMode {/if false {/g' "./Mile A Day/Widgets/StreakCountWidget.swift"
sed -i 's/entry\.liveProgress/entry.progress/g' "./Mile A Day/Widgets/StreakCountWidget.swift"
sed -i 's/isLiveMode: true/progress: 0.7/g' "./Mile A Day/Widgets/StreakCountWidget.swift"
sed -i 's/liveProgress: 0\.7, //g' "./Mile A Day/Widgets/StreakCountWidget.swift"
