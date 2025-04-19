import Foundation
import AppsFlyerLib

public class AppsFlyerHelper {
    public static let shared = AppsFlyerHelper()
    
    private init() {}
    
    public func appsflyerStart() {
        AppsFlyerLib.shared().appsFlyerDevKey = AppsFlyerConstants.appsFlyerDevKey
        AppsFlyerLib.shared().appleAppID = AppsFlyerConstants.appleAppID
        AppsFlyerConstants.appsflyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        AppsFlyerLib.shared().start(completionHandler: { dictionary, error in
            if let error = error {
                print("Ошибка AppsFlyer: \(error.localizedDescription)")
            } else {
                print("Успешная установка: \(String(describing: dictionary))")
            }
        })
        
        AppsFlyerLib.shared().logEvent(name: AFEventCompleteRegistration, values: [
            AFEventParamRegistrationMethod: "app_install"
        ], completionHandler: { response, error in
            if let error = error {
                print("Ошибка отправки: \(error.localizedDescription)")
            } else {
                print("Событие регистрации отправлено: \(String(describing: response))")
            }
        })
    }
}
