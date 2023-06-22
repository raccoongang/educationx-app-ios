//
//  CourseRepository.swift
//  Course
//
//  Created by  Stepanok Ivan on 26.09.2022.
//

import Foundation
import Core

public protocol CourseRepositoryProtocol {
    func getCourseDetails(courseID: String) async throws -> CourseDetails
    func getCourseBlocks(courseID: String) async throws -> CourseStructure
    func getCourseDetailsOffline(courseID: String) async throws -> CourseDetails
    func getCourseBlocksOffline(courseID: String) throws -> CourseStructure
    func enrollToCourse(courseID: String) async throws -> Bool
    func blockCompletionRequest(courseID: String, blockID: String) async throws
    func getHandouts(courseID: String) async throws -> String?
    func getUpdates(courseID: String) async throws -> [CourseUpdate]
    func resumeBlock(courseID: String) async throws -> ResumeBlock
    func getSubtitles(url: String, selectedLanguage: String) async throws -> String
}

public class CourseRepository: CourseRepositoryProtocol {
    
    private let api: API
    private let appStorage: AppStorage
    private let config: Config
    private let persistence: CoursePersistenceProtocol
    
    public init(api: API,
                appStorage: AppStorage,
                config: Config,
                persistence: CoursePersistenceProtocol) {
        self.api = api
        self.appStorage = appStorage
        self.config = config
        self.persistence = persistence
    }
    
    public func getCourseDetails(courseID: String) async throws -> CourseDetails {
        let response = try await api.requestData(CourseDetailsEndpoint.getCourseDetail(courseID: courseID))
            .mapResponse(DataLayer.CourseDetailsResponse.self)
            .domain(baseURL: config.baseURL.absoluteString)
        persistence.saveCourseDetails(course: response)
        return response
    }
    
    public func getCourseDetailsOffline(courseID: String) async throws -> CourseDetails {
        return try persistence.loadCourseDetails(courseID: courseID)
    }
        
    public func getCourseBlocks(courseID: String) async throws -> CourseStructure {
        let structure = try await api.requestData(
            CourseDetailsEndpoint.getCourseBlocks(courseID: courseID, userName: appStorage.user?.username ?? "")
        ).mapResponse(DataLayer.CourseStructure.self)
        persistence.saveCourseStructure(structure: structure)
        let parsedStructure = parseCourseStructure(structure: structure)
        return parsedStructure
    }
    
    public func getCourseBlocksOffline(courseID: String) throws -> CourseStructure {
        let localData = try persistence.loadCourseStructure(courseID: courseID)
        return parseCourseStructure(structure: localData)
    }
    
    public func enrollToCourse(courseID: String) async throws -> Bool {
        let enroll = try await api.request(CourseDetailsEndpoint.enrollToCourse(courseID: courseID))
        if enroll.statusCode == 200 {
            return true
        } else {
            return false
        }
    }
    
    public func blockCompletionRequest(courseID: String, blockID: String) async throws {
        try await api.requestData(CourseDetailsEndpoint.blockCompletionRequest(
            username: appStorage.user?.username ?? "",
            courseID: courseID,
            blockID: blockID)
        )
    }
    
    public func getHandouts(courseID: String) async throws -> String? {
        return try await api.requestData(CourseDetailsEndpoint.getHandouts(courseID: courseID))
            .mapResponse(DataLayer.HandoutsResponse.self)
            .handoutsHtml
    }
    
    public func getUpdates(courseID: String) async throws -> [CourseUpdate] {
        return try await api.requestData(CourseDetailsEndpoint.getUpdates(courseID: courseID))
            .mapResponse(DataLayer.CourseUpdates.self).map { $0.domain }
    }
    
    public func resumeBlock(courseID: String) async throws -> ResumeBlock {
        return try await api.requestData(CourseDetailsEndpoint
            .resumeBlock(userName: appStorage.user?.username ?? "", courseID: courseID))
        .mapResponse(DataLayer.ResumeBlock.self).domain
    }
    
    public func getSubtitles(url: String, selectedLanguage: String) async throws -> String {
        if let subtitlesOffline = persistence.loadSubtitles(url: url + selectedLanguage) {
            return subtitlesOffline
        } else {
            let result = try await api.requestData(CourseDetailsEndpoint.getSubtitles(
                url: url,
                selectedLanguage: selectedLanguage
            ))
            let subtitles = String(data: result, encoding: .utf8) ?? ""
            persistence.saveSubtitles(url: url + selectedLanguage, subtitlesString: subtitles)
            return subtitles
        }
    }
    
