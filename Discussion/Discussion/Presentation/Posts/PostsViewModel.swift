//
//  PostsViewModel.swift
//  Discussion
//
//  Created by  Stepanok Ivan on 13.10.2022.
//

import Foundation
import SwiftUI
import Combine
import Core

public extension ThreadsFilter {
    
    var localizedValue: String {
        switch self {
        case .allThreads:
            return DiscussionLocalization.Posts.Filter.allPosts
        case .unread:
            return DiscussionLocalization.Posts.Filter.unread
        case .unanswered:
            return DiscussionLocalization.Posts.Filter.unanswered
        }
    }
}

public class PostsViewModel: ObservableObject {
    
    public var nextPage = 1
    public var totalPages = 1
    public private(set) var fetchInProgress = false
    
    public enum ButtonType {
        case sort
        case filter
    }
    
    @Published private(set) var isShowProgress = false
    @Published var showError: Bool = false
    @Published var filteredPosts: [DiscussionPost] = []
    @Published var filterTitle: ThreadsFilter = .allThreads {
        willSet {
            if let courseID {
              resetPosts()
                Task {
                    _ = await getPosts(courseID: courseID, pageNumber: 1)
                }
            }
        }
    }
    @Published var sortTitle: SortType = .recentActivity {
       willSet {
           if let courseID {
             resetPosts()
               Task {
                   _ = await getPosts(courseID: courseID, pageNumber: 1)
               }
           }
       }
   }
    @Published var filterButtons: [ActionSheet.Button] = []
    
    public var courseID: String?
    var errorMessage: String? {
        didSet {
            withAnimation {
                showError = errorMessage != nil
            }
        }
    }
    
    public var type: ThreadType!
    public var topics: Topics?
    private var topicsFetched: Bool = false
    private var discussionPosts: [DiscussionPost] = []
    private var threads: ThreadLists = ThreadLists(threads: [])
    private let interactor: DiscussionInteractorProtocol
    private let router: DiscussionRouter
    private let config: Config
    internal let postStateSubject = CurrentValueSubject<PostState?, Never>(nil)
    private var cancellable: AnyCancellable?
    
    public init(interactor: DiscussionInteractorProtocol,
                router: DiscussionRouter,
                config: Config) {
        self.interactor = interactor
        self.router = router
        self.config = config
        
        cancellable = postStateSubject
            .receive(on: RunLoop.main)
            .sink(receiveValue: { [weak self] state in
                guard let self, let state else { return }
                switch state {
                case let .followed(id, followed):
                    self.updatePostFollowedState(id: id, followed: followed)
                case let .replyAdded(id):
                    self.updatePostRepliesCountState(id: id)
                case let .readed(id):
                    self.updateUnreadCommentsCount(id: id)
                case let .liked(id, voted, voteCount):
                    self.updatePostLikedState(id: id, voted: voted, voteCount: voteCount)
                case let .reported(id, reported):
                    self.updatePostReportedState(id: id, reported: reported)
                }
            })
    }
    
    public func resetPosts() {
        filteredPosts = []
        discussionPosts = []
        threads.threads = []
        nextPage = 1
        totalPages = 1
    }
    
