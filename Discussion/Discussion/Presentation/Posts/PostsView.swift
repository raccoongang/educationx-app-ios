//
//  PostsView.swift
//  Discussion
//
//  Created by  Stepanok Ivan on 13.10.2022.
//

import Foundation
import SwiftUI
import Core

public struct PostsView: View {
    
    @ObservedObject private var viewModel: PostsViewModel
    @State private var isShowProgress: Bool = true
    @State private var showingAlert = false
    @State private var listAnimation: Animation?
    private let router: DiscussionRouter
    private let title: String
    private let currentBlockID: String
    private let courseID: String
    private var showTopMenu: Bool
    
    public init(courseID: String, currentBlockID: String, topics: Topics, title: String, type: ThreadType,
                viewModel: PostsViewModel, router: DiscussionRouter, showTopMenu: Bool = true) {
        self.courseID = courseID
        self.title = title
        self.currentBlockID = currentBlockID
        self.router = router
        self.showTopMenu = showTopMenu
        self.viewModel = viewModel
        self.viewModel.courseID = courseID
        self.viewModel.topics = topics
        viewModel.type = type
        Task {
            await viewModel.getPosts(courseID: courseID, pageNumber: 1, withProgress: true)
        }
    }
    
    public init(courseID: String, router: DiscussionRouter, viewModel: PostsViewModel) {
        self.courseID = courseID
        self.title = ""
        self.currentBlockID = ""
        self.router = router
        self.viewModel = viewModel
        Task {
            await viewModel.getPosts(courseID: courseID, pageNumber: 1, withProgress: true)
        }
        self.showTopMenu = true
        self.viewModel.courseID = courseID
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            
            // MARK: - Page name
                VStack(alignment: .center) {
                    if showTopMenu {
                        NavigationBar(title: title,
                        leftButtonAction: { router.back() })
                    }
                    // MARK: - Page Body
                    ScrollViewReader { scroll in
                        VStack {
                            ZStack(alignment: .top) {
                                VStack {
                                    HStack(alignment: .top) {
                                        VStack {
                                            HStack {
                                                Group {
                                                    Button(action: {
                                                        listAnimation = .easeIn
                                                        viewModel.generateButtons(type: .filter)
                                                        showingAlert = true
                                                    }, label: {
                                                        CoreAssets.filter.swiftUIImage
                                                        Text(viewModel.filterTitle.localizedValue)
                                                    })
                                                    Spacer()
                                                    Button(action: {
                                                        listAnimation = .easeIn
                                                        viewModel.generateButtons(type: .sort)
                                                        showingAlert = true
                                                    }, label: {
                                                        CoreAssets.sort.swiftUIImage
                                                        Text(viewModel.sortTitle.localizedValue)
                                                    })
                                                }.foregroundColor(CoreAssets.accentColor.swiftUIColor)
                                            } .font(Theme.Fonts.labelMedium)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 12)
                                                .shadow(color: CoreAssets.shadowColor.swiftUIColor,
                                                        radius: 12, y: 4)
                                                .background(
                                                    CoreAssets.background.swiftUIColor
                                                )
                                            Divider().offset(y: -8)
                                        }
                                    }.frameLimit()
                                    RefreshableScrollViewCompat(action: {
                                        listAnimation = nil
                                        viewModel.resetPosts()
                                        _ = await viewModel.getPosts(courseID: courseID,
                                                                     pageNumber: 1,
                                                                     withProgress: isIOS14)
                                    }) {
                                        LazyVStack {
                                            VStack {}.frame(height: 1)
                                                .id(1)
                                            let posts = Array(viewModel.filteredPosts.enumerated())
                                            HStack {
                                                Text(title)
                                                    .font(Theme.Fonts.titleLarge)
                                                    .foregroundColor(CoreAssets.textPrimary.swiftUIColor)
                                                    .padding(.horizontal, 24)
                                                    .padding(.top, 12)
                                                Spacer()
                                            }
                                            ForEach(posts, id: \.offset) { index, post in
                                                PostCell(post: post).padding(24)
                                                    .id(UUID())
                                                    .onAppear {
                                                        Task {
                                                            await viewModel.getPostsPagination(courseID: self.courseID, index: index)
                                                        }
                                                    }
                                                if posts.last?.element != post {
                                                    Divider().padding(.horizontal, 24)
                                                }
                                            }
                                            Spacer(minLength: 84)
                                        }
                                    }
                                }.frameLimit()
                                    .animation(listAnimation)
                                    .onRightSwipeGesture {
                                        router.back()
                                    }
                                
                                VStack {
                                    Spacer()
                                    Button(action: {
                                        router.createNewThread(courseID: courseID,
                                                               selectedTopic: currentBlockID,
                                                               onPostCreated: {
                                            reloadPage(onSuccess: {
                                                withAnimation {
                                                    scroll.scrollTo(1)
                                                }
                                            })
                                        })
                                    }, label: {
                                        VStack {
                                            HStack(alignment: .center) {
                                                CoreAssets.addComment.swiftUIImage
                                                    .font(Theme.Fonts.labelLarge)
                                                Text(DiscussionLocalization.Posts.createNewPost)
                                            }.frame(maxHeight: 42)
                                                .padding(.horizontal, 20)
                                        }
                                        .foregroundColor(.white)
                                        .background(
                                            Theme.Shapes.buttonShape
                                                .foregroundColor(CoreAssets.accentColor.swiftUIColor)
                                        )
                                        .padding(.bottom, 30)
                                    })
                                }
                            }
                        }.frame(maxWidth: .infinity)
                    }
                }
            if viewModel.isShowProgress {
                VStack(alignment: .center) {
                    ProgressBar(size: 40, lineWidth: 8)
                        .padding(.horizontal)
                }.frame(maxWidth: .infinity,
                        maxHeight: .infinity)
            }
        }
        .background(
            CoreAssets.background.swiftUIColor
                .ignoresSafeArea()
        )
        // MARK: - Action Sheet
        .actionSheet(isPresented: $showingAlert, content: {
            ActionSheet(title: Text(DiscussionLocalization.Posts.Alert.makeSelection), buttons: viewModel.filterButtons)
        })
    }
    
    @MainActor
    private func reloadPage(onSuccess: @escaping () -> Void) {
        Task {
            listAnimation = nil
            viewModel.resetPosts()
            _ = await viewModel.getPosts(courseID: courseID,
                                         pageNumber: 1,
                                         withProgress: isIOS14)
            onSuccess()
        }
    }
}

