//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import SignalMessaging

public protocol ConversationAvatarViewDelegate: AnyObject {
    func didTapAvatar()
    func didTapBadge()
}
public extension ConversationAvatarViewDelegate {
    func didTapAvatar() {}
    func didTapBadge() {}
}

public class ConversationAvatarView: UIView, CVView, PrimaryImageView {

    public required init(
        sizeClass: Configuration.SizeClass = .customDiameter(0),
        localUserDisplayMode: LocalUserDisplayMode,
        badged: Bool = true,
        shape: Configuration.Shape = .circular,
        useAutolayout: Bool = true
    ) {
        self.configuration = Configuration(
            sizeClass: sizeClass,
            dataSource: nil,
            localUserDisplayMode: localUserDisplayMode,
            addBadgeIfApplicable: badged,
            shape: shape,
            useAutolayout: useAutolayout)

        super.init(frame: .zero)

        addSubview(avatarView)
        addSubview(badgeView)
        autoresizesSubviews = false
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Configuration API

    public struct Configuration: Equatable {
        public enum SizeClass: Equatable {
            case twentyFour
            case twentyEight
            case thirtySix
            case forty
            case fortyEight
            case fiftySix
            case sixtyFour
            case eighty
            case eightyEight
            case oneHundredTwelve

            // Badge sprites may have artifacts from scaling to custom size classes
            // Stick to explicit size classes when you can
            case customDiameter(UInt)

            public init(avatarDiameter: UInt) {
                switch avatarDiameter {
                case Self.twentyFour.avatarDiameter:
                    self = .twentyFour
                case Self.twentyEight.avatarDiameter:
                    self = .twentyEight
                case Self.thirtySix.avatarDiameter:
                    self = .thirtySix
                case Self.forty.avatarDiameter:
                    self = .forty
                case Self.fortyEight.avatarDiameter:
                    self = .fortyEight
                case Self.fiftySix.avatarDiameter:
                    self = .fiftySix
                case Self.sixtyFour.avatarDiameter:
                    self = .sixtyFour
                case Self.eighty.avatarDiameter:
                    self = .eighty
                case Self.eightyEight.avatarDiameter:
                    self = .eightyEight
                case Self.oneHundredTwelve.avatarDiameter:
                    self = .oneHundredTwelve
                default:
                    self = .customDiameter(avatarDiameter)
                }
            }
        }

        public enum Shape {
            case rectangular
            case circular
        }

        /// The preferred size class of the avatar. Used for avatar generation and autolayout (if enabled)
        /// If a predefined size class is used, a badge can optionally be placed by specifying `addBadgeIfApplicable`
        public var sizeClass: SizeClass
        /// The data provider used to fetch an avatar and badge
        public var dataSource: ConversationAvatarDataSource?
        /// Adjusts how the local user profile avatar is generated (Note to Self or Avatar?)
        public var localUserDisplayMode: LocalUserDisplayMode
        /// Places the user's badge (if they have one) over the avatar. Only supported for predefined size classes
        public var addBadgeIfApplicable: Bool

        /// Adjusts the mask of the avatar view
        public var shape: Shape
        /// If set `true`, adds constraints to the view to ensure that it's sized for the provided size class
        /// Otherwise, it's the superview's responsibility to ensure this view is sized appropriately
        public var useAutolayout: Bool

        // Adopters that'd like to fetch the image synchronously can set this to perform
        // the next model update synchronously if necessary.
        fileprivate var forceSyncUpdate: Bool = false
        public mutating func applyConfigurationSynchronously() {
            forceSyncUpdate = true
        }
        fileprivate mutating func checkForSyncUpdateAndClear() -> Bool {
            let shouldUpdateSync = forceSyncUpdate || (dataSource?.isDataImmediatelyAvailable != true)
            forceSyncUpdate = false
            return shouldUpdateSync
        }
    }

    public private(set) var configuration: Configuration {
        didSet {
            if configuration.dataSource != oldValue.dataSource {
                if Thread.isMainThread {
                    ensureObservers()
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.ensureObservers()
                    }
                }
            }
        }
    }

