//
//  DashboardAnalytics.swift
//  Dashboard
//
//  Created by  Stepanok Ivan on 29.06.2023.
//

import Foundation

public protocol DashboardAnalytics {
    func dashboardCourseClicked(courseID: String, courseName: String)
}

class DashboardAnalyticsMock: DashboardAnalytics {
    public func dashboardCourseClicked(courseID: String, courseName: String) {}
}
