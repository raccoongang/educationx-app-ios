//
//  CourseRouter.swift
//  Course
//
//  Created by  Stepanok Ivan on 16.11.2022.
//

import Foundation
import Core

public protocol CourseRouter: BaseRouter {
    
    func showCourseScreens(courseID: String,
                           isActive: Bool?,
                           courseStart: Date?,
                           courseEnd: Date?,
                           enrollmentStart: Date?,
                           enrollmentEnd: Date?,
                           title: String)
    
    func showCourseUnit(blockId: String,
                        courseID: String,
                        sectionName: String,
                        verticalIndex: Int,
                        chapters: [CourseChapter],
                        chapterIndex: Int,
                        sequentialIndex: Int)
    
    func replaceCourseUnit(blockId: String,
                           courseID: String,
                           sectionName: String,
                           verticalIndex: Int,
                           chapters: [CourseChapter],
                           chapterIndex: Int,
                           sequentialIndex: Int)
    
    func showCourseVerticalView(title: String,
                                chapters: [CourseChapter],
                                chapterIndex: Int,
                                sequentialIndex: Int)
    
    func showHandoutsUpdatesView(handouts: String?,
                                 announcements: [CourseUpdate]?,
                                 router: Course.CourseRouter,
                                 cssInjector: CSSInjector)
}

// Mark - For testing and SwiftUI preview
#if DEBUG
public class CourseRouterMock: BaseRouterMock, CourseRouter {
    
    public override init() {}
    
    public func showCourseScreens(courseID: String,
                                  isActive: Bool?,
                                  courseStart: Date?,
                                  courseEnd: Date?,
                                  enrollmentStart: Date?,
                                  enrollmentEnd: Date?,
                                  title: String) {}
    
    public func showCourseUnit(blockId: String,
                               courseID: String,
                               sectionName: String,
                               verticalIndex: Int,
                               chapters: [CourseChapter],
                               chapterIndex: Int,
                               sequentialIndex: Int) {}
    
    public func replaceCourseUnit(blockId: String,
                                  courseID: String,
                                  sectionName: String,
                                  verticalIndex: Int,
                                  chapters: [CourseChapter],
                                  chapterIndex: Int,
                                  sequentialIndex: Int) {}
    
    public func showCourseVerticalView(title: String,
                                       chapters: [CourseChapter],
                                       chapterIndex: Int,
                                       sequentialIndex: Int) {}
    
    public func showHandoutsUpdatesView(handouts: String?,
                                        announcements: [CourseUpdate]?,
                                        router: Course.CourseRouter,
                                        cssInjector: CSSInjector) {}
    
}
#endif