    private func parseCourseStructure(structure: DataLayer.CourseStructure) -> CourseStructure {
        let blocks = Array(structure.dict.values)
        let course = blocks.first(where: {$0.type == BlockType.course.rawValue })!
        let descendants = course.descendants ?? []
        var childs: [CourseChapter] = []
        for descend in descendants {
            let chapter = parseChapters(id: descend, blocks: blocks)
            childs.append(chapter)
        }
        
        return CourseStructure(id: course.id,
                               graded: course.graded,
                               completion: course.completion ?? 0,
                               viewYouTubeUrl: course.userViewData?.encodedVideo?.youTube?.url ?? "",
                               encodedVideo: course.userViewData?.encodedVideo?.fallback?.url ?? "",
                               displayName: course.displayName,
                               topicID: course.userViewData?.topicID,
                               childs: childs,
                               media: structure.media,
                               certificate: structure.certificate?.domain)
    }
    
    private func parseChapters(id: String, blocks: [DataLayer.CourseBlock]) -> CourseChapter {
        let chapter = blocks.first(where: {$0.id == id })!
        let descendants = chapter.descendants ?? []
        var childs: [CourseSequential] = []
        for descend in descendants {
            let chapter = parseSequential(id: descend, blocks: blocks)
            childs.append(chapter)
        }
        return CourseChapter(blockId: chapter.blockId,
                             id: chapter.id,
                             displayName: chapter.displayName,
                             type: BlockType(rawValue: chapter.type) ?? .unknown,
                             childs: childs)
        
    }
    
    private func parseSequential(id: String, blocks: [DataLayer.CourseBlock]) -> CourseSequential {
        let sequential = blocks.first(where: {$0.id == id })!
        let descendants = sequential.descendants ?? []
        var childs: [CourseVertical] = []
        for descend in descendants {
            let vertical = parseVerticals(id: descend, blocks: blocks)
            childs.append(vertical)
        }
        return CourseSequential(blockId: sequential.blockId,
                                id: sequential.id,
                                displayName: sequential.displayName,
                                type: BlockType(rawValue: sequential.type) ?? .unknown,
                                completion: sequential.completion ?? 0,
                                childs: childs)
    }
    
    private func parseVerticals(id: String, blocks: [DataLayer.CourseBlock]) -> CourseVertical {
        let sequential = blocks.first(where: {$0.id == id })!
        let descendants = sequential.descendants ?? []
        var childs: [CourseBlock] = []
        for descend in descendants {
            let block = parseBlock(id: descend, blocks: blocks)
            childs.append(block)
        }
        return CourseVertical(blockId: sequential.blockId,
                                id: sequential.id,
                                displayName: sequential.displayName,
                                type: BlockType(rawValue: sequential.type) ?? .unknown,
                                completion: sequential.completion ?? 0,
                                childs: childs)
    }
    
    private func parseBlock(id: String, blocks: [DataLayer.CourseBlock]) -> CourseBlock {
        let block = blocks.first(where: {$0.id == id })!
        let subtitles = block.userViewData?.transcripts?.map {
            let url = $0.value
                .replacingOccurrences(of: config.baseURL.absoluteString, with: "")
                .replacingOccurrences(of: "?lang=\($0.key)", with: "")
            return SubtitleUrl(language: $0.key, url: url)
        }
            
        return CourseBlock(blockId: block.blockId,
                           id: block.id,
                           topicId: block.userViewData?.topicID,
                           graded: block.graded,
                           completion: block.completion ?? 0,
                           type: BlockType(rawValue: block.type) ?? .unknown,
                           displayName: block.displayName,
                           studentUrl: block.studentUrl,
                           subtitles: subtitles,
                           videoUrl: block.userViewData?.encodedVideo?.fallback?.url,
                           youTubeUrl: block.userViewData?.encodedVideo?.youTube?.url)
    }
    
}

// Mark - For testing and SwiftUI preview
#if DEBUG
// swiftlint:disable all
class CourseRepositoryMock: CourseRepositoryProtocol {
    func resumeBlock(courseID: String) async throws -> ResumeBlock {
        ResumeBlock(blockID: "123")
    }
    
    func getHandouts(courseID: String) async throws -> String? {
        return "Test Handouts"
    }
    
