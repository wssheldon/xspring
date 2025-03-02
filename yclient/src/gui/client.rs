use crate::models::{Beacon, BeaconSession, Command, NewCommand, Tab, View};
use crate::utils::formatter::format_ls_output;
use eframe::egui;
use egui_dock::DockState;
use reqwest::blocking::Client as ReqwestClient;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

/// Main GUI client for the application
pub struct GuiClient {
    pub beacons: Arc<Mutex<Vec<Beacon>>>,
    pub server_url: String,
    pub reqwest_client: ReqwestClient,

    // Add active sessions
    pub active_sessions: Vec<BeaconSession>,
    pub current_view: View,

    // Add dock state for the tabbed interface
    pub dock_state: DockState<Tab>,
}

impl GuiClient {
    /// Create a new GUI client
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        // Customize fonts if needed
        let fonts = egui::FontDefinitions::default();
        cc.egui_ctx.set_fonts(fonts);

        // Initialize dock state
        let dock_state = DockState::new(Vec::new());

        let client = Self {
            beacons: Arc::new(Mutex::new(Vec::new())),
            server_url: String::from("http://127.0.0.1:4444"),
            reqwest_client: ReqwestClient::new(),

            // Initialize with empty sessions
            active_sessions: Vec::new(),
            current_view: View::Dashboard,

            // Add dock state
            dock_state,
        };

        // Start beacon polling thread
        let beacons = client.beacons.clone();
        let server_url = client.server_url.clone();
        thread::spawn(move || {
            let poll_client = ReqwestClient::new();
            loop {
                if let Ok(response) = poll_client.get(format!("{}/beacons", server_url)).send() {
                    if response.status().is_success() {
                        if let Ok(new_beacons) = response.json::<Vec<Beacon>>() {
                            if let Ok(mut beacons_lock) = beacons.lock() {
                                *beacons_lock = new_beacons;
                            }
                        }
                    }
                }
                thread::sleep(Duration::from_secs(5));
            }
        });

