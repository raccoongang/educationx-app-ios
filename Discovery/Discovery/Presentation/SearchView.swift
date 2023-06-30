//
//  SearchView.swift
//  Discovery
//
//  Created by Paul Maul on 10.02.2023.
//

import SwiftUI
import Core

public struct SearchView: View {
    
    @ObservedObject
    private var viewModel: SearchViewModel<RunLoop>
    @State private var animated: Bool = false
    
    public init(viewModel: SearchViewModel<RunLoop>) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack(alignment: .top) {
            
            // MARK: - Page name
            VStack(alignment: .center) {
                NavigationBar(title: DiscoveryLocalization.search,
                                     leftButtonAction: {
                    viewModel.router.backWithFade()
                })
                
                HStack(spacing: 11) {
                    Image(systemName: "magnifyingglass")
                        .padding(.leading, 16)
                        .padding(.top, -1)
                        .foregroundColor(
                            viewModel.isSearchActive
                            ? CoreAssets.accentColor.swiftUIColor
                            : CoreAssets.textPrimary.swiftUIColor
                        )
                    
                    TextField(
                        !viewModel.isSearchActive
                        ? DiscoveryLocalization.search
                        : "",
                        text: $viewModel.searchText,
                        onEditingChanged: { editing in
                            viewModel.isSearchActive = editing
                        }
                    )
                    .introspectTextField { textField in
                        textField.becomeFirstResponder()
                    }
                    .foregroundColor(CoreAssets.textPrimary.swiftUIColor)
                    Spacer()
                    if !viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: { viewModel.searchText.removeAll() }, label: {
                            CoreAssets.clearInput.swiftUIImage
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                                .padding(.horizontal)
                        })
                        .foregroundColor(CoreAssets.styledButtonText.swiftUIColor)
                    }
                }
                .padding(.top, 3)
                .frame(minHeight: 48)
                .frame(maxWidth: 532)
                .background(
                    Theme.Shapes.textInputShape
                        .fill(viewModel.isSearchActive
                              ? CoreAssets.textInputBackground.swiftUIColor
                              : CoreAssets.textInputUnfocusedBackground.swiftUIColor)
                )
                .overlay(
                    Theme.Shapes.textInputShape
                        .stroke(lineWidth: 1)
                        .fill(viewModel.isSearchActive
                              ? CoreAssets.accentColor.swiftUIColor
                              : CoreAssets.textInputUnfocusedStroke.swiftUIColor)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                ZStack {
                    ScrollView {
                        HStack {
                            searchHeader(viewModel: viewModel)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 20)
                                .offset(y: animated ? 0 : 50)
                                .opacity(animated ? 1 : 0)
                            Spacer()
                        }.padding(.leading, 10)
                        
                        LazyVStack {
                            let searchResults = viewModel.searchResults.enumerated()
                            ForEach(
                                Array(searchResults), id: \.offset) { index, course in
                                    CourseCellView(model: course,
                                                   type: .discovery,
                                                   index: index,
                                                   cellsCount: viewModel.searchResults.count)
                                    .padding(.horizontal, 24)
                                    .onAppear {
                                        Task {
                                            await viewModel.searchCourses(
                                                index: index,
                                                searchTerm: viewModel.searchText
                                            )
                                        }
                                    }
                                    .onTapGesture {
                                        viewModel.router.showCourseDetais(
                                            courseID: course.courseID,
                                            title: course.name
                                        )
                                    }
                                }
                            // MARK: - ProgressBar
                            if viewModel.fetchInProgress {
                                VStack(alignment: .center) {
                                    ProgressBar(size: 40, lineWidth: 8)
                                        .padding(.top, 20)
                                }.frame(maxWidth: .infinity,
                                        maxHeight: .infinity)
                            }
                        }
                        Spacer(minLength: 40)
                    }.frameLimit()
                }
            }
            // MARK: - Error Alert
            if viewModel.showError {
                VStack {
                    Spacer()
                    SnackBarView(message: viewModel.errorMessage)
                }
                .transition(.move(edge: .bottom))
                .onAppear {
                    doAfter(Theme.Timeout.snackbarMessageLongTimeout) {
                        viewModel.errorMessage = nil
                    }
                }
            }
        }.hideNavigationBar()
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        animated = true
                    }
                }
            }
            .background(CoreAssets.background.swiftUIColor.ignoresSafeArea())
            .addTapToEndEditing(isForced: true)
    }
    
    private func searchHeader(viewModel: SearchViewModel<RunLoop>) -> some View {
        return VStack(alignment: .leading) {
            Text(DiscoveryLocalization.Search.title)
                .font(Theme.Fonts.displaySmall)
                .foregroundColor(CoreAssets.textPrimary.swiftUIColor)
            Text(searchDescription(viewModel: viewModel))
                .font(Theme.Fonts.titleSmall)
                .foregroundColor(CoreAssets.textPrimary.swiftUIColor)
        }.listRowBackground(Color.clear)
    }
    
    private func searchDescription(viewModel: SearchViewModel<RunLoop>) -> String {
        let searchEmptyDescription = DiscoveryLocalization.Search.emptyDescription
        let searchDescription =  DiscoveryLocalization.searchResultsDescription(
            viewModel.searchResults.isEmpty
            ? 0
            : viewModel.searchResults[0].coursesCount
        )
        let searchFieldEmpty = viewModel.searchText
            .trimmingCharacters(in: .whitespaces)
            .isEmpty
        if searchFieldEmpty {
            return searchEmptyDescription
        } else {
            return searchDescription
        }
    }
}

#if DEBUG
struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        let router = DiscoveryRouterMock()
        let vm = SearchViewModel(
            interactor: DiscoveryInteractor.mock,
            connectivity: Connectivity(),
            router: router,
            analyticsManager: DiscoveryAnalyticsMock(),
            debounce: .searchDebounce
        )
        
        SearchView(viewModel: vm)
            .preferredColorScheme(.light)
            .previewDisplayName("SearchView Light")
        
        SearchView(viewModel: vm)
            .preferredColorScheme(.dark)
            .previewDisplayName("SearchView Dark")
    }
}
#endif
