//
//  StatusAuthorView.swift
//  
//
//  Created by Jed Fox on 2022-10-31.
//

import UIKit
import Combine
import Meta
import MetaTextKit
import MastodonAsset
import MastodonCore
import MastodonLocalization

public class StatusAuthorView: UIStackView {
    private var _disposeBag = Set<AnyCancellable>() // which lifetime same to view scope

    weak var statusView: StatusView?

    // accessibility actions
    var authorActions = [UIAccessibilityCustomAction]()

    // avatar
    public let avatarButton = AvatarButton()

    // author name
    public let authorNameLabel = MetaLabel(style: .statusName)

    // author username
    public let authorUsernameLabel = MetaLabel(style: .statusUsername)

    public let usernameTrialingDotLabel: MetaLabel = {
        let label = MetaLabel(style: .statusUsername)
        label.configure(content: PlaintextMetaContent(string: "·"))
        return label
    }()

    // timestamp
    public let dateLabel = MetaLabel(style: .statusUsername)

    public let dateTrailingDotLabel: MetaLabel = {
        let label = MetaLabel(style: .statusUsername)
        label.configure(content: PlaintextMetaContent(string: "·"))
        return label
    }()

    let visibilityIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.tintColor = Asset.Colors.Label.secondary.color
        imageView.contentMode = .scaleAspectFit
        imageView.image = Asset.Scene.Compose.earth.image.withRenderingMode(.alwaysTemplate)
        return imageView
    }()

    public let menuButton: UIButton = {
        let button = HitTestExpandedButton(type: .system)
        button.expandEdgeInsets = UIEdgeInsets(top: -20, left: -10, bottom: -10, right: -10)
        button.tintColor = Asset.Colors.Label.secondary.color
        let image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(font: .systemFont(ofSize: 15)))
        button.setImage(image, for: .normal)
        button.accessibilityLabel = L10n.Common.Controls.Status.Actions.menu
        return button
    }()

    public let contentSensitiveeToggleButton: UIButton = {
        let button = HitTestExpandedButton(type: .system)
        button.expandEdgeInsets = UIEdgeInsets(top: -20, left: -10, bottom: -10, right: -10)
        button.tintColor = Asset.Colors.Label.secondary.color
        button.imageView?.contentMode = .scaleAspectFit
        let image = UIImage(systemName: "eye.slash.fill")
        button.setImage(image, for: .normal)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        _init()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        _init()
    }

    func layout(style: StatusView.Style) {
        switch style {
        case .inline:               layoutBase()
        case .plain:                layoutBase()
        case .report:               layoutReport()
        case .notification:         layoutBase()
        case .notificationQuote:    layoutNotificationQuote()
        case .composeStatusReplica: layoutComposeStatusReplica()
        case .composeStatusAuthor:  layoutComposeStatusAuthor()
        case .editHistory:          layoutBase()
        }
    }

    public override var accessibilityElements: [Any]? {
        get { [] }
        set {}
    }

    public override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            var actions = authorActions
            if !contentSensitiveeToggleButton.isHidden {
                actions.append(UIAccessibilityCustomAction(
                    name: contentSensitiveeToggleButton.accessibilityLabel!,
                    image: contentSensitiveeToggleButton.image(for: .normal),
                    actionHandler: { _ in
                        self.contentSensitiveeToggleButtonDidPressed(self.contentSensitiveeToggleButton)
                        return true
                    }
                ))
            }
            return actions
        }
        set {}
    }

    public override func accessibilityActivate() -> Bool {
        guard let statusView = statusView else { return false }
        statusView.delegate?.statusView(statusView, authorAvatarButtonDidPressed: avatarButton)
        return true
    }
}

