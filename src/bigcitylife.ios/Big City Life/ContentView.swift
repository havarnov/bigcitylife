//
//  ContentView.swift
//  Big City Life
//
//  Created by havarnov on 29/11/2020.
//

import SwiftUI
import CoreLocation
import SwiftSignalRClient

public struct GroupChatMessage: Codable {
    let ChatName: String
    let Message: String
}

struct JoinGroupChatMessage: Codable {
    let Name: String
}

public class SignalRService {
    var connection: HubConnection
    var onMessageReceived: (GroupChatMessage, MessageSender) -> Void
    var userId: String
    
    fileprivate init(url: URL, hubConnectionDelegate: HubConnectionDelegate, onMessageReceived: @escaping (GroupChatMessage, MessageSender) -> Void) {
        let userId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        self.userId = userId
        self.onMessageReceived = onMessageReceived
        
        connection = HubConnectionBuilder(url: url)
            .withHttpConnectionOptions(configureHttpOptions: {options in
                options.headers["x-ms-signalr-user-id"] = userId
            })
            .withLogging(minLogLevel: .error)
            .withAutoReconnect()
            .build()
        connection.delegate = hubConnectionDelegate

        connection.on(method: "newMessage", callback: { (userId: String, msg: GroupChatMessage) in
            self.handleMessage(msg, userId)
        })
        
        connection.start()
    }
    
    private func handleMessage(_ message: GroupChatMessage, _ userId: String) {
        print("\(message.ChatName): \(message.Message)")
        
        var sender: MessageSender
        if userId == self.userId {
            sender = .myself(self.userId)
        }
        else {
            sender = .other(userId)
        }
        
        self.onMessageReceived(message, sender)
    }
    
    func sendToGroupChat(msg: GroupChatMessage) {
        connection.invoke(method: "sendToGroupChat", msg) { error in
            if let error = error {
                print("error: \(error)")
            } else {
                print("sendToGroupChat invocation completed without errors")
            }
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    public var onStatusChanged: ((CLAuthorizationStatus?) -> Void)?
    public var onPlacemarkChanged: ((CLPlacemark?) -> Void)?
    
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.onStatusChanged?(status)
    }
    
    // Below method will provide you current location.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        geocoder.reverseGeocodeLocation(
            location,
            preferredLocale: Locale(identifier: "en_US"),
            completionHandler: { (places, error) in
          if error == nil {
            self.onPlacemarkChanged?(places?[0])
          } else {
            self.onPlacemarkChanged?(nil)
          }
        })
    }

    // Below Mehtod will print error if not able to update location.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Error: \(error)")
    }
    
    func startUpdatingLocation() {
        self.locationManager.startUpdatingLocation()
    }
}

enum ChatItem: Hashable {
    case message(Message)
    case disconnctedMarker(UUID)
    case reconnectedMarker(UUID)
}

extension ChatItem: Identifiable {
    var id: UUID {
        switch self {
        case .disconnctedMarker(let uuid):
            return uuid
        case .message(let msg):
            return msg.id
        case .reconnectedMarker(let uuid):
            return uuid
        }
    }
}

enum MessageSender: Hashable {
    case other(String)
    case myself(String)
}

struct Message:Identifiable, Hashable {
    var id = UUID()
    var sender: MessageSender
    var color: Color
    var value: String
}

class ContentViewModel: ObservableObject, HubConnectionDelegate {
    var signalRService: SignalRService?
    var locationManager = LocationManager()
    var colorDict: [String:Color] = [:]
    