    func getUpdates(courseID: String) async throws -> [CourseUpdate] {
        return [CourseUpdate(id: 1, date: "Date", content: "content", status: "status")]
    }
    
    
    func getCourseDetailsOffline(courseID: String) async throws -> CourseDetails {
        return CourseDetails(
            courseID: "courseID",
            org: "Organization",
            courseTitle: "Course title",
            courseDescription: "Course description",
            courseStart: Date(iso8601: "2021-05-26T12:13:14Z"),
            courseEnd: Date(iso8601: "2022-05-26T12:13:14Z"),
            enrollmentStart: nil,
            enrollmentEnd: nil,
            isEnrolled: false,
            overviewHTML: "<b>Course description</b><br><br>Lorem ipsum",
            courseBannerURL: "courseBannerURL",
            courseVideoURL: nil
        )
    }
    
    func getCourseBlocksOffline(courseID: String) throws -> CourseStructure {
        let decoder = JSONDecoder()
        let jsonData = Data(courseStructureJson.utf8)
        let courseBlocks = try decoder.decode(DataLayer.CourseStructure.self, from: jsonData)
        return parseCourseStructure(structure: courseBlocks)
    }
    
    public  func getCourseDetails(courseID: String) async throws -> CourseDetails {
        return CourseDetails(
            courseID: "courseID",
            org: "Organization",
            courseTitle: "Course title",
            courseDescription: "Course description",
            courseStart: Date(iso8601: "2021-05-26T12:13:14Z"),
            courseEnd: Date(iso8601: "2022-05-26T12:13:14Z"),
            enrollmentStart: nil,
            enrollmentEnd: nil,
            isEnrolled: false,
            overviewHTML: "<b>Course description</b><br><br>Lorem ipsum",
            courseBannerURL: "courseBannerURL",
            courseVideoURL: nil
        )
    }
        
    public  func getCourseBlocks(courseID: String) async throws -> CourseStructure {
        do {
//            let decoder = JSONDecoder()
//            let jsonData = Data(courseStructureJson.utf8)
            let courseBlocks = try courseStructureJson.data(using: .utf8)!.mapResponse(DataLayer.CourseStructure.self)

//            let courseBlocks = try decoder.decode(DataLayer.CourseStructure.self, from: jsonData)
            return parseCourseStructure(structure: courseBlocks)
        } catch {
            throw error
        }
    }
    
    public  func enrollToCourse(courseID: String) async throws -> Bool {
        return true
    }
    
    public  func blockCompletionRequest(courseID: String, blockID: String) {
        
    }
    
    public func getSubtitles(url: String, selectedLanguage: String) async throws -> String {
        return """
0
00:00:00,350 --> 00:00:05,230
GREGORY NAGY: In hour zero, where I try to introduce Homeric poetry to
1
00:00:05,230 --> 00:00:11,060
people who may never have been exposed to the Iliad and the Odyssey even in
2
00:00:11,060 --> 00:00:20,290
translation, my idea was to get a sense of the medium, which is not a
3
00:00:20,290 --> 00:00:25,690
readable medium because Homeric poetry, in its historical context, was
4
00:00:25,690 --> 00:00:30,210
meant to be heard, not read.
5
00:00:30,210 --> 00:00:34,760
And there are various ways of describing it-- call it oral poetry or
"""
    }
    
    private func parseCourseStructure(structure: DataLayer.CourseStructure) -> CourseStructure {
        let blocks = Array(structure.dict.values)
        let course = blocks.first(where: {$0.type == BlockType.course.rawValue })!
        let descendants = course.descendants ?? []
        var childs: [CourseChapter] = []
        for descend in descendants {
            let chapter = parseChapters(id: descend, blocks: blocks)
            childs.append(chapter)
        }
        
        return CourseStructure(id: course.id,
                               graded: course.graded,
                               completion: course.completion ?? 0,
                               viewYouTubeUrl: course.userViewData?.encodedVideo?.youTube?.url ?? "",
                               encodedVideo: course.userViewData?.encodedVideo?.fallback?.url ?? "",
                               displayName: course.displayName,
                               topicID: course.userViewData?.topicID,
                               childs: childs,
                               media: structure.media,
                               certificate: structure.certificate?.domain)
    }
    