    func updateConfigurationAndSetDirtyIfNecessary(_ newValue: Configuration) {
        let oldValue = configuration
        configuration = newValue

        // We may need to update our model, layout, or constraints based on the changes to the configuration
        let sizeClassDidChange = configuration.sizeClass != oldValue.sizeClass
        let dataSourceDidChange = configuration.dataSource != oldValue.dataSource
        let localUserDisplayModeDidChange = configuration.localUserDisplayMode != oldValue.localUserDisplayMode
        let shouldShowBadgeDidChange = configuration.addBadgeIfApplicable != oldValue.addBadgeIfApplicable
        let shapeDidChange = configuration.shape != oldValue.shape
        let autolayoutDidChange = configuration.useAutolayout != oldValue.useAutolayout

        // Any changes to avatar size or provider will trigger a model update
        if sizeClassDidChange || dataSourceDidChange || localUserDisplayModeDidChange || shouldShowBadgeDidChange {
            setNeedsModelUpdate()
        }

        // If autolayout was toggled, or the size changed while autolayout is enabled we need to update our constraints
        if autolayoutDidChange || (configuration.useAutolayout && sizeClassDidChange) {
            if Thread.isMainThread {
                setNeedsUpdateConstraints()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.setNeedsUpdateConstraints()
                }
            }
        }

