//
//  AKMediaViewerController.swift
//  AKMediaViewer
//
//  Created by Diogo Autilio on 3/18/16.
//  Copyright © 2016 AnyKey Entertainment. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit

// MARK: - PlayerView

public class PlayerView: UIView {

    override public class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    func player() -> AVPlayer? {
        guard let avPlayer = (layer as? AVPlayerLayer) else {
            return nil
        }
        return avPlayer.player
    }

    func setPlayer(_ player: AVPlayer?) {
        if let avPlayer = (layer as? AVPlayerLayer) {
            avPlayer.player = player
        }
    }
}

// MARK: - AKMediaViewerController

public class AKMediaViewerController: UIViewController, UIScrollViewDelegate {

    public var tapGesture = UITapGestureRecognizer()
    public var doubleTapGesture = UITapGestureRecognizer()
    public var controlMargin: CGFloat = 0.0
    public var playerView: PlayerView?
    public var imageScrollView = AKImageScrollView()
    public var controlView: UIView?
    public var infiniteLoopForVideo: Bool = false
    
    @IBOutlet var mainImageView: UIImageView!
    @IBOutlet var titleLabel: UILabel!
    @IBOutlet var accessoryView: UIView!
    @IBOutlet var contentView: UIView!

    var accessoryViewTimer: Timer?
    var player: AVPlayer?
    var activityIndicator: UIActivityIndicatorView?

    var observersAdded = false

    struct ObservedValue {
        static let PresentationSize = "presentationSize"
        static let PlayerKeepUp = "playbackLikelyToKeepUp"
        static let PlayerHasEmptyBuffer = "playbackBufferEmpty"
        static let Status = "status"
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(AKMediaViewerController.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        controlMargin = 5.0

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(AKMediaViewerController.handleTap(_:)))
        tapGesture.require(toFail: doubleTapGesture)

        view.addGestureRecognizer(tapGesture)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeObservers(player: self.player)
        player?.removeObserver(self, forKeyPath: ObservedValue.Status)
        if infiniteLoopForVideo {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }

        mainImageView = nil
        contentView = nil
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        titleLabel.layer.shadowOpacity = 1
        titleLabel.layer.shadowOffset = CGSize.zero
        titleLabel.layer.shadowRadius = 1
        accessoryView.alpha = 0
    }

