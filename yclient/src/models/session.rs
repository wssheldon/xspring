/// Different views available in the application
#[derive(Debug, PartialEq)]
pub enum View {
    Dashboard,
    Beacons,
    Listeners,
    Settings,
}

/// Represents a session with a beacon
pub struct BeaconSession {
    pub beacon_id: String,
    pub command_input: String,
    pub command_output: Vec<String>,
    pub is_selected: bool,
}

impl BeaconSession {
    pub fn new(beacon_id: String) -> Self {
        Self {
            beacon_id,
            command_input: String::new(),
            command_output: Vec::new(),
            is_selected: false,
        }
    }
}

/// Represents a tab in the dock interface
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Tab {
    Beacon(String), // String is the beacon ID
}