        if sizeClassDidChange || shouldShowBadgeDidChange || shapeDidChange {
            if Thread.isMainThread {
                setNeedsLayout()
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.setNeedsLayout()
                }
            }
        }
    }

    // MARK: Configuration updates

    public func updateWithSneakyTransactionIfNecessary(_ updateBlock: (inout Configuration) -> Void) {
        update(optionalTransaction: nil, updateBlock)
    }

    /// To reduce the occurrence of unnecessary avatar fetches, updates to the view configuration occur in a closure
    /// Configuration updates will be applied all at once
    public func update(_ transaction: SDSAnyReadTransaction, _ updateBlock: (inout Configuration) -> Void) {
        AssertIsOnMainThread()
        update(optionalTransaction: transaction, updateBlock)
    }

    private func update(optionalTransaction transaction: SDSAnyReadTransaction?, _ updateBlock: (inout Configuration) -> Void) {
        let oldConfiguration = configuration
        var mutableConfig = oldConfiguration
        updateBlock(&mutableConfig)
        updateConfigurationAndSetDirtyIfNecessary(mutableConfig)
        updateModelIfNecessary(transaction: transaction)
    }

    // MARK: Model Updates

    public func reloadDataIfNecessary() {
        updateModel(transaction: nil)
    }
    private func updateModel(transaction readTx: SDSAnyReadTransaction?) {
        setNeedsModelUpdate()
        updateModelIfNecessary(transaction: readTx)
    }

    // If the model has been dirtied, performs an update
    // If an async update is requested, the model is updated immediately with any available chached content
    // followed by enqueueing a full model update on a background thread.
    private func updateModelIfNecessary(transaction readTx: SDSAnyReadTransaction?) {
        guard nextModelGeneration.get() > currentModelGeneration else { return }
        Logger.debug("Updating model using dataSource: \(configuration.dataSource?.description ?? "nil")")
        guard let dataSource = configuration.dataSource else {
            updateViewContent(avatarImage: nil, badgeImage: nil)
            return
        }

        let updateSynchronously = configuration.checkForSyncUpdateAndClear()
        if updateSynchronously {
            let avatarImage = dataSource.buildImage(configuration: configuration, transaction: readTx)
            let badgeImage = dataSource.fetchBadge(configuration: configuration, transaction: readTx)
            updateViewContent(avatarImage: avatarImage, badgeImage: badgeImage)
        } else {
            let avatarImage = dataSource.fetchCachedImage(configuration: configuration, transaction: readTx)
            let badgeImage = dataSource.fetchBadge(configuration: configuration, transaction: readTx)
            updateViewContent(avatarImage: avatarImage, badgeImage: badgeImage)
            enqueueAsyncModelUpdate()
        }
    }

    private func updateViewContent(avatarImage: UIImage?, badgeImage: UIImage?) {
        let uiUpdateBlock = { [weak self] in
            if let self = self {
                self.avatarView.image = avatarImage ?? UIImage(named: Theme.isDarkThemeEnabled ? "profile-placeholder-dark-56" : "profile-placeholder-56")
                self.badgeView.image = badgeImage
                self.currentModelGeneration = self.nextModelGeneration.get()
                self.setNeedsLayout()
            }
        }
        if Thread.isMainThread {
            uiUpdateBlock()
        } else {
            DispatchQueue.main.async {
                uiUpdateBlock()
            }
        }
    }

    // MARK: - Model Tracking

    // Invoking `setNeedsModelUpdate()` increments the next model generation
    // Any updates to the model copy the `nextModelGeneration` to the currentModelGeneration
    // For synchronous updates, these happen in lockstep on the main thread
    // For async model updates, this helps with detecting parallel model changes on another thread
    // `nextModelGeneration` can be read on a background thread, so it needs to be atomic.
    // All updates are performed on the main thread.
    private var currentModelGeneration: UInt = 0
    private var nextModelGeneration = AtomicUInt(0)
    @discardableResult
    private func setNeedsModelUpdate() -> UInt {
        var ret: UInt?
        if Thread.isMainThread {
            ret = nextModelGeneration.increment()
        } else {
            DispatchQueue.main.sync {
                ret = nextModelGeneration.increment()
            }
        }
        return ret!
    }

    // Load avatars in _reverse_ order in which they are enqueued.
    // Avatars are enqueued as the user navigates (and not cancelled),
    // so the most recently enqueued avatars are most likely to be
    // visible. To put it another way, we don't cancel loads so
    // the oldest loads are most likely to be unnecessary.
    private static let serialQueue = ReverseDispatchQueue(label: "org.signal.ConversationAvatarView")

    private func enqueueAsyncModelUpdate() {
        AssertIsOnMainThread()
        let generationAtEnqueue = setNeedsModelUpdate()
        let configurationAtEnqueue = configuration

        Self.serialQueue.async { [weak self] in
            guard let self = self, self.nextModelGeneration.get() == generationAtEnqueue else {
                Logger.info("Model generation updated while performing async model update. Dropping results.")
                return
            }

            let (updatedAvatar, updatedBadge) = Self.databaseStorage.read { transaction -> (UIImage?, UIImage?) in
                let avatarImage = configurationAtEnqueue.dataSource?.buildImage(configuration: configurationAtEnqueue, transaction: transaction)
                let badgeImage = configurationAtEnqueue.dataSource?.fetchBadge(configuration: configurationAtEnqueue, transaction: transaction)
                return (avatarImage, badgeImage)
            }

            DispatchQueue.main.async {
                guard self.nextModelGeneration.get() == generationAtEnqueue else {
                    Logger.info("Model generation updated while performing async model update. Dropping results.")
                    return
                }
                self.updateViewContent(avatarImage: updatedAvatar, badgeImage: updatedBadge)
            }
        }
    }

    // MARK: Subviews and Layout

    private var avatarView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        return view
    }()

    private var badgeView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.layer.minificationFilter = .trilinear
        view.layer.magnificationFilter = .trilinear
        return view
    }()

    private var sizeConstraints: (width: NSLayoutConstraint, height: NSLayoutConstraint)?
    override public func updateConstraints() {
        let targetSize = configuration.sizeClass.avatarSize

        switch (configuration.useAutolayout, sizeConstraints) {
        case (true, let constraints?):
            constraints.width.constant = targetSize.width
            constraints.height.constant = targetSize.height
        case (true, nil):
            sizeConstraints = (width: autoSetDimension(.width, toSize: targetSize.width),
                               height: autoSetDimension(.height, toSize: targetSize.height))
        case (false, _):
            if let sizeConstraints = sizeConstraints {
                NSLayoutConstraint.deactivate([sizeConstraints.width, sizeConstraints.height])
            }
            sizeConstraints = nil
        }

        super.updateConstraints()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        avatarView.frame = CGRect(origin: .zero, size: configuration.sizeClass.avatarSize)
        badgeView.frame = CGRect(origin: configuration.sizeClass.badgeOffset, size: configuration.sizeClass.badgeSize)
        badgeView.isHidden = (badgeView.image == nil)

        switch configuration.shape {
        case .circular:
            avatarView.layer.cornerRadius = (avatarView.bounds.height / 2)
            avatarView.layer.masksToBounds = true
        case .rectangular:
            avatarView.layer.cornerRadius = 0
            avatarView.layer.masksToBounds = false
        }
    }

    @objc
    public override var intrinsicContentSize: CGSize { configuration.sizeClass.avatarSize }

    @objc
    public override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }

    // MARK: - Controls

    lazy private var avatarTapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer()
        tapGestureRecognizer.addTarget(self, action: #selector(didTapAvatar(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        return tapGestureRecognizer
    }()

    lazy private var badgeTapGestureRecognizer: UITapGestureRecognizer = {
        let tapGestureRecognizer = UITapGestureRecognizer()
        tapGestureRecognizer.addTarget(self, action: #selector(didTapBadge(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        return tapGestureRecognizer
    }()

    public weak var interactionDelegate: ConversationAvatarViewDelegate? {
        didSet {
            if interactionDelegate != nil, oldValue == nil {
                avatarView.addGestureRecognizer(avatarTapGestureRecognizer)
                badgeView.addGestureRecognizer(badgeTapGestureRecognizer)
                avatarView.isUserInteractionEnabled = true
                badgeView.isUserInteractionEnabled = true
                isUserInteractionEnabled = true
            } else if interactionDelegate == nil, oldValue != nil {
                avatarView.removeGestureRecognizer(avatarTapGestureRecognizer)
                badgeView.removeGestureRecognizer(badgeTapGestureRecognizer)
                avatarView.isUserInteractionEnabled = false
                badgeView.isUserInteractionEnabled = false
                isUserInteractionEnabled = false
            }
        }
    }

    @objc private func didTapAvatar(_ sender: UITapGestureRecognizer) {
        guard avatarView.image != nil else { return }
        interactionDelegate?.didTapAvatar()
    }

    @objc private func didTapBadge(_ sender: UITapGestureRecognizer) {
        guard badgeView.image != nil else { return }
        interactionDelegate?.didTapBadge()
    }

    // MARK: Notifications

    private func ensureObservers() {
        // TODO: Badges — Notify on an updated badge asset?

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: .ThemeDidChange,
                                               object: nil)

        guard let dataSource = configuration.dataSource else { return }

        if dataSource.isContactAvatar {
            if dataSource.contactAddress?.isLocalAddress == true {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(localUsersProfileDidChange(notification:)),
                                                       name: .localProfileDidChange,
                                                       object: nil)
            } else {
                NotificationCenter.default.addObserver(self,
                                                       selector: #selector(otherUsersProfileDidChange(notification:)),
                                                       name: .otherUsersProfileDidChange,
                                                       object: nil)
            }

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleSignalAccountsChanged(notification:)),
                                                   name: .OWSContactsManagerSignalAccountsDidChange,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(skipContactAvatarBlurDidChange(notification:)),
                                                   name: OWSContactsManager.skipContactAvatarBlurDidChange,
                                                   object: nil)
        } else if dataSource.isGroupAvatar {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleGroupAvatarChanged(notification:)),
                                                   name: .TSGroupThreadAvatarChanged,
                                                   object: nil)
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(skipGroupAvatarBlurDidChange(notification:)),
                                                   name: OWSContactsManager.skipGroupAvatarBlurDidChange,
                                                   object: nil)
        }
    }

    @objc
    private func themeDidChange() {
        AssertIsOnMainThread()
        updateModel(transaction: nil)
    }

    @objc
    private func handleSignalAccountsChanged(notification: Notification) {
        AssertIsOnMainThread()

        // PERF: It would be nice if we could do this only if *this* user's SignalAccount changed,
        // but currently this is only a course grained notification.
        updateModel(transaction: nil)
    }

    @objc
    private func localUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()
        if let sourceAddress = configuration.dataSource?.contactAddress, sourceAddress.isLocalAddress {
            handleUpdatedAddressNotification(address: sourceAddress)
        }
    }

    @objc
    private func otherUsersProfileDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let changedAddress = notification.userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress, changedAddress.isValid else {
            owsFailDebug("changedAddress was unexpectedly nil")
            return
        }
        handleUpdatedAddressNotification(address: changedAddress)
    }

    @objc
    private func skipContactAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let address = notification.userInfo?[OWSContactsManager.skipContactAvatarBlurAddressKey] as? SignalServiceAddress, address.isValid else {
            owsFailDebug("Missing address.")
            return
        }
        handleUpdatedAddressNotification(address: address)
    }

    private func handleUpdatedAddressNotification(address: SignalServiceAddress) {
        AssertIsOnMainThread()
        guard let dataSource = configuration.dataSource else { return }
        guard let providerAddress = dataSource.contactAddress else {
            // Should always be set for non-group thread avatar providers
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }

        if providerAddress == address {
            updateModel(transaction: nil)
        }
    }

    @objc
    private func handleGroupAvatarChanged(notification: Notification) {
        AssertIsOnMainThread()
        guard let changedGroupThreadId = notification.userInfo?[TSGroupThread_NotificationKey_UniqueId] as? String else {
            owsFailDebug("groupThreadId was unexpectedly nil")
            return
        }
        handleUpdatedGroupThreadNotification(changedThreadId: changedGroupThreadId)
    }

    @objc
    private func skipGroupAvatarBlurDidChange(notification: Notification) {
        AssertIsOnMainThread()
        guard let groupThreadId = notification.userInfo?[OWSContactsManager.skipGroupAvatarBlurGroupUniqueIdKey] as? String else {
            owsFailDebug("Missing groupId.")
            return
        }
        handleUpdatedGroupThreadNotification(changedThreadId: groupThreadId)
    }

    private func handleUpdatedGroupThreadNotification(changedThreadId: String) {
        AssertIsOnMainThread()
        guard let dataSource = configuration.dataSource, dataSource.isGroupAvatar else { return }
        guard let contentThreadId = dataSource.threadId else {
            // Should always be set for non-group thread avatar providers
            owsFailDebug("contactAddress was unexpectedly nil")
            return
        }

        if contentThreadId == changedThreadId {
            databaseStorage.read {
                dataSource.reload(transaction: $0)
                updateModel(transaction: $0)
            }
        }
    }

    // MARK: - <CVView>

    public func reset() {
        configuration.dataSource = nil
        reloadDataIfNecessary()
    }

    // MARK: - <PrimaryImageView>

    public var primaryImage: UIImage? { avatarView.image }
}

