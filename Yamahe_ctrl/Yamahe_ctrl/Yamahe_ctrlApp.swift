import Cocoa

typealias ErrorDetails = (message: String, context: String)
class ErrorLogWindowController: NSWindowController {
    static let shared = ErrorLogWindowController()

    private var logTextView: NSTextView!

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
        window.title = "Error Log"
        super.init(window: window)

        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true

        logTextView = NSTextView(frame: scrollView.bounds)
        logTextView.isEditable = false
        logTextView.isSelectable = true

        scrollView.documentView = logTextView
        window.contentView?.addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func logError(_ details: ErrorDetails) {
        DispatchQueue.main.async {
            let logEntry = "\(Date()): \(details.message)\nContext: \(details.context)\n\n"
            self.logTextView.textStorage?.append(NSAttributedString(string: logEntry))
            self.logTextView.scrollToEndOfDocument(nil)

            if !self.window!.isVisible {
                self.showWindow(nil)
            }
        }
    }
}

class BlockAction: NSObject {
    private let action: (AnyObject?) -> Void

    init(action: @escaping (AnyObject?) -> Void) {
        self.action = action
    }

    @objc func performAction(_ sender: AnyObject?) {
        action(sender)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu!
    
    private var actions: [BlockAction] = []
    
    var pureDirectState: Bool = false
    var enhancerState: Bool = false
    var extraBassState: Bool = false
    var adaptiveDrcState: Bool = false
    
    private let errorLog = ErrorLogWindowController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.title = "🎵"

        statusMenu = NSMenu()
        statusItem?.menu = statusMenu

        fetchYamahaStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.updateMenu(with: status)
                case .failure(let error):
                    self.handleError(error, context: "Initial Yamaha status fetch")
                }
            }
        }

        statusItem?.menu?.delegate = self
    }
    
    func handleError(_ error: Error, context: String) {
        let errorMessage = "An error occurred: \(error.localizedDescription)"
        print(errorMessage)
        errorLog.logError((message: errorMessage, context: context))
    }

    func updateMenu(with status: YamahaStatus) {
        statusMenu.removeAllItems()
        
        // Helper pour créer un label
        func createLabelItem(text: String) -> NSMenuItem {
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            let item = NSMenuItem()
            item.view = label
            return item
        }
        
        // Helper pour créer un slider
        func createSliderItem(value: Double, minValue: Double, maxValue: Double, target: AnyObject, action: Selector) -> NSView {
            let container = NSStackView()
            container.orientation = .horizontal
            container.alignment = .centerY
            container.spacing = 8
            container.translatesAutoresizingMaskIntoConstraints = false

            let slider = NSSlider(value: value, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.widthAnchor.constraint(equalToConstant: 120).isActive = true

            let label = NSTextField(labelWithString: "\(Int(value))")
            label.alignment = .center
            label.isEditable = false
            label.isBezeled = false
            label.drawsBackground = false
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalToConstant: 40).isActive = true

            let blockAction = BlockAction { sender in
                if let slider = sender as? NSSlider {
                    label.stringValue = "\(Int(slider.doubleValue))"
                }
                let _ = target.perform(action, with: sender)
            }

            actions.append(blockAction)

            slider.target = blockAction
            slider.action = #selector(BlockAction.performAction(_:))

            container.addArrangedSubview(slider)
            container.addArrangedSubview(label)

            container.widthAnchor.constraint(equalToConstant: 180).isActive = true
            container.heightAnchor.constraint(equalToConstant: 30).isActive = true

            return container
        }
        
    
        
        // Volume
        statusMenu.addItem(createLabelItem(text: "Volume: \(status.actual_volume.value)"))
        let volumeSliderItem = NSMenuItem()
        volumeSliderItem.view = createSliderItem(value: Double(status.volume), minValue: 0, maxValue: Double(status.max_volume), target: self, action: #selector(volumeChanged(_:)))
        statusMenu.addItem(volumeSliderItem)
        
        
        // Bass
        statusMenu.addItem(createLabelItem(text: "Bass Vol: \(status.subwoofer_volume)"))
        let bassSliderItem = NSMenuItem()
        bassSliderItem.view = createSliderItem(value: Double(status.subwoofer_volume), minValue: -12, maxValue: 12, target: self, action: #selector(bassChanged(_:)))
        statusMenu.addItem(bassSliderItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Tone
        statusMenu.addItem(createLabelItem(text: "Bass: \(status.tone_control.bass) / Treble: \(status.tone_control.treble)"))
        let toneSliderItem = NSMenuItem()
        toneSliderItem.view = createSliderItem(value: Double(status.tone_control.bass), minValue: -12, maxValue: 12, target: self, action: #selector(toneControlChanged(_:)))
        statusMenu.addItem(toneSliderItem)
        
        let tone1SliderItem = NSMenuItem()
        tone1SliderItem.view = createSliderItem(value: Double(status.tone_control.treble), minValue: -12, maxValue: 12, target: self, action: #selector(toneControlChanged(_:)))
        statusMenu.addItem(tone1SliderItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        statusMenu.addItem(createLabelItem(text: "Dial: \(status.dialogue_level)"))
        let dialSliderItem = NSMenuItem()
        dialSliderItem.view = createSliderItem(value: Double(status.dialogue_level), minValue: 0, maxValue: 3, target: self, action: #selector(dialogueLevelChanged(_:)))
        statusMenu.addItem(dialSliderItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Toggles
        pureDirectState = status.pure_direct
        enhancerState = status.enhancer
        extraBassState = status.extra_bass
        adaptiveDrcState = status.adaptive_drc
        
        addToggleMenuItem(title: "Pure Direct", state: pureDirectState, action: #selector(togglePureDirect))
        addToggleMenuItem(title: "Enhancer", state: enhancerState, action: #selector(toggleEnhancer))
        addToggleMenuItem(title: "Extra Bass", state: extraBassState, action: #selector(toggleExtraBass))
        addToggleMenuItem(title: "Adaptive DRC", state: adaptiveDrcState, action: #selector(toggleAdaptiveDrc))
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Static menu items
        statusMenu.addItem(NSMenuItem(title: "Show Settings", action: nil, keyEquivalent: ""))
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

    }

    func addToggleMenuItem(title: String, state: Bool, action: Selector) {
        let toggleItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        toggleItem.state = state ? .on : .off
        toggleItem.target = self
        statusMenu.addItem(toggleItem)
    }
    
    @objc func dialogueLevelChanged(_ sender: NSSlider) {
        let newLevel = Int(sender.doubleValue)
        setDialogueLevel(to: newLevel) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Dialogue level set to \(newLevel)")
                case .failure(let error):
                    self.handleError(error, context: "Failed to set dialogue level")
                }
            }
        }
    }

    @objc func toneControlChanged(_ sender: NSSlider) {
        let bassSlider = statusMenu.item(at: 6)?.view as? NSSlider
        let bass = Int(bassSlider?.doubleValue ?? 0)

        let trebleSlider = statusMenu.item(at: 7)?.view as? NSSlider
        let treble = Int(trebleSlider?.doubleValue ?? 0)


        setToneControl(bass: bass, treble: treble) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Tone control updated to Bass: \(bass), Treble: \(treble)")
                case .failure(let error):
                    self.handleError(error, context: "Failed to update tone control")
                }
            }
        }
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        let newVolume = Int(sender.doubleValue)
        setVolume(to: newVolume) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Volume set to \(newVolume)")
                case .failure(let error):
                    self.handleError(error, context: "Failed to set volume")
                }
            }
        }
    }

    @objc func bassChanged(_ sender: NSSlider) {
        let newBass = Int(sender.doubleValue)
        setBass(to: newBass) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Bass set to \(newBass)")
                case .failure(let error):
                    self.handleError(error, context: "Failed to set bass")
                }
            }
        }
    }

    @objc func togglePureDirect() {
        pureDirectState.toggle()
        toggleSetting(endpoint: "setPureDirect", state: pureDirectState) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Toggled Pure Direct to \(self.pureDirectState ? "on" : "off")")
                case .failure(let error):
                    self.handleError(error, context: "Failed to toggle Pure Direct")
                }
            }
        }
    }

    @objc func toggleEnhancer() {
        enhancerState.toggle()
        toggleSetting(endpoint: "setEnhancer", state: enhancerState) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Toggled Enhancer to \(self.enhancerState ? "on" : "off")")
                case .failure(let error):
                    self.handleError(error, context: "Failed to toggle Enhancer")
                }
            }
        }
    }

    @objc func toggleExtraBass() {
        extraBassState.toggle()
        toggleSetting(endpoint: "setExtraBass", state: extraBassState) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Toggled Extra Bass to \(self.extraBassState ? "on" : "off")")
                case .failure(let error):
                    self.handleError(error, context: "Failed to toggle Extra Bass")
                }
            }
        }
    }

    @objc func toggleAdaptiveDrc() {
        adaptiveDrcState.toggle()
        toggleSetting(endpoint: "setAdaptiveDrc", state: adaptiveDrcState) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Toggled Adaptive DRC to \(self.adaptiveDrcState ? "on" : "off")")
                case .failure(let error):
                    self.handleError(error, context: "Failed to toggle Adaptive DRC")
                }
            }
        }
    }
    
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func setDialogueLevel(to level: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        performRequest(endpoint: "setDialogueLevel", parameters: ["value": "\(level)"], completion: completion)
    }

    func setToneControl(bass: Int, treble: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        performRequest(endpoint: "setToneControl", parameters: ["mode": "manual", "bass": "\(bass)", "treble": "\(treble)"], completion: completion)
    }

    func setVolume(to volume: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        performRequest(endpoint: "setVolume", parameters: ["volume": "\(volume)"], completion: completion)
    }

    func setBass(to bass: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        performRequest(endpoint: "setSubwooferVolume", parameters: ["volume": "\(bass)"], completion: completion)
    }

    func toggleSetting(endpoint: String, state: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        performRequest(endpoint: endpoint, parameters: ["enable": state ? "true" : "false"], completion: completion)
    }
    
    
    func performRequest(endpoint: String, parameters: [String: String], completion: @escaping (Result<Void, Error>) -> Void) {
        // Construction de l'URL avec les paramètres
        var urlComponents = URLComponents(string: "http://192.168.1.86/YamahaExtendedControl/v1/main/\(endpoint)")
        urlComponents?.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        guard let url = urlComponents?.url else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            completion(.success(()))
        }
        task.resume()
    }

    func menuWillOpen(_ menu: NSMenu) {
        fetchYamahaStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.updateMenu(with: status)
                case .failure(let error):
                    self.handleError(error, context: "Menu refresh")
                }
            }
        }
    }

    func fetchYamahaStatus(completion: @escaping (Result<YamahaStatus, Error>) -> Void) {
        guard let url = URL(string: "http://192.168.1.86/YamahaExtendedControl/v1/main/getStatus") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "No data received", code: -1, userInfo: nil)))
                return
            }

            do {
                let status = try JSONDecoder().decode(YamahaStatus.self, from: data)
                completion(.success(status))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }
    
    struct ActualVolume: Codable{
        let value: Float
    }
    
    struct ToneControl: Codable{
        let mode: String
        let bass: Int
        let treble: Int
    }
    
    struct YamahaStatus: Codable {
        let volume: Int
        let max_volume: Int
        let subwoofer_volume: Int
        let pure_direct: Bool
        let enhancer: Bool
        let adaptive_drc: Bool
        let extra_bass: Bool
        let actual_volume: ActualVolume
        let dialogue_level: Int
        let tone_control: ToneControl
    }
}
