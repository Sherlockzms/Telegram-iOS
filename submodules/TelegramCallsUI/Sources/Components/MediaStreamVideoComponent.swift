import Foundation
import UIKit
import ComponentFlow
import ActivityIndicatorComponent
import AccountContext
import AVKit

final class MediaStreamVideoComponent: Component {
    let call: PresentationGroupCallImpl
    let hasVideo: Bool
    let activatePictureInPicture: ActionSlot<Action<Void>>
    let bringBackControllerForPictureInPictureDeactivation: (@escaping () -> Void) -> Void
    
    init(call: PresentationGroupCallImpl, hasVideo: Bool, activatePictureInPicture: ActionSlot<Action<Void>>, bringBackControllerForPictureInPictureDeactivation: @escaping (@escaping () -> Void) -> Void) {
        self.call = call
        self.hasVideo = hasVideo
        self.activatePictureInPicture = activatePictureInPicture
        self.bringBackControllerForPictureInPictureDeactivation = bringBackControllerForPictureInPictureDeactivation
    }
    
    public static func ==(lhs: MediaStreamVideoComponent, rhs: MediaStreamVideoComponent) -> Bool {
        if lhs.call !== rhs.call {
            return false
        }
        if lhs.hasVideo != rhs.hasVideo {
            return false
        }
        
        return true
    }
    
    public final class State: ComponentState {
        override init() {
            super.init()
        }
    }
    
    public func makeState() -> State {
        return State()
    }
    
    public final class View: UIView, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate, ComponentTaggedView {
        public final class Tag {
        }
        
        private let videoRenderingContext = VideoRenderingContext()
        private var videoView: VideoRenderingView?
        private let blurTintView: UIView
        private var videoBlurView: VideoRenderingView?
        private var activityIndicatorView: ComponentHostView<Empty>?
        
        private var pictureInPictureController: AVPictureInPictureController?
        
        private var component: MediaStreamVideoComponent?
        private var hadVideo: Bool = false
        
        override init(frame: CGRect) {
            self.blurTintView = UIView()
            self.blurTintView.backgroundColor = UIColor(white: 0.0, alpha: 0.55)
            
            super.init(frame: frame)
            
            self.isUserInteractionEnabled = false
            self.clipsToBounds = true
            
            self.addSubview(self.blurTintView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func matches(tag: Any) -> Bool {
            if let _ = tag as? Tag {
                return true
            }
            return false
        }
        
        func expandFromPictureInPicture() {
            self.pictureInPictureController?.stopPictureInPicture()
        }
        
        func update(component: MediaStreamVideoComponent, availableSize: CGSize, state: State, transition: Transition) -> CGSize {
            if component.hasVideo, self.videoView == nil {
                if let input = component.call.video(endpointId: "unified") {
                    if let videoBlurView = self.videoRenderingContext.makeView(input: input, blur: true) {
                        self.videoBlurView = videoBlurView
                        self.insertSubview(videoBlurView, belowSubview: self.blurTintView)
                    }
                    
                    if let videoView = self.videoRenderingContext.makeView(input: input, blur: false, forceSampleBufferDisplayLayer: true) {
                        self.videoView = videoView
                        self.addSubview(videoView)
                        
                        if #available(iOSApplicationExtension 15.0, iOS 15.0, *), AVPictureInPictureController.isPictureInPictureSupported(), let sampleBufferVideoView = videoView as? SampleBufferVideoRenderingView {
                            let pictureInPictureController = AVPictureInPictureController(contentSource: AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: sampleBufferVideoView.sampleBufferLayer, playbackDelegate: self))
                            
                            pictureInPictureController.delegate = self
                            pictureInPictureController.canStartPictureInPictureAutomaticallyFromInline = true
                            pictureInPictureController.requiresLinearPlayback = true
                            
                            self.pictureInPictureController = pictureInPictureController
                        }
                        
                        videoView.setOnOrientationUpdated { [weak state] _, _ in
                            state?.updated(transition: .immediate)
                        }
                        videoView.setOnFirstFrameReceived { [weak self, weak state] _ in
                            guard let strongSelf = self else {
                                return
                            }
                            
                            strongSelf.hadVideo = true
                            strongSelf.activityIndicatorView?.removeFromSuperview()
                            strongSelf.activityIndicatorView = nil
                            
                            state?.updated(transition: .immediate)
                        }
                    }
                }
            }
            
            if let videoView = self.videoView {
                videoView.updateIsEnabled(true)
                var aspect = videoView.getAspect()
                if aspect <= 0.01 {
                    aspect = 3.0 / 4.0
                }
                
                let videoSize = CGSize(width: aspect * 100.0, height: 100.0).aspectFitted(availableSize)
                let blurredVideoSize = videoSize.aspectFilled(availableSize)
                
                transition.withAnimation(.none).setFrame(view: videoView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - videoSize.width) / 2.0), y: floor((availableSize.height - videoSize.height) / 2.0)), size: videoSize), completion: nil)
                
                if let videoBlurView = self.videoBlurView {
                    videoBlurView.updateIsEnabled(true)
                    transition.withAnimation(.none).setFrame(view: videoBlurView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - blurredVideoSize.width) / 2.0), y: floor((availableSize.height - blurredVideoSize.height) / 2.0)), size: blurredVideoSize), completion: nil)
                }
            }
            
            if !self.hadVideo {
                var activityIndicatorTransition = transition
                let activityIndicatorView: ComponentHostView<Empty>
                if let current = self.activityIndicatorView {
                    activityIndicatorView = current
                } else {
                    activityIndicatorTransition = transition.withAnimation(.none)
                    activityIndicatorView = ComponentHostView<Empty>()
                    self.activityIndicatorView = activityIndicatorView
                    self.addSubview(activityIndicatorView)
                }
                
                let activityIndicatorSize = activityIndicatorView.update(
                    transition: transition,
                    component: AnyComponent(ActivityIndicatorComponent()),
                    environment: {},
                    containerSize: CGSize(width: 100.0, height: 100.0)
                )
                activityIndicatorTransition.setFrame(view: activityIndicatorView, frame: CGRect(origin: CGPoint(x: floor((availableSize.width - activityIndicatorSize.width) / 2.0), y: floor((availableSize.height - activityIndicatorSize.height) / 2.0)), size: activityIndicatorSize), completion: nil)
            }
            
            self.component = component
            
            component.activatePictureInPicture.connect { [weak self] completion in
                guard let strongSelf = self, let pictureInPictureController = strongSelf.pictureInPictureController else {
                    return
                }
                
                pictureInPictureController.startPictureInPicture()
                
                completion(Void())
            }
            
            return availableSize
        }
        
        public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        }

        public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
            return CMTimeRange(start: .zero, duration: .positiveInfinity)
        }

        public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
            return false
        }

        public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        }

        public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        public func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
            return false
        }
        
        public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
            guard let component = self.component else {
                completionHandler(false)
                return
            }

            component.bringBackControllerForPictureInPictureDeactivation {
                completionHandler(true)
            }
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: State, environment: Environment<Empty>, transition: Transition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, transition: transition)
    }
}