// MARK: -

public enum ConversationAvatarDataSource: Equatable, Dependencies, CustomStringConvertible {
    case thread(TSThread)
    case address(SignalServiceAddress)
    case asset(avatar: UIImage?, badge: UIImage?)

    var isContactAvatar: Bool { contactAddress != nil }
    var isGroupAvatar: Bool {
        if case .thread(_ as TSGroupThread) = self {
            return true
        } else {
            return false
        }
    }

    var contactAddress: SignalServiceAddress? {
        switch self {
        case .address(let address): return address
        case .thread(let thread as TSContactThread): return thread.contactAddress
        case .thread: return nil
        case .asset: return nil
        }
    }

    fileprivate var threadId: String? {
        switch self {
        case .thread(let thread): return thread.uniqueId
        case .address, .asset: return nil
        }
    }

    fileprivate var isDataImmediatelyAvailable: Bool {
        switch self {
        case .thread, .address: return false
        case .asset: return true
        }
    }

    private func performWithTransaction<T>(_ existingTx: SDSAnyReadTransaction?, _ block: (SDSAnyReadTransaction) -> T) -> T {
        if let transaction = existingTx {
            return block(transaction)
        } else {
            return databaseStorage.read { readTx in
                block(readTx)
            }
        }
    }

    // TODO: Badges — Should this be async?
    fileprivate func fetchBadge(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction?) -> UIImage? {
        guard configuration.addBadgeIfApplicable else { return nil }
        guard RemoteConfig.donorBadgeDisplay else {
            Logger.warn("Ignoring badge request. Badge flag currently disabled")
            return nil
        }
        guard configuration.sizeClass.badgeDiameter >= 16 else {
            // We never want to show a badge <= 16pts
            Logger.warn("Skipping badge request for badge with diameter of \(configuration.sizeClass.badgeDiameter)")
            return nil
        }

        let targetAddress: SignalServiceAddress
        switch self {
        case .address(let address):
            targetAddress = address
        case .thread(let contactThread as TSContactThread):
            targetAddress = (contactThread).contactAddress
        case .thread:
            return nil
        case .asset(avatar: _, badge: let badge):
            return badge
        }

        if targetAddress.isLocalAddress, configuration.localUserDisplayMode == .noteToSelf {
            // We never want to show badges on Note To Self
            return nil
        }

        let primaryBadge: ProfileBadge? = performWithTransaction(transaction) {
            let userProfile: OWSUserProfile?
            if targetAddress.isLocalAddress {
                // TODO: Badges — Expose badge info about local user profile on OWSUserProfile
                userProfile = OWSProfileManager.shared.localUserProfile()
            } else {
                userProfile = AnyUserProfileFinder().userProfile(for: targetAddress, transaction: $0)
            }
            return userProfile?.primaryBadge?.fetchBadgeContent(transaction: $0)
        }
        guard let badgeAssets = primaryBadge?.assets else { return nil }
        return configuration.sizeClass.fetchImageFromBadgeAssets(badgeAssets)
    }