    private func parseChapters(id: String, blocks: [DataLayer.CourseBlock]) -> CourseChapter {
        let chapter = blocks.first(where: {$0.id == id })!
        let descendants = chapter.descendants ?? []
        var childs: [CourseSequential] = []
        for descend in descendants {
            let chapter = parseSequential(id: descend, blocks: blocks)
            childs.append(chapter)
        }
        return CourseChapter(blockId: chapter.blockId,
                             id: chapter.id,
                             displayName: chapter.displayName,
                             type: BlockType(rawValue: chapter.type) ?? .unknown,
                             childs: childs)
    }
    
    private func parseSequential(id: String, blocks: [DataLayer.CourseBlock]) -> CourseSequential {
        let sequential = blocks.first(where: {$0.id == id })!
        let descendants = sequential.descendants ?? []
        var childs: [CourseVertical] = []
        for descend in descendants {
            let vertical = parseVerticals(id: descend, blocks: blocks)
            childs.append(vertical)
        }
        return CourseSequential(blockId: sequential.blockId,
                                id: sequential.id,
                                displayName: sequential.displayName,
                                type: BlockType(rawValue: sequential.type) ?? .unknown,
                                completion: sequential.completion ?? 0,
                                childs: childs)
    }
    
    private func parseVerticals(id: String, blocks: [DataLayer.CourseBlock]) -> CourseVertical {
        let sequential = blocks.first(where: {$0.id == id })!
        let descendants = sequential.descendants ?? []
        var childs: [CourseBlock] = []
        for descend in descendants {
            let block = parseBlock(id: descend, blocks: blocks)
            childs.append(block)
        }
        return CourseVertical(blockId: sequential.blockId,
                                id: sequential.id,
                                displayName: sequential.displayName,
                                type: BlockType(rawValue: sequential.type) ?? .unknown,
                                completion: sequential.completion ?? 0,
                                childs: childs)
    }
    
    private func parseBlock(id: String, blocks: [DataLayer.CourseBlock]) -> CourseBlock {
        let block = blocks.first(where: {$0.id == id })!
        let subtitles = block.userViewData?.transcripts?.map {
            let url = $0.value
//                .replacingOccurrences(of: config.baseURL.absoluteString, with: "")
//                .replacingOccurrences(of: "?lang=\($0.key)", with: "")
            return SubtitleUrl(language: $0.key, url: url)
        }
            
        return CourseBlock(blockId: block.blockId,
                           id: block.id,
                           topicId: block.userViewData?.topicID,
                           graded: block.graded,
                           completion: block.completion ?? 0,
                           type: BlockType(rawValue: block.type) ?? .unknown,
                           displayName: block.displayName,
                           studentUrl: block.studentUrl,
                           subtitles: subtitles,
                           videoUrl: block.userViewData?.encodedVideo?.fallback?.url,
                           youTubeUrl: block.userViewData?.encodedVideo?.youTube?.url)
    }
    