    override public func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        removeObservers(player: self.player)
    }

    func removeObservers(player: AVPlayer?) {
        if observersAdded {
            guard let item = player?.currentItem else {
                return
            }

            item.removeObserver(self, forKeyPath: ObservedValue.PresentationSize)
            item.removeObserver(self, forKeyPath: ObservedValue.PlayerKeepUp)
            item.removeObserver(self, forKeyPath: ObservedValue.PlayerHasEmptyBuffer)
            observersAdded = false
        }
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override public func beginAppearanceTransition(_ isAppearing: Bool, animated: Bool) {
        if !isAppearing {
            accessoryView.alpha = 0.0
            playerView?.alpha = 0.0
        }
    }

    override public func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerView?.frame = mainImageView.bounds
    }

    // MARK: - Public

    public func showPlayerWithURL(_ url: URL) {
        playerView = PlayerView(frame: mainImageView.bounds)
        mainImageView.addSubview(self.playerView!)
        playerView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView?.isHidden = true

        // install loading spinner for remote files
        if !url.isFileURL {
            self.activityIndicator = UIActivityIndicatorView(style: .whiteLarge)
            self.activityIndicator?.frame = UIScreen.main.bounds
            self.activityIndicator?.hidesWhenStopped = true
            view.addSubview(self.activityIndicator!)
            self.activityIndicator?.startAnimating()
        }

        DispatchQueue.main.async(execute: { () -> Void in
            // remove old item observer if exists
            self.removeObservers(player: self.player)

            self.player = AVPlayer(url: url)
            self.playerView?.setPlayer(self.player)
            self.player?.currentItem?.addObserver(self, forKeyPath: ObservedValue.PresentationSize, options: .new, context: nil)
            self.player?.currentItem?.addObserver(self, forKeyPath: ObservedValue.PlayerHasEmptyBuffer, options: .new, context: nil)
            self.player?.currentItem?.addObserver(self, forKeyPath: ObservedValue.PlayerKeepUp, options: .new, context: nil)
            self.observersAdded = true
            self.player?.addObserver(self, forKeyPath: ObservedValue.Status, options: .initial, context: nil)
            self.layoutControlView()
        })
    }

    public func focusDidEndWithZoomEnabled(_ zoomEnabled: Bool) {
        if zoomEnabled && (playerView == nil) {
            installZoomView()
        }

        view.setNeedsLayout()
        showAccessoryView(true)
        playerView?.isHidden = false

        addAccessoryViewTimer()

        if player?.status == .readyToPlay {
            playPLayer()
        }
    }

    public func defocusWillStart() {
        if playerView == nil {
            uninstallZoomView()
        }
        pinAccessoryView()
        player?.pause()
    }

    // MARK: - Private

    func addAccessoryViewTimer() {
        if player != nil {
            accessoryViewTimer = Timer.scheduledTimer(timeInterval: 1.5, target: self, selector: #selector(AKMediaViewerController.removeAccessoryViewTimer), userInfo: nil, repeats: false)
        }
    }

    @objc
    func removeAccessoryViewTimer() {
        accessoryViewTimer?.invalidate()
        showAccessoryView(false)
    }

    func installZoomView() {
        let scrollView = AKImageScrollView(frame: contentView.bounds)
        scrollView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        scrollView.delegate = self
        imageScrollView = scrollView
        contentView.insertSubview(scrollView, at: 0)
        scrollView.displayImage(mainImageView.image!)
        self.mainImageView.isHidden = true

        imageScrollView.addGestureRecognizer(doubleTapGesture)
    }

    func uninstallZoomView() {
        if let zoomImageViewFrame = imageScrollView.zoomImageView?.frame {
            let frame = contentView.convert(zoomImageViewFrame, from: imageScrollView)
            imageScrollView.isHidden = true
            mainImageView.isHidden = false
            mainImageView.frame = frame
        }
    }

    func isAccessoryViewPinned() -> Bool {
        return (accessoryView.superview == view)
    }

    func pinView(_ view: UIView) {
        let frame = self.view.convert(view.frame, from: view.superview)
        view.transform = view.superview!.transform
        self.view.addSubview(view)
        view.frame = frame
    }

    func pinAccessoryView() {
        // Move the accessory views to the main view in order not to be rotated along with the media.
        pinView(accessoryView)
    }

    func showAccessoryView(_ visible: Bool) {
        if visible == accessoryViewsVisible() {
            return
        }

        UIView.animate(withDuration: 0.5, delay: 0, options: [UIView.AnimationOptions.beginFromCurrentState, UIView.AnimationOptions.allowUserInteraction], animations: { () -> Void in
            self.accessoryView.alpha = (visible ? 1.0 : 0.0)
        }, completion: nil)
    }

    func accessoryViewsVisible() -> Bool {
        return (accessoryView.alpha == 1.0)
    }

    func layoutControlView() {

        if isAccessoryViewPinned() {
            return
        }

        if self.controlView == nil {
            if let controlView = AKVideoControlView.videoControlView() {
                controlView.translatesAutoresizingMaskIntoConstraints = false
                controlView.scrubbing.player = player
                self.controlView = controlView
                accessoryView.addSubview(controlView)
            }
        }

        if var controlViewframe = self.controlView?.frame {
            controlViewframe.size.width = self.view.bounds.size.width - self.controlMargin * 2
            controlViewframe.origin.x = self.controlMargin

            let videoFrame = buildVideoFrame()
            let titleFrame = self.controlView!.superview!.convert(titleLabel.frame, from: titleLabel.superview)
            controlViewframe.origin.y = titleFrame.origin.y - controlViewframe.size.height - self.controlMargin
            if videoFrame.size.width > 0 {
                controlViewframe.origin.y = min(controlViewframe.origin.y, videoFrame.maxY - controlViewframe.size.height - self.controlMargin)
            }
            self.controlView!.frame = controlViewframe
        }
    }

    func buildVideoFrame() -> CGRect {

        guard let playerCurrentItem = self.player?.currentItem, playerCurrentItem.presentationSize.equalTo(.zero) else {
            return .zero
        }

        let frame = AVMakeRect(aspectRatio: playerCurrentItem.presentationSize, insideRect: self.playerView!.bounds)
        return frame.integral
    }

    func playPLayer() {
        activityIndicator?.stopAnimating()
        player?.play()
        if infiniteLoopForVideo {
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem, queue: .main) { (_) in
                self.player?.seek(to: CMTime.zero)
                self.player?.play()
            }
        }
    }

    // MARK: - Actions

    @objc
    func handleTap(_ gesture: UITapGestureRecognizer) {
        if imageScrollView.zoomScale == imageScrollView.minimumZoomScale {
            showAccessoryView(!accessoryViewsVisible())
        }
    }

    @objc
    func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        var frame = CGRect.zero
        var scale = imageScrollView.maximumZoomScale

        if imageScrollView.zoomScale == imageScrollView.minimumZoomScale {
            if let contentView = imageScrollView.delegate?.viewForZooming?(in: imageScrollView) {
                let location = gesture.location(in: contentView)
                frame = CGRect(x: location.x * imageScrollView.maximumZoomScale - imageScrollView.bounds.size.width / 2, y: location.y * imageScrollView.maximumZoomScale - imageScrollView.bounds.size.height / 2, width: imageScrollView.bounds.size.width, height: imageScrollView.bounds.size.height)
            }
        } else {
            scale = imageScrollView.minimumZoomScale
        }

        UIView.animate(withDuration: 0.5, delay: 0, options: .beginFromCurrentState, animations: { () -> Void in
            self.imageScrollView.zoomScale = scale
            self.imageScrollView.layoutIfNeeded()
            if scale == self.imageScrollView.maximumZoomScale {
                self.imageScrollView.scrollRectToVisible(frame, animated: false)
            }
        }, completion: nil)

    }

    // MARK: - <UIScrollViewDelegate>

    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageScrollView.zoomImageView
    }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        showAccessoryView(imageScrollView.zoomScale == imageScrollView.minimumZoomScale)
    }

    // MARK: - KVO

    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {

        guard let keyPath = keyPath else {
            return
        }

        switch keyPath {

        case ObservedValue.PlayerKeepUp:
            guard let playerCurrentItem = player?.currentItem else {
                return
            }
            if playerCurrentItem.isPlaybackLikelyToKeepUp {
                playPLayer()
            }

        case ObservedValue.Status:
            guard let status = player?.status else {
                return
            }
            switch status {
            case .readyToPlay:
                playPLayer()
            default:
                player?.pause()
                activityIndicator?.startAnimating()
            }

        case ObservedValue.PlayerHasEmptyBuffer:
            activityIndicator?.startAnimating()

        case ObservedValue.PresentationSize:
            view.setNeedsDisplay()

        default:
            break
        }
    }
}
