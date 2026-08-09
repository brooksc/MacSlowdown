import Foundation

/// What a well-known system process is *for*, in words a person can act on.
///
/// A protected process is nameable but not measurable, so its name is the only
/// thing the interface can give the user. "backupd" is a name; "Time Machine" is
/// an answer. This is the difference between a list the user can reason about and
/// a list they have to look up elsewhere.
///
/// **This is data, not logic.** The tables below are the whole mechanism; the
/// lookup is a dictionary hit and two prefix scans. A `switch` would have hidden
/// the coverage question — how much of the unmeasurable set can we actually
/// describe? — inside control flow where it cannot be counted. `coverage(of:)`
/// answers it directly, and is what the recorded proportion in TASK-65.13 comes
/// from.
///
/// Every entry describes a documented, publicly observable role. Nothing here
/// claims a process is *doing* anything at a moment in time; that would be a
/// measurement, and for these processes we have none (FR-002, FR-038).
enum SystemProcessDescriptors {
    /// `p_comm` → what the process is for.
    ///
    /// Keyed on the kernel's command name because that is the one field available
    /// for every process regardless of ownership. Note that `p_comm` is truncated
    /// to 16 bytes, so longer keys here are also matched against their truncation
    /// — see `meaning(forCommand:)`.
    static let byCommand: [String: String] = [
        // Kernel and service management
        "kernel_task": "Kernel",
        "launchd": "Service manager",
        "smd": "Service management",
        "runningboardd": "Process lifecycle",
        "xpcroleaccountd": "Background service accounts",
        "UserEventAgent": "System event agent",
        "KernelEventAgent": "Kernel event agent",
        "kernelmanagerd": "Kernel extensions",
        "corekdld": "Kernel extensions",
        "cron": "Scheduled jobs",
        "oahd": "Rosetta translation",

        // Windowing, display, graphics
        "WindowServer": "Window server",
        "corebrightnessd": "Display brightness",
        "MTLCompilerService": "GPU shader compilation",
        "CVMServer": "GPU shader compilation",

        // Spotlight
        "mds": "Spotlight indexing",
        "mds_stores": "Spotlight system indexer",
        "mdworker": "Spotlight worker",
        "mdworker_shared": "Spotlight worker",
        "mdsync": "Spotlight index sync",
        "mdbulkimport": "Spotlight bulk import",

        // Backup, versions, file events
        "backupd": "Time Machine",
        "backupd-helper": "Time Machine",
        "revisiond": "Document versions",
        "fseventsd": "File change tracking",
        "filecoordinationd": "File coordination",
        "deleted_helper": "Purgeable space management",

        // Storage and file systems
        "diskarbitrationd": "Disk mounting",
        "apfsd": "APFS file system",
        "fskitd": "File systems",
        "storagekitd": "Disk management",
        "automountd": "Network volume mounting",
        "autofsd": "Network volume mounting",
        "diskimagesiod": "Disk images",
        "simdiskimaged": "Disk images",
        "containermanagerd": "App containers",
        "containermanagerd_system": "App containers",

        // Audio
        "coreaudiod": "Core Audio",
        "audiomxd": "Audio routing",
        "usbaudiod": "USB audio",
        "systemsoundserverd": "System sounds",
        "audioanalyticsd": "Audio diagnostics",

        // Camera
        "cameracaptured": "Camera",
        "appleh13camerad": "Camera",
        "UVCAssistant": "USB camera",
        "VDCAssistant": "Camera",

        // Networking
        "configd": "Network configuration",
        "mDNSResponder": "Bonjour and DNS",
        "mDNSResponderHelper": "Bonjour and DNS",
        "netbiosd": "Windows file sharing",
        "nsurlsessiond": "Background downloads",
        "nehelper": "Network extensions",
        "nesessionmanager": "Network extensions",
        "socketfilterfw": "Application firewall",
        "usbmuxd": "USB device connections",
        "remoted": "Remote device connections",
        "airportd": "Wi-Fi",
        "wifivelocityd": "Wi-Fi diagnostics",
        "wifianalyticsd": "Wi-Fi diagnostics",
        "wifip2pd": "Wi-Fi peer-to-peer",
        "WirelessRadioManagerd": "Wireless radios",
        "bluetoothd": "Bluetooth",
        "IOUserBluetoothSerialDriver": "Bluetooth driver",
        "nfcd": "NFC",
        "sharingd": "Sharing and Handoff",

        // Security, trust, privacy
        "securityd": "Keychain and security",
        "securityd_system": "Keychain and security",
        "trustd": "Certificate trust",
        "authd": "Authorisation",
        "coreauthd": "Authentication",
        "biometrickitd": "Touch ID",
        "keybagd": "Encryption keys",
        "ctkd": "Smart cards",
        "seputil": "Secure Enclave",
        "opendirectoryd": "Directory services",
        "syspolicyd": "Gatekeeper policy",
        "amfid": "Code signature checking",
        "taskgated": "Code signature checking",
        "sandboxd": "App Sandbox",
        "secinitd": "App Sandbox setup",
        "tccd": "Privacy permissions",
        "xprotectd": "Malware protection (XProtect)",
        "XprotectService": "Malware protection (XProtect)",
        "XProtectBridgeService": "Malware protection (XProtect)",
        "XProtectUpdateService": "Malware protection updates",
        "mobileactivationd": "Device activation",
        "online-auth-agent": "Online authentication",

        // Notifications, preferences, launch services
        "distnoted": "Distributed notifications",
        "notifyd": "Notification routing",
        "cfprefsd": "Preferences service",
        "apsd": "Apple push notifications",
        "lsd": "Launch Services",
        "launchservicesd": "Launch Services",
        "iconservicesd": "Icon services",
        "coreservicesd": "Core Services",
        "appleeventsd": "Apple Events",
        "usermanagerd": "User sessions",
        "logind": "User sessions",

        // Power, thermal, sensors
        "powerd": "Power management",
        "powerdatad": "Power measurement",
        "powerexperienced": "Power management",
        "PowerUIAgent": "Battery interface",
        "thermalmonitord": "Thermal monitoring",
        "PerfPowerServices": "Performance and power metrics",
        "IOMFB_bics_daemon": "Display backlight",
        "liquiddetectiond": "Liquid detection",
        "accessoryaccessd": "Accessory access",

        // Logging, diagnostics, analytics
        "logd": "System logging",
        "logd_helper": "System logging",
        "syslogd": "System logging",
        "analyticsd": "Usage analytics",
        "SubmitDiagInfo": "Diagnostic report submission",
        "osanalyticshelper": "Diagnostic reports",
        "ReportCrash": "Crash reporting",
        "CrashReporterSupportHelper": "Crash reporting",
        "spindump": "Unresponsiveness reports",
        "sysdiagnosed": "System diagnostics",
        "diagnosticd": "Diagnostics",
        "symptomsd": "Network condition monitoring",
        "symptomsd-diag": "Network condition monitoring",
        "tailspind": "Performance trace capture",
        "watchdogd": "System watchdog",
        "sysmond": "System monitoring",
        "systemstats": "System statistics",
        "systemstatusd": "System status",
        "coresymbolicationd": "Crash symbolication",
        "rtcreportingd": "Real-time diagnostics",

        // Software update and assets
        "softwareupdated": "Software Update",
        "suhelperd": "Software Update",
        "installd": "App installation",
        "system_installd": "System installation",
        "mobileassetd": "System asset downloads",
        "assetsubscriptiond": "System asset downloads",
        "uarpd": "Firmware updates",
        "uarpassetmanagerd": "Firmware updates",
        "AssetCache": "Content caching",
        "AssetCacheLocatorService": "Content caching",
        "AssetCacheTetheratorService": "Content caching",

        // iCloud and continuity
        "cloudd": "iCloud",
        "cloudtelemetryd": "iCloud diagnostics",
        "searchpartyd": "Find My",
        "findmydeviced": "Find My",
        "findmybeaconingd": "Find My",
        "nearbyd": "Nearby devices",
        "locationd": "Location Services",
        "com.apple.geod": "Maps data",
        "AirPlayXPCHelper": "AirPlay",
        "mediaremoted": "Media playback controls",

        // Media rights
        "fairplayd": "Media playback rights",
        "fpassetmanagerd": "Media playback rights",
        "lskdd": "Media playback rights",

        // On-device intelligence
        "aned": "Neural Engine",
        "aneuserd": "Neural Engine",
        "modelmanagerd": "On-device models",
        "modelcatalogd": "On-device models",
        "corespeechd_system": "Speech recognition",
        "PCCAgentClientExtension": "Private Cloud Compute",

        // Scheduling and context
        "dasd": "Background task scheduling",
        "coreduetd": "Activity prediction",
        "ospredictiond": "Activity prediction",
        "contextstored": "System context",
        "ContextService": "System context",
        "ecosystemd": "Device ecosystem",
        "countryd": "Regional settings",
        "eligibilityd": "Feature availability",
        "backgroundtaskmanagementd": "Login and background items",
        "mmaintenanced": "Scheduled maintenance",
        "corerepaird": "System repair",
        "biomed": "Health and sensor data",
        "adid": "Advertising attribution",
        "triald_system": "Apple feature experiments",
        "TrialArchivingService": "Apple feature experiments",
        "gamecontrollerd": "Game controllers",
        "gamepolicyd": "Game mode",
        "timed": "Network time",
        "clocksyncd": "Clock synchronisation",
        "tzd": "Time zone",
        "ioupsd": "Uninterruptible power supply",
        "automationmode-writer": "Automation mode",
        "AppleDeviceQueryService": "Device information",
        "AppIntentsLiveEntityService": "App Intents",
        "com.apple.CodeSigningHelper": "Code signing",
    ]