    private let courseStructureJson: String = """
    {"root": "block-v1:QA+comparison+2022+type@course+block@course",
          "blocks": {
            "block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78": {
              "id": "block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78",
              "block_id": "be1704c576284ba39753c6f0ea4a4c78",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78",
              "type": "comparison",
              "display_name": "Comparison",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296",
              "block_id": "93acc543871e4c73bc20a72a64e93296",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296",
              "type": "problem",
              "display_name": "Dropdown with Hints and Feedback",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b": {
              "id": "block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b",
              "block_id": "06c17035106e48328ebcd042babcf47b",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b",
              "type": "comparison",
              "display_name": "Comparison",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58",
              "block_id": "c19e41b61db14efe9c45f1354332ae58",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58",
              "type": "problem",
              "display_name": "Text Input with Hints and Feedback",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb",
              "block_id": "0d96732f577b4ff68799faf8235d1bfb",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb",
              "type": "problem",
              "display_name": "Numerical Input with Hints and Feedback",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96",
              "block_id": "dd2e22fdf0724bd88c8b2e6b68dedd96",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96",
              "type": "problem",
              "display_name": "Blank Common Problem",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd",
              "block_id": "d1e091aa305741c5bedfafed0d269efd",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd",
              "type": "problem",
              "display_name": "Blank Common Problem",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7": {
              "id": "block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7",
              "block_id": "23e10dea806345b19b77997b4fc0eea7",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7",
              "type": "comparison",
              "display_name": "Comparison",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904": {
              "id": "block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904",
              "block_id": "29e7eddbe8964770896e4036748c9904",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904",
              "type": "vertical",
              "display_name": "Unit",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@comparison+block@be1704c576284ba39753c6f0ea4a4c78",
                "block-v1:QA+comparison+2022+type@problem+block@93acc543871e4c73bc20a72a64e93296",
                "block-v1:QA+comparison+2022+type@comparison+block@06c17035106e48328ebcd042babcf47b",
                "block-v1:QA+comparison+2022+type@problem+block@c19e41b61db14efe9c45f1354332ae58",
                "block-v1:QA+comparison+2022+type@problem+block@0d96732f577b4ff68799faf8235d1bfb",
                "block-v1:QA+comparison+2022+type@problem+block@dd2e22fdf0724bd88c8b2e6b68dedd96",
                "block-v1:QA+comparison+2022+type@problem+block@d1e091aa305741c5bedfafed0d269efd",
                "block-v1:QA+comparison+2022+type@comparison+block@23e10dea806345b19b77997b4fc0eea7"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6": {
              "id": "block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6",
              "block_id": "f468bb5c6e8641179e523c7fcec4e6d6",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6",
              "type": "sequential",
              "display_name": "Subsection",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@vertical+block@29e7eddbe8964770896e4036748c9904"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234",
              "block_id": "eaf91d8fc70547339402043ba1a1c234",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234",
              "type": "problem",
              "display_name": "Dropdown with Hints and Feedback",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751": {
              "id": "block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751",
              "block_id": "fac531c3f1f3400cb8e3b97eb2c3d751",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751",
              "type": "comparison",
              "display_name": "Comparison",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de": {
              "id": "block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de",
              "block_id": "74a1074024fe401ea305534f2241e5de",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de",
              "type": "html",
              "display_name": "Raw HTML",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-05-04T19:08:07Z",
                "html_data": "https://s3.eu-central-1.amazonaws.com/vso-dev-edx-sorage/htmlxblock/QA/comparison/html/74a1074024fe401ea305534f2241e5de/content_html.zip",
                "size": 576,
                "index_page": "index.html",
                "icon_class": "other"
              },
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca": {
              "id": "block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca",
              "block_id": "e5b2e105f4f947c5b76fb12c35da1eca",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca",
              "type": "vertical",
              "display_name": "Unit",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@problem+block@eaf91d8fc70547339402043ba1a1c234",
                "block-v1:QA+comparison+2022+type@comparison+block@fac531c3f1f3400cb8e3b97eb2c3d751",
                "block-v1:QA+comparison+2022+type@html+block@74a1074024fe401ea305534f2241e5de"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2": {
              "id": "block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2",
              "block_id": "d37cb0c5c2d24ddaacf3494760a055f2",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2",
              "type": "sequential",
              "display_name": "Another one subsection",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@vertical+block@e5b2e105f4f947c5b76fb12c35da1eca"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846": {
              "id": "block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846",
              "block_id": "abecaefe203c4c93b441d16cea3b7846",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846",
              "type": "chapter",
              "display_name": "Section",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@sequential+block@f468bb5c6e8641179e523c7fcec4e6d6",
                "block-v1:QA+comparison+2022+type@sequential+block@d37cb0c5c2d24ddaacf3494760a055f2"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de",
              "block_id": "a0c3ac29daab425f92a34b34eb2af9de",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de",
              "type": "pdf",
              "display_name": "PDF title",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9",
              "block_id": "bcd1b0f3015b4d3696b12f65a5d682f9",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9",
              "type": "pdf",
              "display_name": "PDF",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59",
              "block_id": "67d805daade34bd4b6ace607e6d48f59",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59",
              "type": "pdf",
              "display_name": "PDF",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974",
              "block_id": "828606a51f4e44198e92f86a45be7974",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974",
              "type": "pdf",
              "display_name": "PDF",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee",
              "block_id": "8646c3bc2184467b86e5ef01ecd452ee",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee",
              "type": "pdf",
              "display_name": "PDF",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1": {
              "id": "block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1",
              "block_id": "e2faa0e62223489e91a41700865c5fc1",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1",
              "type": "vertical",
              "display_name": "Unit",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@pdf+block@a0c3ac29daab425f92a34b34eb2af9de",
                "block-v1:QA+comparison+2022+type@pdf+block@bcd1b0f3015b4d3696b12f65a5d682f9",
                "block-v1:QA+comparison+2022+type@pdf+block@67d805daade34bd4b6ace607e6d48f59",
                "block-v1:QA+comparison+2022+type@pdf+block@828606a51f4e44198e92f86a45be7974",
                "block-v1:QA+comparison+2022+type@pdf+block@8646c3bc2184467b86e5ef01ecd452ee"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52": {
              "id": "block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52",
              "block_id": "0c5e89fa6d7a4fac8f7b26f2ca0bbe52",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52",
              "type": "problem",
              "display_name": "Checkboxes with Hints and Feedback",
              "graded": false,
              "student_view_multi_device": true,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4": {
              "id": "block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4",
              "block_id": "8ba437d8b20d416d91a2d362b0c940a4",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4",
              "type": "vertical",
              "display_name": "Unit",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@problem+block@0c5e89fa6d7a4fac8f7b26f2ca0bbe52"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d": {
              "id": "block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d",
              "block_id": "021f70794f7349998e190b060260b70d",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d",
              "type": "pdf",
              "display_name": "PDF",
              "graded": false,
              "student_view_data": {
                "last_modified": "2023-04-26T08:43:45Z",
                "url": "https://www.adobe.com/support/products/enterprise/knowledgecenter/media/c4611_sample_explain.pdf",
              },
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ],
              "completion": 0.0
            },
            "block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1": {
              "id": "block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1",
              "block_id": "2c344115d3554ac58c140ec86e591aa1",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1",
              "type": "vertical",
              "display_name": "Unit",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@pdf+block@021f70794f7349998e190b060260b70d"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe": {
              "id": "block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe",
              "block_id": "6c9c6ba663b54c0eb9cbdcd0c6b4bebe",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe",
              "type": "sequential",
              "display_name": "Subsection",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@vertical+block@e2faa0e62223489e91a41700865c5fc1",
                "block-v1:QA+comparison+2022+type@vertical+block@8ba437d8b20d416d91a2d362b0c940a4",
                "block-v1:QA+comparison+2022+type@vertical+block@2c344115d3554ac58c140ec86e591aa1"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7": {
              "id": "block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7",
              "block_id": "d5a4f1f2f5314288aae400c270fb03f7",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7",
              "type": "chapter",
              "display_name": "PDF",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@sequential+block@6c9c6ba663b54c0eb9cbdcd0c6b4bebe"
              ],
              "completion": 0
            },
            "block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf": {
              "id": "block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf",
              "block_id": "7ab45affb80f4846a60648ec6aff9fbf",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf",
              "type": "chapter",
              "display_name": "Section",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                
              ]
            },
            "block-v1:QA+comparison+2022+type@course+block@course": {
              "id": "block-v1:QA+comparison+2022+type@course+block@course",
              "block_id": "course",
              "lms_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@course+block@course",
              "legacy_web_url": "https://lms.lilac-vso-dev.raccoongang.com/courses/course-v1:QA+comparison+2022/jump_to/block-v1:QA+comparison+2022+type@course+block@course?experience=legacy",
              "student_view_url": "https://lms.lilac-vso-dev.raccoongang.com/xblock/block-v1:QA+comparison+2022+type@course+block@course",
              "type": "course",
              "display_name": "Comparison xblock test coursre",
              "graded": false,
              "student_view_multi_device": false,
              "block_counts": {
                "video": 0
              },
              "descendants": [
                "block-v1:QA+comparison+2022+type@chapter+block@abecaefe203c4c93b441d16cea3b7846",
                "block-v1:QA+comparison+2022+type@chapter+block@d5a4f1f2f5314288aae400c270fb03f7",
                "block-v1:QA+comparison+2022+type@chapter+block@7ab45affb80f4846a60648ec6aff9fbf"
              ],
              "completion": 0
            }
          },
          "id": "course-v1:QA+comparison+2022",
          "name": "Comparison xblock test coursre",
          "number": "comparison",
          "org": "QA",
          "start": "2022-01-01T00:00:00Z",
          "start_display": "01 january 2022 р.",
          "start_type": "timestamp",
          "end": null,
          "courseware_access": {
            "has_access": true,
            "error_code": null,
            "developer_message": null,
            "user_message": null,
            "additional_context_user_message": null,
            "user_fragment": null
          },
          "media": {
            "image": {
              "raw": "/asset-v1:QA+comparison+2022+type@asset+block@images_course_image.jpg",
              "small": "/asset-v1:QA+comparison+2022+type@asset+block@images_course_image.jpg",
              "large": "/asset-v1:QA+comparison+2022+type@asset+block@images_course_image.jpg"
            }
          },
          "certificate": {
            
          },
          "is_self_paced": false
        }
    """
}

#endif
