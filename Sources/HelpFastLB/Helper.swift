import SwiftUI

@MainActor
public final class TokensHelper {
    
    public weak var delegate: RequestsManagerDelegate?
    
    @ObservedObject var monitor = NetworkMonitor.shared
    private let urlStorageKey = "receivedURL"
    private let hasLaunchedBeforeKey = "hasLaunchedBefore"
    private var apnsToken =  "token"
    private var attToken = "token"
    private var retryCount = 0
    private let maxRetryCount = 3
    private let retryDelay = 3.0
    
    public init(appsDevKey: String, appleAppId: String, baseSsylka: String, isOkay: String?) {
        AppsFlyerConstants.appleAppID = appleAppId
        AppsFlyerConstants.appsFlyerDevKey = appsDevKey
        Constants.unlockDate = isOkay
        Constants.baseGameURL = baseSsylka
    }
    
    public func getData() async {
        
        
        if !monitor.isActive {
            await retryInternetConnection()
            return
        }
        
        retryCount = 0
        
        if !isFirstLaunch() {
            handleStoredState()
            return
        }
        
        await getTokens()
    }
    
    private func handleStoredState() {
        if let urlString = UserDefaults.standard.string(forKey: urlStorageKey), let url = URL(string: urlString) {
            updateLoading(object: url)
        }
    }
    
    private func getFinalUrl(data: [String: String]) -> String {
        // Обработка случая с пустыми данными
        let safeData = data.isEmpty ? ["apns_token": "token", "appsflyer_id": "default"] : data
        
        let queryItems = safeData.map { URLQueryItem(name: $0.key, value: $0.value) }
        var components = URLComponents()
        components.queryItems = queryItems
        
        guard let queryString = components.query?.data(using: .utf8) else {
            // Если не удалось сформировать query, отправляем дефолтную строку
            let defaultBase64 = "apns_token=token&appsflyer_id=default".data(using: .utf8)!.base64EncodedString()
            return Constants.baseGameURL.decodePercentEncoding() +
                   "%3F%64%61%74%61%3D".decodePercentEncoding() +
                   defaultBase64
        }
        
        let base64String = queryString.base64EncodedString()
        let fullUrlString = Constants.baseGameURL.decodePercentEncoding() +
                             "%2F%3F%64%61%74%61%3D".decodePercentEncoding() +
                             base64String
        
        return fullUrlString
    }
    
    private func retryInternetConnection() async {
        if retryCount >= maxRetryCount {
            DispatchQueue.main.async {
                self.monitor.showInternetALert = true
            }
            retryCount = 0
            return
        }
        retryCount += 1
        
        try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
        
        if monitor.isActive {
            retryCount = 0
            
            if !isFirstLaunch() {
                handleStoredState()
            } else {
                await getTokens()
            }
        } else {
           
            await retryInternetConnection()
        }
    }

    private func getTokens() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var isContinuationResumed = false
            
            func safeResume() {
                if !isContinuationResumed {
                    isContinuationResumed = true
                    continuation.resume()
                }
            }
            
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            
            let timeout = DispatchTime.now() + 5
            
            let observer = NotificationCenter.default.addObserver(
                forName: .apnsTokenReceived,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                
                if let token = notification.userInfo?["token"] as? String {
                    Task { @MainActor in
                        self.apnsToken = token
                        if let url = URL(string: self.getFinalUrl(data: self.getDeviceData())) {
                            self.sendNTFQuestionToUser()
                            self.handleFirstLaunchSuccess(url: url)
                        }
                        safeResume()
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: timeout) { [weak self] in
                guard let self = self else { return }
                
                NotificationCenter.default.removeObserver(observer)
                
                if self.apnsToken.isEmpty || self.apnsToken == "token" {
                    Task { @MainActor in
                        self.apnsToken = "token"
                        
                        let urlString = self.getFinalUrl(data: self.getDeviceData())
                        
                        if let url = URL(string: urlString) {
                            self.sendNTFQuestionToUser()
                            self.handleFirstLaunchSuccess(url: url)
                        }
                        
                        safeResume()
                    }
                } else {
                    safeResume()
                }
            }
        }
    }
    
    func getDeviceData() -> [String: String] {
        let safeApnsToken = apnsToken.isEmpty ? "token" : apnsToken
        
        let data = [
            "apns_token": safeApnsToken,
            "appsflyer_id" : AppsFlyerConstants.appsflyerID ?? "default"
        ]
        print(data)
        return data
    }
    
    private func isFirstLaunch() -> Bool {
        !UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
    }
    
    private func handleFirstLaunchSuccess(url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: urlStorageKey)
        UserDefaults.standard.set(true, forKey: hasLaunchedBeforeKey)
        updateLoading(object: url)
    }
    
   
    
    func isShowWV() -> Bool {
        return UserDefaults.standard.bool(forKey: hasLaunchedBeforeKey)
    }
    
    func sendNTFQuestionToUser() {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) {_, _ in }
    }
}

// MARK: - RequestsManager Notifications Extension

extension TokensHelper {
    func updateLoading(object: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.delegate?.handle(action: .success(object))
        }
    }
    
    func showGame(object: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.delegate?.handle(action: .game(object))
        }
    }
}
