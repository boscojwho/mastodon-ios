//
//  HomeTimelineViewModel+LoadLatestState.swift
//  Mastodon
//
//  Created by sxiaojian on 2021/2/5.
//

import func QuartzCore.CACurrentMediaTime
import Foundation
import CoreData
import CoreDataStack
import GameplayKit
import MastodonCore

extension HomeTimelineViewModel {
    class LoadLatestState: GKState {
        
        let id = UUID()

        var name: String {
            String(describing: Self.self)
        }
        
        weak var viewModel: HomeTimelineViewModel?
        
        init(viewModel: HomeTimelineViewModel) {
            self.viewModel = viewModel
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            viewModel?.loadLatestStateMachinePublisher.send(self)
        }
        
        @MainActor
        func enter(state: LoadLatestState.Type) {
            stateMachine?.enter(state)
        }
    }
}

extension HomeTimelineViewModel.LoadLatestState {
    class Initial: HomeTimelineViewModel.LoadLatestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self || stateClass == LoadingManually.self
        }
    }
    
    class Loading: HomeTimelineViewModel.LoadLatestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Fail.self || stateClass == Idle.self
        }
        
        override func didEnter(from previousState: GKState?) {
            didEnter(from: previousState, viewModel: viewModel, isUserInitiated: false)
        }
    }
    
    class LoadingManually: HomeTimelineViewModel.LoadLatestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Fail.self || stateClass == Idle.self
        }
        
        override func didEnter(from previousState: GKState?) {
            didEnter(from: previousState, viewModel: viewModel, isUserInitiated: true)
        }
    }
    
    class Fail: HomeTimelineViewModel.LoadLatestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self || stateClass == Idle.self
        }
    }
    
    class Idle: HomeTimelineViewModel.LoadLatestState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self || stateClass == LoadingManually.self
        }
    }

    private func didEnter(from previousState: GKState?, viewModel: HomeTimelineViewModel?, isUserInitiated: Bool) {
        super.didEnter(from: previousState)

        guard let viewModel else { return }
        
        let latestFeedRecords = viewModel.fetchedResultsController.records.prefix(APIService.onceRequestStatusMaxCount)
        let parentManagedObjectContext = viewModel.fetchedResultsController.managedObjectContext
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.parent = parentManagedObjectContext

        Task {
            let latestStatusIDs: [Status.ID] = latestFeedRecords.compactMap { record in
                guard let feed = record.object(in: managedObjectContext) else { return nil }
                return feed.status?.id
            }

            do {
                let response = try await viewModel.context.apiService.homeTimeline(
                    authenticationBox: viewModel.authContext.mastodonAuthenticationBox
                )
                
                await enter(state: Idle.self)
                viewModel.homeTimelineNavigationBarTitleViewModel.receiveLoadingStateCompletion(.finished)

                viewModel.context.instanceService.updateMutesAndBlocks()
                
                // stop refresher if no new statuses
                let statuses = response.value
                let newStatuses = statuses.filter { !latestStatusIDs.contains($0.id) }

                if newStatuses.isEmpty {
                    viewModel.didLoadLatest.send()
                } else {
                    if !latestStatusIDs.isEmpty {
                        viewModel.homeTimelineNavigationBarTitleViewModel.newPostsIncoming()
                    }
                }
                viewModel.timelineIsEmpty.value = latestStatusIDs.isEmpty && statuses.isEmpty
                
                if !isUserInitiated {
                    await UIImpactFeedbackGenerator(style: .light)
                        .impactOccurred()
                }
                
            } catch {
                await enter(state: Idle.self)
                viewModel.didLoadLatest.send()
                viewModel.homeTimelineNavigationBarTitleViewModel.receiveLoadingStateCompletion(.failure(error))
            }
        }   // end Task
    }
}