    /// Whole families of generated command names, matched on a prefix.
    ///
    /// Ordered: the first match wins, so put the more specific prefix first.
    static let byPrefix: [(prefix: String, meaning: String)] = [
        ("com.apple.DriverKit", "Device driver"),
        ("com.apple.AppleUserHIDDrivers", "Input device driver"),
        ("com.apple.cmio", "Camera"),
        ("com.apple.MobileSoftwareUpdate", "Software Update"),
        ("com.apple.dt.instruments", "Developer tools"),
        ("com.apple.AmbientDisplay", "Ambient light sensing"),
        ("UARPAssetManagerService", "Firmware updates"),
        ("TGOnDeviceInference", "On-device models"),
        ("PrivateMLClientInference", "On-device models"),
        ("GenerativeExperiences", "On-device models"),
        ("mdworker", "Spotlight worker"),
        ("com.apple.WebKit", "Web content"),
    ]

    /// What this process is for, or nil.
    ///
    /// Nil is a real answer and the common one: most of the process table has no
    /// published description, and inventing one would be exactly the fabricated
    /// claim FR-002 forbids.
    static func meaning(forCommand command: String) -> String? {
        if let exact = byCommand[command] { return exact }
        // `p_comm` is 16 bytes, so a longer name arrives truncated and would never
        // match its own key.
        if let truncated = truncatedIndex[command] { return truncated }
        return byPrefix.first { matches(prefix: $0.prefix, command: command) }?.meaning
    }