    @Published var enteredForeground = true
    @Published var isConnected = false
    @Published var joinedChat = false
    @Published var status: CLAuthorizationStatus?
    @Published var placemark: CLPlacemark?
    @Published var chatMsg: String = ""
    @Published var receivedMsg: [ChatItem] = []
  
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground), name: UIScene.willEnterForegroundNotification, object: nil)
        signalRService = SignalRService(url: URL(string: "https://bigcitylife.azurewebsites.net/api")!, hubConnectionDelegate: self, onMessageReceived: self.onMessageReceived)
        locationManager.onStatusChanged = self.onStatusChanged
        locationManager.onPlacemarkChanged = self.onPlacemarkChanged
    }
    
    func onMessageReceived(message: GroupChatMessage, sender: MessageSender) {
        var userId: String
        
        switch sender {
        case .myself(let uId):
            userId = uId
        case .other(let uId):
            userId = uId
        }
        
        var color: Color
        
        if let index = self.colorDict.firstIndex(where: { (k, v) in k == userId} ) {
            color = self.colorDict[index].value
        }
        else {
            color = Color.init(red: Double.random(in: 0...1), green: Double.random(in: 0...1), blue: Double.random(in: 0...1))
            colorDict[userId] = color
        }
        
        self.receivedMsg.append(.message(Message(sender: sender, color: color, value: message.Message)))
    }

    @objc func willEnterForeground() {
        enteredForeground.toggle()
    }
    
    public func onStatusChanged(status: CLAuthorizationStatus?) -> Void {
        self.status = status
    }
    
    public func onPlacemarkChanged(placemark: CLPlacemark?) -> Void {
        if self.placemark == placemark || (self.placemark != nil && placemark == nil) {
            return
        }
        
        // TODO leave chat
        
        self.placemark = placemark
        
        if self.isConnected && self.placemark != nil {
            print("her1")
            let msg = JoinGroupChatMessage(Name: getChatName()!)
            signalRService!.connection.invoke(method: "joinGroupChat", msg) { error in
                if let error = error {
                    print("error: \(error)")
                } else {
                    self.joinedChat = true;
                    print("joinGroupChat invocation completed without errors")
                }
            }
        }
    }
    
    public func connectionDidOpen(hubConnection: HubConnection) {
        self.isConnected = true
        if self.placemark != nil {
            print("her2")
            let msg = JoinGroupChatMessage(Name: getChatName()!)
            signalRService!.connection.invoke(method: "joinGroupChat", msg) { error in
                if let error = error {
                    print("error: \(error)")
                } else {
                    self.joinedChat = true;
                    print("joinGroupChat invocation completed without errors")
                }
            }
        }
    }
    
    private func getChatName() -> String? {
        guard let placemark = self.placemark else {
            return nil
        }
        
        // TODO: what if nil?
        return "\(placemark.locality ?? "")::\(placemark.country ?? "")"
    }
    
    public func connectionDidFailToOpen(error: Error) {
        print("connectionDidFailToOpen: \(error)")
        self.isConnected = false
        self.joinedChat = false
    }
    
    public func connectionDidClose(error: Error?) {
        print("connectionDidClose: \(String(describing: error))")
        self.isConnected = false
        self.joinedChat = false
        self.receivedMsg.append(.disconnctedMarker(UUID()))
    }
    
    public func connectionWillReconnect(error: Error) {
        print("connectionWillReconnect: \(error)")
        self.isConnected = false
        self.joinedChat = false
        self.receivedMsg.append(.disconnctedMarker(UUID()))
    }

    func connectionDidReconnect() {
        self.isConnected = true
        if self.placemark != nil {
            print("her3")
            let msg = JoinGroupChatMessage(Name: getChatName()!)
            signalRService!.connection.invoke(method: "joinGroupChat", msg) { error in
                if let error = error {
                    print("error: \(error)")
                } else {
                    self.joinedChat = true;
                    self.receivedMsg.append(.reconnectedMarker(UUID()))
                    print("joinGroupChat invocation completed without errors")
                }
            }
        }
    }
    
    func sendToGroupChat() {
        let msg = GroupChatMessage(ChatName: getChatName()!, Message: self.chatMsg)
        signalRService!.sendToGroupChat(msg: msg)
        self.chatMsg = ""
    }
    
    func startUpdateLocation() {
        self.locationManager.startUpdatingLocation()
    }
}

struct ContentView: View {
    @ObservedObject var viewModel = ContentViewModel()
    let dateFormatterGet = DateFormatter()
    
    init() {
        dateFormatterGet.dateFormat = "HH:mm"
    }

    var body: some View {
        VStack {
            if let status = self.viewModel.status, (status == .denied || status == .restricted) {
                Text("App not authorized to access device location.")
            }
            else if let placemark = self.viewModel.placemark {
                let city = "\(placemark.locality ?? "City Information N/A]"), \(placemark.country ?? "Country Information N/A")"
                Text(city)
                    .font(.largeTitle)
                
                ScrollView(.vertical) {
                    ScrollViewReader { scrollView in
                        LazyVStack {
                            ForEach(self.viewModel.receivedMsg.reversed(), id: \.id) { item in
                                switch (item) {
                                case .message(let msg):
                                    HStack {
                                        switch msg.sender {
                                        case .myself(_):
                                            Spacer()
                                            Text(msg.value)
                                                .foregroundColor(msg.color)
                                                .font(.system(size: 20.0))
                                                .padding(.trailing)
                                        case .other(_):
                                            Text(msg.value)
                                                .foregroundColor(msg.color)
                                                .font(.system(size: 20.0))
                                                .padding(.leading)
                                            Spacer()
                                        }
                                    }

                                case .disconnctedMarker:
                                    Text("--- DISCONNECTED ---")
                                case  .reconnectedMarker:
                                    Text("--- RECONNECTED  ---")
                                }
                            }
                        }
                        .onAppear {
                            if self.viewModel.receivedMsg.count > 0 {
                                scrollView.scrollTo(self.viewModel.receivedMsg[self.viewModel.receivedMsg.endIndex - 1])
                            }
                        }
                    }
                }
                
                Spacer()
                HStack {
                    TextField("Say hi to \(city)", text: $viewModel.chatMsg)
                        .font(.system(size: 25.0))
                    
                    Button(action: {self.viewModel.sendToGroupChat()}) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 25.0))
                    }
                    .disabled(!self.viewModel.isConnected || !self.viewModel.joinedChat || self.viewModel.chatMsg.isEmpty)
                }
            }
            else {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
        }
        .onReceive(self.viewModel.$enteredForeground) { _ in
            self.viewModel.startUpdateLocation()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
