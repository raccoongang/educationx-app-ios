//
//  CourseDetailsViewModelTests.swift
//  CourseDetailsTests
//
//  Created by  Stepanok Ivan on 20.01.2023.
//

import SwiftyMocky
import XCTest
@testable import Core
@testable import Course
import Alamofire
import SwiftUI

final class CourseDetailsViewModelTests: XCTestCase {

    func testGetCourseDetailSuccess() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        let courseDetails = CourseDetails(
            courseID: "123",
            org: "org",
            courseTitle: "title",
            courseDescription: "description",
            courseStart: Date(),
            courseEnd: nil,
            enrollmentStart: nil,
            enrollmentEnd: nil,
            isEnrolled: true,
            overviewHTML: "",
            courseBannerURL: "",
            courseVideoURL: nil
        )
        
        
        Given(interactor, .getCourseDetails(courseID: "123",
                                            willReturn: courseDetails))
        
        await viewModel.getCourseDetail(courseID: "123")
        
        Verify(interactor, 1, .getCourseDetails(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
    }
    
    func testGetCourseDetailSuccessOffline() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: false))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        let courseDetails = CourseDetails(
            courseID: "123",
            org: "org",
            courseTitle: "title",
            courseDescription: "description",
            courseStart: Date(),
            courseEnd: nil,
            enrollmentStart: nil,
            enrollmentEnd: nil,
            isEnrolled: true,
            overviewHTML: "",
            courseBannerURL: "",
            courseVideoURL: nil
        )
        
        Given(interactor, .getCourseDetailsOffline(courseID: "123",
                                                   willReturn: courseDetails))
        
        await viewModel.getCourseDetail(courseID: "123")
        
        Verify(interactor, 1, .getCourseDetailsOffline(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
    }
    
    func testGetCourseDetailNoInternetError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        let noInternetError = AFError.sessionInvalidated(error: URLError(.notConnectedToInternet))

        Given(interactor, .getCourseDetails(courseID: "123",
                                            willThrow: noInternetError))
        
        await viewModel.getCourseDetail(courseID: "123")
        
        Verify(interactor, 1, .getCourseDetails(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.slowOrNoInternetConnection)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testGetCourseDetailNoCacheError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        Given(interactor, .getCourseDetails(courseID: "123",
                                            willThrow: NoCachedDataError()))
        
        await viewModel.getCourseDetail(courseID: "123")
        
        Verify(interactor, 1, .getCourseDetails(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.slowOrNoInternetConnection)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testGetCourseDetailUnknownError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        Given(interactor, .getCourseDetails(courseID: "123",
                                            willThrow: NSError()))
        
        await viewModel.getCourseDetail(courseID: "123")
        
        Verify(interactor, 1, .getCourseDetails(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.unknownError)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testEnrollToCourseSuccess() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        Given(interactor, .enrollToCourse(courseID: "123", willReturn: true))
        
        await viewModel.enrollToCourse(id: "123")
        
        Verify(interactor, 1, .enrollToCourse(courseID: .any))
        Verify(analytics, .courseEnrollClicked(courseId: .any, courseName: .any))
        Verify(analytics, .courseEnrollSuccess(courseId: .any, courseName: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
    }
    
    func testEnrollToCourseUnknownError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        Given(interactor, .enrollToCourse(courseID: "123",
                                          willThrow: AFError.explicitlyCancelled))
        
        await viewModel.enrollToCourse(id: "123")
        
        Verify(interactor, 1, .enrollToCourse(courseID: .any))
        Verify(analytics, .courseEnrollClicked(courseId: .any, courseName: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.unknownError)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testEnrollToCourseNoInternetError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        let noInternetError = AFError.sessionInvalidated(error: URLError(.notConnectedToInternet))

        Given(interactor, .enrollToCourse(courseID: "123",
                                          willThrow: noInternetError))
        
        await viewModel.enrollToCourse(id: "123")
        
        Verify(interactor, 1, .enrollToCourse(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.slowOrNoInternetConnection)
        XCTAssertTrue(viewModel.showError)
    }
    
    func testEnrollToCourseNoCacheError() async throws {
        let interactor = CourseInteractorProtocolMock()
        let router = CourseRouterMock()
        let analytics = CourseAnalyticsMock()
        let config = ConfigMock()
        let cssInjector = CSSInjectorMock()
        let connectivity = ConnectivityProtocolMock()
        
        Given(connectivity, .isInternetAvaliable(getter: true))
        
        let viewModel = CourseDetailsViewModel(interactor: interactor,
                                               router: router,
                                               analytics: analytics,
                                               config: config,
                                               cssInjector: cssInjector,
                                               connectivity: connectivity)
        
        Given(interactor, .enrollToCourse(courseID: "123",
                                          willThrow: NoCachedDataError()))
        
        await viewModel.enrollToCourse(id: "123")
        
        Verify(interactor, 1, .enrollToCourse(courseID: .any))
        
        XCTAssertFalse(viewModel.isShowProgress)
        XCTAssertEqual(viewModel.errorMessage, CoreLocalization.Error.slowOrNoInternetConnection)
        XCTAssertTrue(viewModel.showError)
    }
    
}