        client
    }

    /// Find or create a session for a beacon
    pub fn find_or_create_session(&mut self, beacon_id: &str) -> usize {
        if let Some(idx) = self
            .active_sessions
            .iter()
            .position(|s| s.beacon_id == beacon_id)
        {
            idx
        } else {
            let new_session = BeaconSession::new(beacon_id.to_string());
            self.active_sessions.push(new_session);
            self.active_sessions.len() - 1
        }
    }

    /// Render a beacon session with command history and input
    pub fn render_beacon_session(&mut self, ui: &mut egui::Ui, session_idx: usize) {
        if session_idx >= self.active_sessions.len() {
            return;
        }

        let beacon_id = self.active_sessions[session_idx].beacon_id.clone();

        egui::SidePanel::left("command_panel")
            .resizable(true)
            .min_width(300.0)
            .default_width(400.0)
            .show_inside(ui, |ui| {
                // Command history
                egui::ScrollArea::vertical()
                    .id_salt("command_history")
                    .stick_to_bottom(true)
                    .show(ui, |ui| {
                        self.render_command_history(ui, session_idx);
                    });

                // Command input
                ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                    ui.horizontal(|ui| {
                        let session = &mut self.active_sessions[session_idx];
                        let text_edit = ui.add_sized(
                            ui.available_size() - egui::vec2(60.0, 0.0),
                            egui::TextEdit::singleline(&mut session.command_input)
                                .hint_text("Enter command...")
                                .id_salt("command_input"),
                        );

                        if (text_edit.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)))
                            || ui.button("Send").clicked()
                        {
                            if !session.command_input.is_empty() {
                                self.send_command(&beacon_id);
                            }
                        }
                    });
                });
            });

        // Command results panel (central)
        egui::CentralPanel::default().show_inside(ui, |ui| {
            ui.heading("Command Results");
            egui::ScrollArea::vertical()
                .id_salt("command_results")
                .show(ui, |ui| {
                    self.render_command_results(ui, session_idx);
                });
        });
    }

    /// Render a navigation button
    pub fn render_nav_button(&mut self, ui: &mut egui::Ui, icon: char, view: View, tooltip: &str) {
        let is_selected = self.current_view == view;

        let btn = egui::Button::new(egui::RichText::new(icon.to_string()).size(24.0).color(
            if is_selected {
                ui.visuals().selection.stroke.color
            } else {
                ui.visuals().text_color()
            },
        ))
        .min_size(egui::vec2(40.0, 40.0));

        let response = ui.add(btn);

        if response.clicked() {
            self.current_view = view;
        }

        response.on_hover_text(tooltip);
    }

    /// Send a command to a beacon
    pub fn send_command(&mut self, beacon_id: &str) {
        // Get the active session index
        let session_idx = if let Some(idx) = self
            .active_sessions
            .iter()
            .position(|s| s.beacon_id == beacon_id)
        {
            idx
        } else {
            return;
        };

        // Get a reference to the session
        let session = &mut self.active_sessions[session_idx];

        let new_command = NewCommand {
            beacon_id: beacon_id.to_string(),
            command: session.command_input.clone(),
        };

        // Add command to history
        session
            .command_output
            .push(format!("> {}", session.command_input));

        // Send command using reqwest
        match self
            .reqwest_client
            .post(format!("{}/command/new", self.server_url))
            .json(&new_command)
            .send()
        {
            Ok(response) => match response.json::<Command>() {
                Ok(cmd) => {
                    session
                        .command_output
                        .push(format!("Command scheduled (ID: {})", cmd.id));
                }
                Err(e) => {
                    session
                        .command_output
                        .push(format!("Failed to parse response: {}", e));
                }
            },
            Err(e) => {
                session
                    .command_output
                    .push(format!("Failed to send command: {}", e));
            }
        }

        session.command_input.clear();
    }

    /// Render command history for a session
    pub fn render_command_history(&mut self, ui: &mut egui::Ui, session_idx: usize) {
        if session_idx < self.active_sessions.len() {
            let session = &self.active_sessions[session_idx];
            for output in &session.command_output {
                ui.label(output);
            }
        }
    }

    /// Render command results for a session
    pub fn render_command_results(&mut self, ui: &mut egui::Ui, session_idx: usize) {
        if session_idx >= self.active_sessions.len() {
            return;
        }

        let session = &self.active_sessions[session_idx];
        let beacon_id = &session.beacon_id;

        if let Ok(commands) = self
            .reqwest_client
            .get(format!("{}/command/list/{}", self.server_url, beacon_id))
            .send()
        {
            if let Ok(commands) = commands.json::<Vec<Command>>() {
                for cmd in commands.iter().rev() {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(format!("ID: {}", cmd.id));
                            ui.label(format!("Status: {}", cmd.status));
                            ui.label(format!("Created: {}", cmd.created_at));
                        });
                        ui.label(format!("Command: {}", cmd.command));
                        if let Some(result) = &cmd.result {
                            ui.separator();
                            ui.label("Output:");

                            // Apply special formatting for ls command
                            if cmd.command.trim() == "ls" {
                                let formatted_output = format_ls_output(result);
                                ui.add(
                                    egui::TextEdit::multiline(&mut formatted_output.as_str())
                                        .desired_width(f32::INFINITY)
                                        .font(egui::TextStyle::Monospace),
                                );
                            } else {
                                ui.label(result);
                            }
                        }
                        if let Some(completed_at) = &cmd.completed_at {
                            ui.small(format!("Completed: {}", completed_at));
                        }
                    });
                    ui.add_space(4.0);
                }
            }
        }
    }
}

impl eframe::App for GuiClient {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Check if we have a beacon to open - hold the value outside to avoid borrowing issues
        let mut beacon_to_open: Option<String> = None;

        ctx.data_mut(|data| {
            // Remove returns (), so we need to get the value before removing
            if let Some(beacon_id) = data.get_temp::<String>(egui::Id::new("selected_beacon")) {
                beacon_to_open = Some(beacon_id.clone());
                data.remove::<String>(egui::Id::new("selected_beacon"));
            }
        });

        // Now we can safely use beacon_to_open without borrowing issues
        if let Some(beacon_id) = beacon_to_open {
            self.open_beacon_tab(&beacon_id);
        }

        // Add the left navigation panel
        egui::SidePanel::left("nav_panel")
            .max_width(50.0)
            .show(ctx, |ui| {
                ui.vertical_centered(|ui| {
                    ui.add_space(10.0);
                    self.render_nav_button(ui, '📊', View::Dashboard, "Dashboard");
                    self.render_nav_button(ui, '💻', View::Beacons, "Beacons");
                    self.render_nav_button(ui, '📡', View::Listeners, "Listeners");
                    ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                        self.render_nav_button(ui, '⚙', View::Settings, "Settings");
                    });
                });
            });

        // Main content area
        egui::CentralPanel::default().show(ctx, |ui| match self.current_view {
            View::Dashboard => {
                self.render_dashboard_view(ui);
            }
            View::Beacons => {
                self.render_beacons_view(ui);
            }
            View::Listeners => {
                self.render_listeners_view(ui);
            }
            View::Settings => {
                self.render_settings_view(ui);
            }
        });

        // Request repaint
        ctx.request_repaint_after(Duration::from_secs(1));
    }
}
