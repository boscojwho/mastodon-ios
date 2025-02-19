//
//  MastodonLoginViewController.swift
//  Mastodon
//
//  Created by Nathan Mattes on 09.11.22.
//

import UIKit
import MastodonSDK
import MastodonCore
import MastodonAsset
import Combine
import AuthenticationServices
import MastodonLocalization

protocol MastodonLoginViewControllerDelegate: AnyObject {
    func backButtonPressed(_ viewController: MastodonLoginViewController)
    func nextButtonPressed(_ viewController: MastodonLoginViewController)
}

enum MastodonLoginViewSection: Hashable {
    case servers
}

class MastodonLoginViewController: UIViewController, NeedsDependency {
    
    enum RightBarButtonState {
        case normal, disabled, loading
    }
    
    weak var delegate: MastodonLoginViewControllerDelegate?
    var dataSource: UITableViewDiffableDataSource<MastodonLoginViewSection, Mastodon.Entity.Server>?
    let viewModel: MastodonLoginViewModel
    let authenticationViewModel: AuthenticationViewModel
    var mastodonAuthenticationController: MastodonAuthenticationController?
    
    weak var context: AppContext!
    weak var coordinator: SceneCoordinator!
    
    var disposeBag = Set<AnyCancellable>()
    
    var contentView: MastodonLoginView {
        view as! MastodonLoginView
    }
    
    init(appContext: AppContext, authenticationViewModel: AuthenticationViewModel, sceneCoordinator: SceneCoordinator) {
        
        viewModel = MastodonLoginViewModel(appContext: appContext)
        self.authenticationViewModel = authenticationViewModel
        self.context = appContext
        self.coordinator = sceneCoordinator
        
        super.init(nibName: nil, bundle: nil)
        viewModel.delegate = self
    }
    
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    override func loadView() {
        let loginView = MastodonLoginView()
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.Common.Controls.Actions.next,
            style: .plain,
            target: self,
            action: #selector(nextButtonPressed(_:))
        )
        
        navigationItem.leftBarButtonItem?.target = self
        navigationItem.leftBarButtonItem?.action = #selector(backButtonPressed(_:))
        
