//
//  MileADayWidgetsBundle.swift
//  Mile A Day
//
//  Created by Robert Wiscount on 6/13/25.
//

import WidgetKit
import SwiftUI

@main
struct MileADayWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        TodayProgressWidget()
        StreakCountWidget()
    }
}
