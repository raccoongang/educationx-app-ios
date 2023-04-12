//
//  CourseInteractor.swift
//  Course
//
//  Created by  Stepanok Ivan on 26.09.2022.
//

import Foundation
import Core

//sourcery: AutoMockable
public protocol CourseInteractorProtocol {
    func getCourseDetails(courseID: String) async throws -> CourseDetails
    func getCourseBlocks(courseID: String) async throws -> CourseStructure
    func getCourseVideoBlocks(fullStructure: CourseStructure) -> CourseStructure
    func getCourseDetailsOffline(courseID: String) async throws -> CourseDetails
    func getCourseBlocksOffline(courseID: String) async throws -> CourseStructure
    func enrollToCourse(courseID: String) async throws -> Bool
    func blockCompletionRequest(courseID: String, blockID: String) async throws
    func getHandouts(courseID: String) async throws -> String?
    func getUpdates(courseID: String) async throws -> [CourseUpdate]
    func resumeBlock(courseID: String) async throws -> ResumeBlock
    func getSubtitles(url: String) async throws -> String
}

public class CourseInteractor: CourseInteractorProtocol {
    
    private let repository: CourseRepositoryProtocol
    
    public init(repository: CourseRepositoryProtocol) {
        self.repository = repository
    }
    
    public func getCourseDetails(courseID: String) async throws -> CourseDetails {
        return try await repository.getCourseDetails(courseID: courseID)
    }
    
    public func getCourseBlocks(courseID: String) async throws -> CourseStructure {
        return try await repository.getCourseBlocks(courseID: courseID)
    }
    
    public func getCourseVideoBlocks(fullStructure course: CourseStructure) -> CourseStructure {
        var newChilds = [CourseChapter]()
        for chapter in course.childs {
            let newChapter = filterChapter(chapter: chapter)
            if !newChapter.childs.isEmpty {
                newChilds.append(newChapter)
            }
        }
        return CourseStructure(
            id: course.id,
            graded: course.graded,
            completion: course.completion,
            viewYouTubeUrl: course.viewYouTubeUrl,
            encodedVideo: course.encodedVideo,
            displayName: course.displayName,
            topicID: course.topicID,
            childs: newChilds,
            media: course.media,
            certificate: course.certificate
        )
    }
    
    public func getCourseDetailsOffline(courseID: String) async throws -> CourseDetails {
        return try await repository.getCourseDetailsOffline(courseID: courseID)
    }
    
    public func getCourseBlocksOffline(courseID: String) async throws -> CourseStructure {
        return try repository.getCourseBlocksOffline(courseID: courseID)
    }
    
    public func enrollToCourse(courseID: String) async throws -> Bool {
        return try await repository.enrollToCourse(courseID: courseID)
    }
    
    public func blockCompletionRequest(courseID: String, blockID: String) async throws {
        return try await repository.blockCompletionRequest(courseID: courseID, blockID: blockID)
    }
    
    public func getHandouts(courseID: String) async throws -> String? {
        return try await repository.getHandouts(courseID: courseID)
    }
    
    public func getUpdates(courseID: String) async throws -> [CourseUpdate] {
        return try await repository.getUpdates(courseID: courseID)
    }
    
    public func resumeBlock(courseID: String) async throws -> ResumeBlock {
        return try await repository.resumeBlock(courseID: courseID)
    }
        
    public func getSubtitles(url: String) async throws -> String {
        return try await repository.getSubtitles(url: url)
    }
    
    private func filterChapter(chapter: CourseChapter) -> CourseChapter {
        var newChilds = [CourseSequential]()
        for sequential in chapter.childs {
            let newSequential = filterSequential(sequential: sequential)
            if !newSequential.childs.isEmpty {
                newChilds.append(newSequential)
            }
        }
        return CourseChapter(
            blockId: chapter.blockId,
            id: chapter.id,
            displayName: chapter.displayName,
            type: chapter.type,
            childs: newChilds
        )
    }
    
    private func filterSequential(sequential: CourseSequential) -> CourseSequential {
        var newChilds = [CourseVertical]()
        for vertical in sequential.childs {
            let newVertical = filterVertical(vertical: vertical)
            if !newVertical.childs.isEmpty {
                newChilds.append(newVertical)
            }
        }
        return CourseSequential(
            blockId: sequential.blockId,
            id: sequential.id,
            displayName: sequential.displayName,
            type: sequential.type,
            completion: sequential.completion,
            childs: newChilds
        )
    }
    
    private func filterVertical(vertical: CourseVertical) -> CourseVertical {
        let newChilds = vertical.childs.filter { $0.type == .video }
        return CourseVertical(
            blockId: vertical.blockId,
            id: vertical.id,
            displayName: vertical.displayName,
            type: vertical.type,
            completion: vertical.completion,
            childs: newChilds
        )
    }
}

// Mark - For testing and SwiftUI preview
#if DEBUG
public extension CourseInteractor {
    static let mock = CourseInteractor(repository: CourseRepositoryMock())
}
#endif