extension StatusAuthorView {
    func _init() {
        axis = .horizontal
        spacing = 12
        isAccessibilityElement = true

        UIContentSizeCategory.publisher
            .sink { [unowned self] category in
                axis = category > .accessibilityLarge ? .vertical : .horizontal
                alignment = category > .accessibilityLarge ? .leading : .center
            }
            .store(in: &_disposeBag)

        // avatar button
        avatarButton.addTarget(self, action: #selector(StatusAuthorView.authorAvatarButtonDidPressed(_:)), for: .touchUpInside)
        authorNameLabel.isUserInteractionEnabled = false
        authorUsernameLabel.isUserInteractionEnabled = false

        // contentSensitiveeToggleButton
        contentSensitiveeToggleButton.addTarget(self, action: #selector(StatusAuthorView.contentSensitiveeToggleButtonDidPressed(_:)), for: .touchUpInside)

        // dateLabel
        dateLabel.isUserInteractionEnabled = false

        visibilityIconImageView.isUserInteractionEnabled = false
    }
}

extension StatusAuthorView {

    public struct AuthorMenuContext {
        public let name: String

        public let isMuting: Bool
        public let isBlocking: Bool
        public let isMyself: Bool
        public let isBookmarking: Bool
        public let isFollowed: Bool
        
        public let isTranslationEnabled: Bool
        public let isTranslated: Bool
        public let statusLanguage: String?
    }

    public func setupAuthorMenu(menuContext: AuthorMenuContext) -> (UIMenu, [UIAccessibilityCustomAction]) {
        var actions: [[MastodonMenu.Action]] = []
        var postActions: [MastodonMenu.Action] = []
        var userActions: [MastodonMenu.Action] = []

        if menuContext.isMyself {
            postActions.append(.editStatus)
        }

        if let statusLanguage = menuContext.statusLanguage, menuContext.isTranslationEnabled {
            if menuContext.isTranslated == false {
                postActions.append(.translateStatus(.init(language: statusLanguage)))
            } else {
                postActions.append(.showOriginal)
            }
        }

        postActions.append(.bookmarkStatus(.init(isBookmarking: menuContext.isBookmarking)))
        postActions.append(.shareStatus)

        if menuContext.isMyself == false {

            userActions.append(.followUser(.init(
                name: menuContext.name,
                isFollowing: menuContext.isFollowed
            )))

            userActions.append(.muteUser(.init(
                name: menuContext.name,
                isMuting: menuContext.isMuting
            )))

            userActions.append(.blockUser(.init(
                name: menuContext.name,
                isBlocking: menuContext.isBlocking
            )))

            userActions.append(.reportUser(
                .init(name: menuContext.name)
            ))
        }

        actions.append(postActions)
        actions.append(userActions)

        if menuContext.isMyself {
            actions.append([.deleteStatus])
        }

        let menu = MastodonMenu.setupMenu(
            actions: actions,
            delegate: self.statusView!
        )

        let accessibilityActions = MastodonMenu.setupAccessibilityActions(
            actions: actions,
            delegate: self.statusView!
        )

        return (menu, accessibilityActions)
    }

}

extension StatusAuthorView {
    @objc private func authorAvatarButtonDidPressed(_ sender: UIButton) {
        guard let statusView = statusView else { return }

        statusView.delegate?.statusView(statusView, authorAvatarButtonDidPressed: avatarButton)
    }

    @objc private func contentSensitiveeToggleButtonDidPressed(_ sender: UIButton) {
        guard let statusView = statusView else { return }

        statusView.delegate?.statusView(statusView, contentSensitiveeToggleButtonDidPressed: sender)
    }
}

extension StatusAuthorView {
    // author container: H - [ avatarButton | authorMetaContainer ]
    private func layoutBase() {
        // avatarButton
        avatarButton.size = CGSize.authorAvatarButtonSize
        avatarButton.avatarImageView.imageViewSize = CGSize.authorAvatarButtonSize
        avatarButton.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(avatarButton)
        NSLayoutConstraint.activate([
            avatarButton.widthAnchor.constraint(equalToConstant: CGSize.authorAvatarButtonSize.width).priority(.required - 1),
            avatarButton.heightAnchor.constraint(equalToConstant: CGSize.authorAvatarButtonSize.height).priority(.required - 1),
        ])
        avatarButton.setContentHuggingPriority(.required - 1, for: .vertical)
        avatarButton.setContentCompressionResistancePriority(.required - 1, for: .vertical)

        // authorMetaContainer: V - [ authorPrimaryMetaContainer | authorSecondaryMetaContainer ]
        let authorMetaContainer = UIStackView()
        authorMetaContainer.axis = .vertical
        authorMetaContainer.spacing = 4
        addArrangedSubview(authorMetaContainer)

        // authorPrimaryMetaContainer: H - [ authorNameLabel | (padding) | menuButton ]
        let authorPrimaryMetaContainer = UIStackView()
        authorPrimaryMetaContainer.axis = .horizontal
        authorPrimaryMetaContainer.alignment = .center
        authorPrimaryMetaContainer.spacing = 8
        authorMetaContainer.addArrangedSubview(authorPrimaryMetaContainer)

        // authorNameLabel
        authorPrimaryMetaContainer.addArrangedSubview(authorNameLabel)
        authorNameLabel.setContentHuggingPriority(.required - 1, for: .vertical)
        authorNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        authorPrimaryMetaContainer.addArrangedSubview(UIView())

        authorPrimaryMetaContainer.addArrangedSubview(contentSensitiveeToggleButton)
        NSLayoutConstraint.activate([
            contentSensitiveeToggleButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        authorPrimaryMetaContainer.setCustomSpacing(16, after: contentSensitiveeToggleButton)

        // menuButton
        authorPrimaryMetaContainer.addArrangedSubview(menuButton)
        menuButton.setContentHuggingPriority(.required - 1, for: .horizontal)
        menuButton.setContentCompressionResistancePriority(.required - 1, for: .horizontal)

        // authorSecondaryMetaContainer: H - [ authorUsername | usernameTrialingDotLabel | dateLabel | (padding) | contentSensitiveeToggleButton ]
        let authorSecondaryMetaContainer = UIStackView()
        authorSecondaryMetaContainer.axis = .horizontal
        authorSecondaryMetaContainer.alignment = .center
        authorSecondaryMetaContainer.spacing = 4
        authorMetaContainer.addArrangedSubview(authorSecondaryMetaContainer)

        authorSecondaryMetaContainer.addArrangedSubview(authorUsernameLabel)
        authorUsernameLabel.setContentHuggingPriority(.required - 1, for: .vertical)
        authorUsernameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        authorSecondaryMetaContainer.addArrangedSubview(usernameTrialingDotLabel)
        usernameTrialingDotLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        authorSecondaryMetaContainer.addArrangedSubview(dateLabel)
        dateLabel.setContentHuggingPriority(.required - 1, for: .horizontal)
        dateLabel.setContentCompressionResistancePriority(.required - 1, for: .horizontal)

        authorSecondaryMetaContainer.addArrangedSubview(dateTrailingDotLabel)
        dateTrailingDotLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        authorSecondaryMetaContainer.addArrangedSubview(visibilityIconImageView)
        NSLayoutConstraint.activate([
            visibilityIconImageView.heightAnchor.constraint(equalTo: authorUsernameLabel.heightAnchor),
            visibilityIconImageView.widthAnchor.constraint(equalTo: visibilityIconImageView.heightAnchor),
        ])

        authorSecondaryMetaContainer.setCustomSpacing(0, after: visibilityIconImageView)

        authorSecondaryMetaContainer.addArrangedSubview(UIView())
    }

    func layoutReport() {
        layoutBase()

        menuButton.removeFromSuperview()
    }

    func layoutNotificationQuote() {
        layoutBase()

        contentSensitiveeToggleButton.removeFromSuperview()
        menuButton.removeFromSuperview()
    }

    func layoutComposeStatusReplica() {
        layoutBase()

        avatarButton.isUserInteractionEnabled = false
        menuButton.removeFromSuperview()
    }

    func layoutComposeStatusAuthor() {
        layoutBase()

        avatarButton.isUserInteractionEnabled = false
        menuButton.removeFromSuperview()
        usernameTrialingDotLabel.removeFromSuperview()
        dateLabel.removeFromSuperview()
    }
}