    /// A prefix rule matches a command that starts with it — or, when the command
    /// arrived truncated, a command that the rule itself starts with. Several of
    /// these families (`com.apple.DriverKit…`) have reverse-DNS names longer than
    /// `p_comm`, so without this the rule could never fire on real data.
    private static func matches(prefix: String, command: String) -> Bool {
        command.hasPrefix(prefix)
            || (command.utf8.count >= 15 && prefix.hasPrefix(command))
    }

    /// How much of a set of commands this table can describe.
    ///
    /// The point of measuring it: a descriptor table that covers 5% of what the
    /// user sees is decoration. Counted over processes rather than distinct names,
    /// because that is what appears on screen — 22 copies of `distnoted` are 22
    /// rows a user has to make sense of.
    static func coverage(of commands: [String]) -> (described: Int, total: Int) {
        (commands.count { meaning(forCommand: $0) != nil }, commands.count)
    }

    /// Truncations of the longer keys, so a 16-byte `p_comm` still resolves.
    ///
    /// A truncation shared by two entries with different meanings is dropped
    /// rather than resolved arbitrarily: guessing which of two processes we are
    /// looking at would put a wrong description on a row, which is worse than no
    /// description.
    private static let truncatedIndex: [String: String] = {
        var index: [String: String] = [:]
        var ambiguous: Set<String> = []
        for (command, meaning) in byCommand where command.utf8.count > 15 {
            for length in [15, 16] where command.count >= length {
                let key = String(command.prefix(length))
                if let existing = index[key], existing != meaning {
                    ambiguous.insert(key)
                } else {
                    index[key] = meaning
                }
            }
        }
        for key in ambiguous { index.removeValue(forKey: key) }
        return index
    }()
}