    fileprivate func buildImage(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction?) -> UIImage? {
        switch self {
        case .thread(let contactThread as TSContactThread):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.avatarImage(
                    forAddress: contactThread.contactAddress,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    localUserDisplayMode: configuration.localUserDisplayMode,
                    transaction: $0)
            }

        case .address(let address):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.avatarImage(
                    forAddress: address,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    localUserDisplayMode: configuration.localUserDisplayMode,
                    transaction: $0)
            }

        case .thread(let groupThread as TSGroupThread):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.avatarImage(
                    forGroupThread: groupThread,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    transaction: $0)
            }

        case .asset(let avatar, _):
            return avatar

        case .thread:
            owsFailDebug("Unrecognized thread subclass: \(self)")
            return nil
        }
    }

    fileprivate func fetchCachedImage(configuration: ConversationAvatarView.Configuration, transaction: SDSAnyReadTransaction?) -> UIImage? {
        switch self {
        case .thread(let contactThread as TSContactThread):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.precachedAvatarImage(
                    forAddress: contactThread.contactAddress,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    localUserDisplayMode: configuration.localUserDisplayMode,
                    transaction: $0)
            }

        case .address(let address):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.precachedAvatarImage(
                    forAddress: address,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    localUserDisplayMode: configuration.localUserDisplayMode,
                    transaction: $0)
            }

        case .thread(let groupThread as TSGroupThread):
            return performWithTransaction(transaction) {
                Self.avatarBuilder.precachedAvatarImage(
                    forGroupThread: groupThread,
                    diameterPoints: UInt(configuration.sizeClass.avatarDiameter),
                    transaction: $0)
            }

        case .asset(let avatar, _):
            return avatar

        case .thread:
            owsFailDebug("Unrecognized thread subclass: \(self)")
            return nil
        }
    }

    fileprivate func reload(transaction: SDSAnyReadTransaction) {
        switch self {
        case .thread(let thread):
            thread.anyReload(transaction: transaction)
        case .asset, .address:
            break
        }
    }

    public var description: String {
        switch self {
        case .address(let address): return "[Address: \(address)]"
        case .thread(let thread): return "[Thread \(type(of: thread)):\(thread.uniqueId)]"
        case .asset(let avatar, let badge): return "[AvatarImage: \(avatar), BadgeImage: \(badge)]"
        }
    }
}