    public func generateButtons(type: ButtonType) {
        switch type {
        case .sort:
            self.filterButtons = [
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Sort.recentActivity)) {
                    self.sortTitle = .recentActivity
                    self.filteredPosts = self.discussionPosts
                },
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Sort.mostActivity)) {
                    self.sortTitle = .mostActivity
                    self.filteredPosts = self.discussionPosts
                },
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Sort.mostVotes)) {
                    self.sortTitle = .mostVotes
                    self.filteredPosts = self.discussionPosts
                },
                .cancel()
            ]
        case .filter:
            self.filterButtons = [
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Filter.allPosts)) {
                    self.filterTitle = .allThreads
                    self.filteredPosts = self.discussionPosts
                },
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Filter.unread)) {
                    self.filterTitle = .unread
                    self.filteredPosts = self.discussionPosts
                },
                ActionSheet.Button.default(Text(DiscussionLocalization.Posts.Filter.unanswered)) {
                    self.filterTitle = .unanswered
                    self.filteredPosts = self.discussionPosts
                },
                .cancel()
            ]
        }
    }
    
    func generatePosts(threads: ThreadLists?) -> [DiscussionPost] {
        var result: [DiscussionPost] = []
        if let threads = threads?.threads {
            for thread in threads {
                result.append(thread.discussionPost(action: { [weak self] in
                    guard let self, let actualThread = self.threads.threads
                        .first(where: {$0.id  == thread.id }) else { return }
                    
                    self.router.showThread(thread: actualThread, postStateSubject: self.postStateSubject)
                }))
            }
        }
        
        return result
    }
    
    @MainActor
    func getPostsPagination(courseID: String, index: Int, withProgress: Bool = true) async {
        if !fetchInProgress {
            if totalPages > 1 {
                if index == filteredPosts.count - 3 {
                    if totalPages != 1 {
                        if nextPage <= totalPages {
                            _ = await getPosts(courseID: courseID,
                                               pageNumber: self.nextPage,
                                               withProgress: withProgress)
                        }
                    }
                }
            }
        }
    }
    
    @MainActor
    public func getPosts(courseID: String, pageNumber: Int, withProgress: Bool = true) async -> Bool {
        fetchInProgress = true
        isShowProgress = withProgress
        do {
            switch type {
            case .allPosts:
                threads.threads += try await interactor
                    .getThreadsList(courseID: courseID,
                                    type: .allPosts,
                                    sort: sortTitle,
                                    filter: filterTitle,
                                    page: pageNumber).threads
                if threads.threads.indices.contains(0) {
                    self.totalPages = threads.threads[0].numPages
                    self.nextPage += 1
                    fetchInProgress = false
                }
            case .followingPosts:
                threads.threads += try await interactor
                    .getThreadsList(courseID: courseID,
                                    type: .followingPosts,
                                    sort: sortTitle,
                                    filter: filterTitle,
                                    page: pageNumber).threads
                if threads.threads.indices.contains(0) {
                    self.totalPages = threads.threads[0].numPages
                    self.nextPage += 1
                    fetchInProgress = false
                }
            case .nonCourseTopics:
                threads.threads += try await interactor
                    .getThreadsList(courseID: courseID,
                                    type: .nonCourseTopics,
                                    sort: sortTitle,
                                    filter: filterTitle,
                                    page: pageNumber).threads
                if threads.threads.indices.contains(0) {
                    self.totalPages = threads.threads[0].numPages
                    self.nextPage += 1
                    fetchInProgress = false
                }
            case .courseTopics(topicID: let topicID):
                threads.threads += try await interactor
                    .getThreadsList(courseID: courseID,
                                    type: .courseTopics(topicID: topicID),
                                    sort: sortTitle,
                                    filter: filterTitle,
                                    page: pageNumber).threads
                if threads.threads.indices.contains(0) {
                    self.totalPages = threads.threads[0].numPages
                    self.nextPage += 1
                    fetchInProgress = false
                }
            case .none:
                isShowProgress = false
                return false
            }
            discussionPosts = generatePosts(threads: threads)
            filteredPosts = discussionPosts
            self.filteredPosts = self.discussionPosts
            isShowProgress = false
            return true
        } catch let error {
            isShowProgress = false
            if error.isInternetError {
                errorMessage = CoreLocalization.Error.slowOrNoInternetConnection
            } else {
                errorMessage = CoreLocalization.Error.unknownError
            }
            return false
        }
    }
    
    private func updateUnreadCommentsCount(id: String) {
        var threads = threads.threads
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.unreadCommentCount = 0
        threads[index] = thread
        
        self.threads = ThreadLists(threads: threads)
        discussionPosts = generatePosts(threads: self.threads)
        self.filteredPosts = self.discussionPosts
    }
    
    private func updatePostFollowedState(id: String, followed: Bool) {
        var threads = threads.threads
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.following = followed
        threads[index] = thread
        
        self.threads = ThreadLists(threads: threads)
        discussionPosts = generatePosts(threads: self.threads)
        self.filteredPosts = self.discussionPosts
    }
    
    private func updatePostLikedState(id: String, voted: Bool, voteCount: Int) {
        var threads = threads.threads
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.voted = voted
        thread.voteCount = voteCount
        threads[index] = thread
        
        self.threads = ThreadLists(threads: threads)
        discussionPosts = generatePosts(threads: self.threads)
        self.filteredPosts = self.discussionPosts
    }
    
    private func updatePostReportedState(id: String, reported: Bool) {
        var threads = threads.threads
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.abuseFlagged = reported
        threads[index] = thread
        
        self.threads = ThreadLists(threads: threads)
        discussionPosts = generatePosts(threads: self.threads)
        self.filteredPosts = self.discussionPosts
    }
    
    private func updatePostRepliesCountState(id: String) {
        var threads = threads.threads
        guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
        var thread = threads[index]
        thread.commentCount += 1
        thread.updatedAt = Date()
        threads[index] = thread
        
        self.threads = ThreadLists(threads: threads)
        discussionPosts = generatePosts(threads: self.threads)
        self.filteredPosts = self.discussionPosts
    }
}
