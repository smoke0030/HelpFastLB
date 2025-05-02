import SwiftUI

public enum AppOrientationType {
    case portrait
    case landscape
    case all
    
    public var mask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape:
            return [.landscapeLeft, .landscapeRight]
        case .all:
            return .all
        }
    }
}

public class OrientationManager: ObservableObject {
    public static let shared = OrientationManager()
    @Published public var orientation: AppOrientationType = .portrait
    
    private init() {}
    
    // Функция для блокировки/разблокировки ориентации
    public func lockOrientation(_ orientationType: AppOrientationType) {
        let orientation = orientationType.mask
        
        switch orientationType {
        case .portrait:
            if UIDevice.current.orientation != .portrait {
                let value = UIInterfaceOrientation.portrait.rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
            }
        case .landscape:
            if !UIDevice.current.orientation.isLandscape {
                let value = UIInterfaceOrientation.landscapeRight.rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
            }
        case .all:
            UINavigationController.attemptRotationToDeviceOrientation()
        }
    }
}

// Модификатор для View, который применяет выбранную ориентацию
public struct OrientationModifier: ViewModifier {
    let orientation: AppOrientationType
    
    public init(orientation: AppOrientationType) {
        self.orientation = orientation
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                OrientationManager.shared.orientation = orientation
                
                // Применяем нужную ориентацию при появлении view
                OrientationManager.shared.lockOrientation(orientation)
            }
    }
}

// Расширение для View для удобного применения ориентации
public extension View {
    func supportedOrientations(_ orientation: AppOrientationType) -> some View {
        modifier(OrientationModifier(orientation: orientation))
    }
}

// Протокол для делегирования получения ориентации
public protocol OrientationDelegate: AnyObject {
    func getCurrentOrientation() -> UIInterfaceOrientationMask
}