#if DEBUG
// swiftlint:disable all
struct PostsView_Previews: PreviewProvider {
    static var previews: some View {
        let topics = Topics(coursewareTopics: [], nonCoursewareTopics: [])
        let router = DiscussionRouterMock()
        let vm = PostsViewModel(
            interactor: DiscussionInteractor.mock,
            router: router,
            config: ConfigMock()
        )
        
        PostsView(courseID: "course_id",
                  currentBlockID: "123",
                  topics: topics,
                  title: "Lesson question",
                  type: .allPosts,
                  viewModel: vm,
                  router: router)
        .preferredColorScheme(.light)
        .previewDisplayName("PostsView Light")
        .loadFonts()
        
        PostsView(courseID: "course_id",
                  currentBlockID: "123",
                  topics: topics,
                  title: "Lesson question",
                  type: .allPosts,
                  viewModel: vm,
                  router: router)
        .preferredColorScheme(.dark)
        .previewDisplayName("PostsView Dark")
        .loadFonts()
        
    }
}
#endif

public struct PostCell: View {
    
    private var post: DiscussionPost
    
    public init(post: DiscussionPost) {
        self.post = post
    }
    
    public var body: some View {
        Button(action: {
            post.action()
        }, label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    post.type.getImage()
                    Text(post.type.localizedValue.capitalized)
                    Spacer()
                    if post.unreadCommentCount - 1 > 0 {
                        CoreAssets.unread.swiftUIImage
                        Text("\(post.unreadCommentCount - 1)")
                        Text(DiscussionLocalization.missedPostsCount(post.unreadCommentCount - 1))
                    }
                }.font(Theme.Fonts.labelSmall)
                    .foregroundColor(CoreAssets.textSecondary.swiftUIColor)
                Text(post.title)
                    .multilineTextAlignment(.leading)
                    .font(Theme.Fonts.labelLarge)
                    .foregroundColor(CoreAssets.textPrimary.swiftUIColor)
                Text("\(DiscussionLocalization.Post.lastPost) \(post.lastPostDateFormatted)")
                    .font(Theme.Fonts.labelSmall)
                    .foregroundColor(CoreAssets.textSecondary.swiftUIColor)
                HStack {
                    CoreAssets.responses.swiftUIImage
                    Text("\(post.replies - 1)")
                    Text(DiscussionLocalization.responsesCount(post.replies - 1))
                        .font(Theme.Fonts.labelLarge)
                }
                .foregroundColor(CoreAssets.accentColor.swiftUIColor)
            }
        })
    }
}