        loginView.searchTextField.addTarget(self, action: #selector(MastodonLoginViewController.textfieldDidChange(_:)), for: .editingChanged)
        loginView.tableView.delegate = self
        loginView.tableView.register(MastodonLoginServerTableViewCell.self, forCellReuseIdentifier: MastodonLoginServerTableViewCell.reuseIdentifier)
        setRightBarButtonState(.disabled)
        
        view = loginView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShowNotification(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHideNotification(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
        let dataSource = UITableViewDiffableDataSource<MastodonLoginViewSection, Mastodon.Entity.Server>(tableView: contentView.tableView) { [weak self] tableView, indexPath, itemIdentifier in
            guard let cell = tableView.dequeueReusableCell(withIdentifier: MastodonLoginServerTableViewCell.reuseIdentifier, for: indexPath) as? MastodonLoginServerTableViewCell,
                  let self = self else {
                fatalError("Wrong cell")
            }
            
            let server = self.viewModel.filteredServers[indexPath.row]
            var configuration = cell.defaultContentConfiguration()
            configuration.text = server.domain
            
            cell.contentConfiguration = configuration
            cell.accessoryType = .disclosureIndicator
            
            cell.backgroundColor = Asset.Scene.Onboarding.textFieldBackground.color
            
            return cell
        }
        
        contentView.tableView.dataSource = dataSource
        self.dataSource = dataSource
        
        contentView.updateCorners()
        
        defer { setupNavigationBarBackgroundView() }
        setupOnboardingAppearance()
        
        title = L10n.Scene.Login.title
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        viewModel.updateServers()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        contentView.searchTextField.becomeFirstResponder()
    }
    
    //MARK: - Actions
    
    @objc func backButtonPressed(_ sender: Any) {
        contentView.searchTextField.resignFirstResponder()
        delegate?.backButtonPressed(self)
    }
    
    @objc func nextButtonPressed(_ sender: Any) {
        contentView.searchTextField.resignFirstResponder()
        delegate?.nextButtonPressed(self)
        setRightBarButtonState(.loading)
    }
    
    @objc func login() {
        guard let server = viewModel.selectedServer else { return }
        
        authenticationViewModel
            .authenticated
            .asyncMap { domain, user -> Result<Bool, Error> in
                do {
                    let result = try await self.context.authenticationService.activeMastodonUser(domain: domain, userID: user.id)
                    return .success(result)
                } catch {
                    return .failure(error)
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                case .success(let isActived):
                    assert(isActived)
                    self.coordinator.setup()
                }
            }
            .store(in: &disposeBag)
        
        authenticationViewModel.isAuthenticating.send(true)
        context.apiService.createApplication(domain: server.domain)
            .tryMap { response -> AuthenticationViewModel.AuthenticateInfo in
                let application = response.value
                guard let info = AuthenticationViewModel.AuthenticateInfo(
                    domain: server.domain,
                    application: application,
                    redirectURI: response.value.redirectURI ?? APIService.oauthCallbackURL
                ) else {
                    throw APIService.APIError.explicit(.badResponse)
                }
                return info
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                self.authenticationViewModel.isAuthenticating.send(false)
                
                switch completion {
                case .failure(let error):
                    let alert = UIAlertController.standardAlert(of: error)
                    self.present(alert, animated: true)
                    self.setRightBarButtonState(.normal)
                case .finished:
                    self.setRightBarButtonState(.normal)
                    break
                }
            } receiveValue: { [weak self] info in
                guard let self else { return }
                let authenticationController = MastodonAuthenticationController(
                    context: self.context,
                    authenticateURL: info.authorizeURL
                )
                
                self.mastodonAuthenticationController = authenticationController
                authenticationController.authenticationSession?.presentationContextProvider = self
                authenticationController.authenticationSession?.start()
                
                self.authenticationViewModel.authenticate(
                    info: info,
                    pinCodePublisher: authenticationController.pinCodePublisher
                )
            }
            .store(in: &disposeBag)
    }
    
    @objc func textfieldDidChange(_ textField: UITextField) {
        viewModel.filterServers(withText: textField.text)
        
        
        if let text = textField.text,
           let domain = AuthenticationViewModel.parseDomain(from: text) {
            
            viewModel.selectedServer = .init(domain: domain, instance: .init(domain: domain))
            setRightBarButtonState(.normal)
        } else {
            viewModel.selectedServer = nil
            setRightBarButtonState(.disabled)
        }
    }
    
    // MARK: - Notifications
    @objc func keyboardWillShowNotification(_ notification: Notification) {
        
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber
        else { return }
        
        // inspired by https://stackoverflow.com/a/30245044
        UIView.animate(withDuration: duration.doubleValue, delay: 0, options: .curveEaseInOut) {
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func keyboardWillHideNotification(_ notification: Notification) {
        
        guard let userInfo = notification.userInfo,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber
        else { return }
        
        UIView.animate(withDuration: duration.doubleValue, delay: 0, options: .curveEaseInOut) {
            self.view.layoutIfNeeded()
        }
    }
    
    private func setRightBarButtonState(_ state: RightBarButtonState) {
        switch state {
        case .normal:
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: L10n.Common.Controls.Actions.next,
                style: .plain,
                target: self,
                action: #selector(nextButtonPressed(_:))
            )
        case .disabled:
            navigationItem.rightBarButtonItem?.isEnabled = false
        case .loading:
            let activityIndicator = UIActivityIndicatorView(style: .medium)
            activityIndicator.startAnimating()
            let barButtonItem = UIBarButtonItem(customView: activityIndicator)
            navigationItem.rightBarButtonItem = barButtonItem
        }
    }
}

// MARK: - OnboardingViewControllerAppearance
extension MastodonLoginViewController: OnboardingViewControllerAppearance { }

// MARK: - UITableViewDelegate
extension MastodonLoginViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let server = viewModel.filteredServers[indexPath.row]
        viewModel.selectedServer = server
        
        contentView.searchTextField.text = server.domain
        viewModel.filterServers(withText: " ")
        
        setRightBarButtonState(.normal)
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - MastodonLoginViewModelDelegate
extension MastodonLoginViewController: MastodonLoginViewModelDelegate {
    func serversUpdated(_ viewModel: MastodonLoginViewModel) {
        var snapshot = NSDiffableDataSourceSnapshot<MastodonLoginViewSection, Mastodon.Entity.Server>()
        
        snapshot.appendSections([MastodonLoginViewSection.servers])
        snapshot.appendItems(viewModel.filteredServers)
        
        dataSource?.apply(snapshot, animatingDifferences: false)
        
        DispatchQueue.main.async {
            let numberOfResults = viewModel.filteredServers.count
            self.contentView.updateCorners(numberOfResults: numberOfResults)
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension MastodonLoginViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return view.window!
    }
}