extension ConversationAvatarView.Configuration.SizeClass {
    // Badge layout is hardcoded. There's no simple rule to precisely place a badge on
    // an arbitrarily sized avatar. Design has provided us with these pre-defined sizes.
    // An avatar outside of these sizes will not support badging

    public var avatarDiameter: UInt {
        switch self {
        case .twentyFour: return 24
        case .twentyEight: return 28
        case .thirtySix: return 36
        case .forty: return 40
        case .fortyEight: return 48
        case .fiftySix: return 56
        case .sixtyFour: return 64
        case .eighty: return 80
        case .eightyEight: return 88
        case .oneHundredTwelve: return 112
        case .customDiameter(let diameter): return diameter
        }
    }

    var badgeDiameter: CGFloat {
        // Originally, we were only using badge sprites for explicit size classes
        // But it turns out we need these badges displayed in more places than originally thought
        // Now we lerp between the explicit size classes that design has provided for us
        switch avatarDiameter {
        case ..<24: return 0
        case 24...36: return 16
        case 36..<40: return CGFloat(avatarDiameter).inverseLerp(36, 40).lerp(16, 24)
        case 40...64: return 24
        case 64..<80: return CGFloat(avatarDiameter).inverseLerp(64, 80).lerp(24, 36)
        case 80...112: return 36
        case 112...: return (CGFloat(avatarDiameter) / 112) * 36
        default: return 0
        }
    }

