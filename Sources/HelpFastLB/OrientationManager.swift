import SwiftUI

public enum AppOrientationType {
    case portrait
    case all
}

public class OrientationManager: ObservableObject {
    public static let shared = OrientationManager()
    @Published public var orientation: AppOrientationType = .portrait
    
    private init() {}
    
    // Функция для блокировки/разблокировки ориентации
    public func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        if orientation != .portrait {
            UINavigationController.attemptRotationToDeviceOrientation()
        } else {
            if UIDevice.current.orientation != .portrait {
                let value = UIInterfaceOrientation.portrait.rawValue
                UIDevice.current.setValue(value, forKey: "orientation")
            }
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
                OrientationManager.shared.lockOrientation(
                    orientation == .portrait ? .portrait : .all
                )
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
