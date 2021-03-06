import UIKit
import ARCL
import ARKit
import SceneKit
import CoreLocation
import DiningStack

@available(iOS 11.0, *)
class ARViewController: UIViewController, CLLocationManagerDelegate, SceneLocationViewDelegate {
    var sceneLocationView = SceneLocationView()
    var eateries: [Eatery] = []
    var nodes: [Eatery: LocationNode] = [:]
    var timer: Timer?
    var userLocation: CLLocation?
    var canUpdateLocation = true
    var alertedBeta = false

    var nearbyState: NearbyState = .none

    enum NearbyState {
        case nearby(eatery: Eatery, detailCard: EateryARDetailCard)
        case none
    }

    static func isSupported() -> Bool {
        return ARWorldTrackingConfiguration.isSupported
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        runARView()

        NotificationCenter.default.addObserver(forName: .UIApplicationDidEnterBackground, object: nil, queue: nil) { notification in
            self.dismissARViewController()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        alertBeta()
    }

    func runARView() {
        sceneLocationView.locationDelegate = self
        sceneLocationView.run()
        view.addSubview(sceneLocationView)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(#imageLiteral(resourceName: "closeIcon"), for: .normal)
        let inset: CGFloat = 18.0
        closeButton.imageEdgeInsets = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
        closeButton.layer.shadowRadius = 18.0
        closeButton.layer.shadowOpacity = 1.0
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(dismissARViewController), for: .touchUpInside)
        view.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(10.0)
            make.size.equalTo(60.0)
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(viewTapped(sender:)))
        sceneLocationView.addGestureRecognizer(tapGesture)

        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] timer in
            self?.canUpdateLocation = true
        }

        timer?.fire()
    }

    func alertBeta() {
        guard !alertedBeta else { return }
        alertedBeta = true

        let alertController = UIAlertController(title: "AR View is in Beta", message: "Please mind the rough edges! Make sure Eatery is allowed access to your Camera and Location Services.", preferredStyle: .alert)
        let settingsAction = UIAlertAction(title: "Settings", style: .default) { action in
            if let url = URL(string: UIApplicationOpenSettingsURLString) {
                UIApplication.shared.open(url, options: [:]) { success in
                    self.dismiss(animated: true, completion: nil)
                }
            }
        }
        alertController.addAction(settingsAction)

        let okAction = UIAlertAction(title: "OK", style: .cancel, handler: nil)
        alertController.addAction(okAction)

        present(alertController, animated: true, completion: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        sceneLocationView.frame = view.bounds
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    @objc func viewTapped(sender: UITapGestureRecognizer) {
        let point = sender.location(in: sceneLocationView)

        let results = sceneLocationView.hitTest(point)
        if let node = results.first?.node.parent as? LocationAnnotationNode,
            let eatery = nodes.first(where: { $0.value == node })?.key {
            presentMenuViewController(eatery: eatery)
        }
    }

    @objc func dismissARViewController() {
        for (_, node) in nodes {
            sceneLocationView.removeLocationNode(locationNode: node)
        }

        timer?.invalidate()
        sceneLocationView.pause()
        dismiss(animated: true) {
            self.sceneLocationView.removeFromSuperview()
        }
    }

    @objc func detailCardTapped() {
        if case let .nearby(eatery, _) = nearbyState {
            presentMenuViewController(eatery: eatery)
        }
    }

    func displayEateries() {
        guard let location = sceneLocationView.currentLocation() else { return }

        for eatery in eateries.filter({ $0.location.distance(from: location) / metersInMile < 0.5 }) {
            let frame = CGRect(x: 0.0, y: 0.0, width: 270.0, height: 54.0)
            let card = EateryARCard(frame: frame, eatery: eatery, userLocation: location)
            card.alpha = 0.8
            card.layer.cornerRadius = 4.0
            card.clipsToBounds = true

            let renderer = UIGraphicsImageRenderer(size: frame.size)
            let image = renderer.image { context in
                card.drawHierarchy(in: frame, afterScreenUpdates: true)
            }

            let scaledImage = UIImage(cgImage: image.cgImage!, scale: 0.1, orientation: image.imageOrientation)

            let location = CLLocation(coordinate: eatery.location.coordinate, altitude: eatery.altitude)

            let node = LocationAnnotationNode(location: location, image: scaledImage)
            node.scaleRelativeToDistance = true

            sceneLocationView.addLocationNodeWithConfirmedLocation(locationNode: node)
            nodes[eatery] = node
        }

        if let closestEatery = eateries.min(by: { $0.location.distance(from: location) < $1.location.distance(from: location) }),
            closestEatery.location.distance(from: location) / metersInMile < 0.05, let node = nodes[closestEatery] {
            sceneLocationView.removeLocationNode(locationNode: node)

            switch nearbyState {
            case .nearby(let eatery, _):
                if eatery != closestEatery {
                    dismissDetailCard {
                        self.presentDetailCard(eatery: closestEatery)
                    }
                }
            case .none:
                self.presentDetailCard(eatery: closestEatery)
            }
        } else {
            dismissDetailCard()
        }
    }

    func presentDetailCard(eatery: Eatery) {
        let card = EateryARDetailCard(eatery: eatery)
        view.addSubview(card)
        card.snp.makeConstraints { make in
            make.height.equalTo(200.0)
            make.leading.trailing.equalToSuperview().inset(20.0)
            make.bottom.equalToSuperview().offset(40.0)
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(detailCardTapped))
        card.addGestureRecognizer(tapGesture)

        nearbyState = .nearby(eatery: eatery, detailCard: card)

        card.transform = CGAffineTransform(translationX: 0.0, y: card.frame.height)
        UIView.animate(withDuration: 0.55, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [], animations: {
            card.transform = .identity
        }, completion: nil)
    }

    func dismissDetailCard(completion: (() -> Void)? = nil) {
        if case let .nearby(_, card) = nearbyState {
            UIView.animate(withDuration: 0.55, delay: 0.0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0.0, options: [], animations: {
                card.transform = CGAffineTransform(translationX: 0.0, y: card.frame.height)
            }, completion: { _ in
                card.removeFromSuperview()
                self.nearbyState = .none
                completion?()
            })
        } else {
            completion?()
        }
    }

    func presentMenuViewController(eatery: Eatery) {
        let menuViewController = MenuViewController(eatery: eatery, delegate: nil, userLocation: userLocation)
        let navigationController = UINavigationController(rootViewController: menuViewController)
        navigationController.navigationBar.barStyle = .black
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissMenuViewController))
        menuViewController.navigationItem.leftBarButtonItem = doneButton
        present(navigationController, animated: true, completion: nil)
    }

    @objc func dismissMenuViewController() {
        dismiss(animated: true, completion: nil)
    }

    func sceneLocationViewDidAddSceneLocationEstimate(sceneLocationView: SceneLocationView, position: SCNVector3, location: CLLocation) {
        self.userLocation = location
        DispatchQueue.main.async {
            guard self.canUpdateLocation else { return }
            self.canUpdateLocation = false

            for (eatery, node) in self.nodes {
                self.sceneLocationView.removeLocationNode(locationNode: node)
                self.nodes.removeValue(forKey: eatery)
            }

            self.displayEateries()
        }
    }

    func sceneLocationViewDidRemoveSceneLocationEstimate(sceneLocationView: SceneLocationView, position: SCNVector3, location: CLLocation) {

    }

    func sceneLocationViewDidConfirmLocationOfNode(sceneLocationView: SceneLocationView, node: LocationNode) {

    }

    func sceneLocationViewDidSetupSceneNode(sceneLocationView: SceneLocationView, sceneNode: SCNNode) {
    }

    func sceneLocationViewDidUpdateLocationAndScaleOfLocationNode(sceneLocationView: SceneLocationView, locationNode: LocationNode) {
    }

}