    /// The badge offset from its frame origin. Design has specified these points so the badge sits right alongside the circular avatar edge
    var badgeOffset: CGPoint {
        switch self {
        case .twentyFour: return CGPoint(x: 10, y: 12)
        case .twentyEight: return CGPoint(x: 14, y: 16)
        case .thirtySix: return CGPoint(x: 20, y: 23)
        case .forty: return CGPoint(x: 20, y: 22)
        case .fortyEight: return CGPoint(x: 28, y: 30)
        case .fiftySix: return CGPoint(x: 32, y: 38)
        case .sixtyFour: return CGPoint(x: 40, y: 46)
        case .eighty: return CGPoint(x: 44, y: 52)
        case .eightyEight: return CGPoint(x: 49, y: 56)
        case .oneHundredTwelve: return CGPoint(x: 74, y: 80)
        case .customDiameter:
            // Design hand-selected the above offsets for each size class
            // For anything in between, let's just stick the badge at the bottom left of the frame for now
            let avatarFrame = CGRect(origin: .zero, size: avatarSize)
            let offsetVector = CGVector(dx: -badgeSize.width, dy: -badgeSize.height)
            return avatarFrame.bottomRight.offsetBy(offsetVector)
        }
    }

    public func fetchImageFromBadgeAssets(_ badgeAssets: BadgeAssets) -> UIImage? {
        // Never show a badge less than 16 points
        // Otherwise, err on the side of downscaling over upscaling
        switch badgeDiameter {
        case ..<16: return nil
        case 16: return Theme.isDarkThemeEnabled ? badgeAssets.dark16 : badgeAssets.light16
        case 16...24: return Theme.isDarkThemeEnabled ? badgeAssets.dark24 : badgeAssets.light24
        case 24...: return Theme.isDarkThemeEnabled ? badgeAssets.dark36 : badgeAssets.light36
        default: return nil
        }
    }

    public var avatarSize: CGSize { .init(square: CGFloat(avatarDiameter)) }
    public var badgeSize: CGSize { .init(square: CGFloat(badgeDiameter)) }
}
