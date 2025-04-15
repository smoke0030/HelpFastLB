import SwiftUI
@preconcurrency import WebKit
import AdServices
import UserNotifications


struct MainView: View {
    @EnvironmentObject var appVM: AppViewModel
    let url: URL
    init(url: URL) {
        self.url = url
    }
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            WebView(mainUrl: url)
                .environmentObject(appVM)
            if appVM.loaderActive {
                ProgressView()
            }
        }
        
        .statusBarHidden(true)
    }
}

struct WebView: UIViewRepresentable {
    @EnvironmentObject var appVM: AppViewModel
    var mainUrl: URL
    
    init(mainUrl: URL) {
        self.mainUrl = mainUrl
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        config.websiteDataStore = WKWebsiteDataStore.default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        webView.evaluateJavaScript("navigator.userAgent") { (result, error) in
            if let userAgent = result as? String {
                let patchedUserAgent = self.patchUserAgent(userAgent)
                print(patchedUserAgent)
                webView.customUserAgent = patchedUserAgent
            }
        }
        
        let request = URLRequest(url: mainUrl, cachePolicy: .returnCacheDataElseLoad)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.appVM.loaderActive = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.appVM.loaderActive = false
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Page load failed with error: \(error.localizedDescription)")
            parent.appVM.loaderActive = false
        }
        
        
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                if navigationAction.targetFrame == nil {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
            }
            
            decisionHandler(.allow)
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        
        
    }
}

extension WebView {
    private func patchUserAgent(_ userAgent: String) -> String {
        let versionSubstring = "Version/16.2"
        var patchedAgent = userAgent
        
        if !patchedAgent.contains("Version/") {
            if let position = patchedAgent.range(of: "like Gecko)")?.upperBound {
                patchedAgent.insert(contentsOf: " " + versionSubstring, at: position)
            } else if let position = patchedAgent.range(of: "Mobile/")?.lowerBound {
                patchedAgent.insert(contentsOf: versionSubstring + " ", at: position)
            }
        }
        
        return patchedAgent
    }
    
    static func clearCache() {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
            print("Cache cleared")
        }
    }
}

fileprivate struct Urls: Decodable {
    let backUrl1: String
    let backUrl2: String
    
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
        self.backUrl1 = try container.decode(String.self, forKey: DynamicCodingKeys(stringValue: Constants.backUrl1.decodePercentEncoding())!)
        self.backUrl2 = try container.decode(String.self, forKey: DynamicCodingKeys(stringValue: Constants.backUrl2.decodePercentEncoding())!)
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


@MainActor
public class RequestsManager {
    
    public init(one: String, two: String, okay: String?) {
        Constants.backUrl1 = one
        Constants.backUrl2 = two
        Constants.unlockDate = okay
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInternetConnectionRestored),
            name: .internetConnectionRestored,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    
    fileprivate var networkService: INetworkService {
        return NetworkService()
    }
    
    @ObservedObject var monitor = NetworkMonitor.shared
    private let urlStorageKey = "receivedURL"
    private var apnsToken = "default"
    private var attToken = "default"
    private var retryCount = 0
    private let maxRetryCount = 3
    private let retryDelay = 3.0
    
    @objc private func handleInternetConnectionRestored() {
        // Когда интернет восстановлен
        if monitor.showInternetALert {
            // Если было показано предупреждение - скрываем его и повторяем запрос
            monitor.showInternetALert = false
            retryCount = 0
            Task {
                await getTokens()
            }
        }
    }
    
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
        
        await getTokens()
        
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
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            let timeout = DispatchTime.now() + 5 // таймаут
            
            NotificationCenter.default.addObserver(forName: .apnsTokenReceived, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                
                if let token = notification.userInfo?["token"] as? String {
                    Task { @MainActor in
                        self.apnsToken = token
                        continuation.resume()
                    }
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: timeout) { [weak self] in
                guard let self = self else { return }
                if self.apnsToken == "default"  {
                    Task { @MainActor in
                        print("APNs токен не получен")
                        continuation.resume()
                    }
                }
            }
        }
        
        do {
            self.attToken = try AAAttribution.attributionToken()
        } catch {
            print("Не удалось получить ATT токен: \(error)")
            self.attToken = "default"
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
            "att_token": attToken
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
            NotificationCenter.default.post(name: .failUpload, object: nil)
        }
    }
    
    func successLoading(object: URL) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .urlUpdated, object: object)
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
            
            guard !decodedData.backUrl1.isEmpty, !decodedData.backUrl2.isEmpty else {
                completion(.failure(URLDecodingError.emptyParameters))
                return
            }
            
            guard let url = URL(string: Constants.protoco.decodePercentEncoding() + decodedData.backUrl1 + decodedData.backUrl2) else {
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
    
    static var backUrl1 = "%77%68%69%73%6B"
    static var backUrl2 = "%67%75%73%74%79"
    static var unlockDate: String?
    static var protoco = "%68%74%74%70%73%3A%2F%2F"
    static var index = "%2E%74%6F%70%2F%69%6E%64%65%78%6E%2E%70%68%70"
    static var data = "%3F%64%61%74%61%3D"
    
}


class AppViewModel: ObservableObject {
    @Published var loaderActive = true
}





