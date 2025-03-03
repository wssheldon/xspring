use crate::models::{Beacon, BeaconSession, Command, NewCommand, Tab, View};
use crate::utils::formatter::format_ls_output;
use eframe::egui;
use egui_dock::DockState;
use egui_phosphor::regular;
use reqwest::blocking::Client as ReqwestClient;
use serde_json;
use std::collections::HashMap;
use std::collections::HashSet;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use std::time::Instant;

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

    // Add state for delete confirmation modal
    pub delete_modal_open: bool,
    pub beacon_to_delete: Option<String>,

    // Add state for beacon panel sizing
    pub beacon_panel_height: f32,

    // Add last poll time for command results
    pub last_poll_time: HashMap<String, Instant>,
    pub poll_interval_ms: u64, // Polling interval in milliseconds
    pub pending_command_ids: HashMap<String, Vec<i64>>, // Track pending commands by beacon ID
    pub processed_command_ids: HashSet<String>, // Track already processed command IDs
}

impl GuiClient {
    /// Create a new GUI client
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        // Initialize fonts with Phosphor icons
        let mut fonts = egui::FontDefinitions::default();
        egui_phosphor::add_to_fonts(&mut fonts, egui_phosphor::Variant::Regular);
        cc.egui_ctx.set_fonts(fonts);

        // Initialize dock state
        let dock_state = DockState::new(Vec::new());

        let client = Self {
            beacons: Arc::new(Mutex::new(Vec::new())),
            server_url: "https://localhost:4444".to_string(),
            reqwest_client: ReqwestClient::builder()
                .danger_accept_invalid_certs(true)
                .build()
                .unwrap(),
            active_sessions: Vec::new(),
            current_view: View::Dashboard,
            dock_state,
            delete_modal_open: false,
            beacon_to_delete: None,
            beacon_panel_height: 300.0,
            last_poll_time: HashMap::new(),
            poll_interval_ms: 150, // Poll every 150ms instead of 1000ms
            pending_command_ids: HashMap::new(),
            processed_command_ids: HashSet::new(),
        };

        // Start beacon polling thread
        let beacons = client.beacons.clone();
        let server_url = client.server_url.clone();
        thread::spawn(move || {
            let poll_client = ReqwestClient::builder()
                .danger_accept_invalid_certs(true)
                .build()
                .unwrap_or_default();
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

        // Use TopBottomPanel for the terminal to ensure it's flush with edges
        egui::TopBottomPanel::bottom("terminal_input")
            .exact_height(ui.available_height())
            .frame(
                egui::Frame::none()
                    .fill(egui::Color32::BLACK)
                    .inner_margin(0.0)
                    .outer_margin(0.0),
            )
            .show_inside(ui, |ui| {
                // Set up layout for terminal: command history (scrollable) at top, input at bottom
                ui.visuals_mut().override_text_color = Some(egui::Color32::WHITE);
                ui.set_min_height(ui.available_height());

                // Use vertical layout to ensure command input stays at bottom
                ui.vertical(|ui| {
                    // Use a ScrollArea for the command history to enable scrolling
                    let available_height = ui.available_height() - 32.0; // Increased space for input to prevent border cutoff
                    egui::ScrollArea::vertical()
                        .auto_shrink([false; 2])
                        .stick_to_bottom(true)
                        .max_height(available_height)
                        .show(ui, |ui| {
                            // Render command history inside the scrollable area
                            self.render_command_history(ui, session_idx);
                        });

                    // Add a small space before the input area
                    ui.add_space(2.0);

                    // Command input at the bottom - more compact
                    ui.horizontal(|ui| {
                        // Add small left margin
                        ui.add_space(8.0);

                        // Command input with proper right margin for send button
                        let text_edit = egui::TextEdit::singleline(
                            &mut self.active_sessions[session_idx].command_input,
                        )
                        .desired_width(ui.available_width() - 70.0) // Reserve space for send button
                        .hint_text(
                            egui::RichText::new("Enter command...")
                                .color(egui::Color32::from_gray(128)),
                        )
                        .margin(egui::vec2(4.0, 4.0))
                        .font(egui::FontId::monospace(14.0))
                        .text_color(egui::Color32::WHITE);

                        let response = ui.add(text_edit);
                        let mut should_send =
                            response.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));

                        // Add small space between input and button
                        ui.add_space(8.0);

                        // Add send button
                        let send_btn = ui.add_sized(
                            [50.0, 24.0],
                            egui::Button::new(
                                egui::RichText::new(regular::PAPER_PLANE_RIGHT)
                                    .size(16.0)
                                    .color(egui::Color32::WHITE),
                            ),
                        );

                        if send_btn.clicked() {
                            should_send = true;
                        }

                        // Add small right margin
                        ui.add_space(8.0);

                        if should_send {
                            self.send_command(&beacon_id);
                            ui.ctx().request_repaint();
                        }
                    });

                    // Add a small space after the input area
                    ui.add_space(2.0);
                });
            });
    }

    /// Render a navigation button
    pub fn render_nav_button(&mut self, ui: &mut egui::Ui, icon: &str, view: View, tooltip: &str) {
        let is_selected = self.current_view == view;

        let icon_text = egui::RichText::new(icon).size(24.0).color(if is_selected {
            ui.visuals().selection.stroke.color
        } else {
            ui.visuals().text_color()
        });

        let response = ui.add(egui::Label::new(icon_text).sense(egui::Sense::click()));

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

                    // Add this command ID to our pending commands list for immediate polling
                    let pending_for_beacon = self
                        .pending_command_ids
                        .entry(beacon_id.to_string())
                        .or_insert_with(Vec::new);
                    pending_for_beacon.push(cmd.id);

                    // Set last poll time to zero to trigger an immediate poll
                    self.last_poll_time
                        .insert(beacon_id.to_string(), Instant::now());
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

            // Use monospace font for all outputs
            let font_id = egui::FontId::monospace(12.0);

            // Set colors for different parts of the terminal
            let output_color = egui::Color32::WHITE;
            let error_color = egui::Color32::from_rgb(255, 100, 100); // red for errors
            let info_color = egui::Color32::from_gray(128); // gray for info messages

            // Create a vertical layout for command history with fixed width
            ui.vertical(|ui| {
                ui.set_min_width(ui.available_width());

                // Display command history and outputs
                for (i, output) in session.command_output.iter().enumerate() {
                    // Check if this is a command entry (starts with >)
                    if output.starts_with("> ") {
                        // Add some space before new commands (except the first one)
                        if i > 0 {
                            ui.add_space(8.0);
                        }

                        // Display command with prompt
                        ui.horizontal(|ui| {
                            ui.add(egui::Label::new(
                                egui::RichText::new("$ ")
                                    .color(output_color)
                                    .font(font_id.clone())
                                    .monospace(),
                            ));
                            ui.add(egui::Label::new(
                                egui::RichText::new(&output[2..]) // Skip the "> " prefix
                                    .color(output_color)
                                    .font(font_id.clone())
                                    .monospace(),
                            ));
                        });
                    } else if output.starts_with("Command scheduled")
                        || output.starts_with("Command result")
                    {
                        // Display command scheduling info
                        ui.add(egui::Label::new(
                            egui::RichText::new(output)
                                .color(info_color)
                                .font(font_id.clone())
                                .monospace(),
                        ));

                        // Add a small space after scheduling info
                        ui.add_space(2.0);
                    } else if output.is_empty() {
                        // Empty line for spacing
                        ui.add_space(4.0);
                    } else if output.starts_with("Failed") || output.contains("Error") {
                        // Error message
                        ui.add(egui::Label::new(
                            egui::RichText::new(output)
                                .color(error_color)
                                .font(font_id.clone())
                                .monospace(),
                        ));
                    } else {
                        // Regular output
                        let text = egui::RichText::new(output)
                            .color(output_color)
                            .font(font_id.clone())
                            .monospace();
                        ui.add(egui::Label::new(text));
                    }
                }

                // Add extra space at the end to ensure content can be scrolled up
                ui.add_space(4.0);
            });
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

    pub fn delete_beacon(&mut self, beacon_id: &str) -> Result<(), reqwest::Error> {
        let url = format!("{}/beacon/{}", self.server_url, beacon_id);

        // Send delete request to the server
        let response = self.reqwest_client.delete(&url).send()?;

        if response.status().is_success() {
            // If successful, remove the beacon from our local list
            if let Ok(mut beacons) = self.beacons.lock() {
                beacons.retain(|b| b.id != beacon_id);
            }

            // Also remove any active sessions for this beacon
            self.active_sessions.retain(|s| s.beacon_id != beacon_id);

            // For tabs, we would need to rebuild the dock state or handle this differently
            // since we don't have direct access to remove tabs
            // This implementation may vary depending on your egui_dock version and implementation
        }

        Ok(())
    }

    /// Poll for command results for all active sessions
    pub fn poll_command_results(&mut self) {
        // Process each active session
        for session in &mut self.active_sessions {
            // Get beacon ID
            let beacon_id = &session.beacon_id;

            // Check for commands with the "scheduled" status
            match self
                .reqwest_client
                .get(format!("{}/command/list/{}", self.server_url, beacon_id))
                .send()
            {
                Ok(response) => {
                    if let Ok(commands) = response.json::<Vec<Command>>() {
                        // Get pending commands for this beacon
                        let pending = self
                            .pending_command_ids
                            .entry(beacon_id.to_string())
                            .or_insert_with(Vec::new);

                        for cmd in commands {
                            // Skip if we've already processed this command
                            if self.processed_command_ids.contains(&cmd.id.to_string()) {
                                continue;
                            }

                            // If command is completed and not already processed
                            if cmd.status == "completed" {
                                // If the command has a result, add it to the output
                                if let Some(result) = &cmd.result {
                                    // Add a separator before the result for visual clarity
                                    session.command_output.push(String::new()); // empty line

                                    // Add the actual result with nice formatting
                                    let output = if result.starts_with('{') && result.ends_with('}')
                                    {
                                        // Try to parse and prettify JSON results
                                        match serde_json::from_str::<serde_json::Value>(result) {
                                            Ok(json) => match serde_json::to_string_pretty(&json) {
                                                Ok(pretty) => pretty,
                                                Err(_) => result.clone(),
                                            },
                                            Err(_) => result.clone(),
                                        }
                                    } else {
                                        result.clone()
                                    };

                                    session.command_output.push(output);

                                    // Mark this command as processed using a global set
                                    // instead of per-beacon set to ensure no duplication
                                    self.processed_command_ids.insert(cmd.id.to_string());

                                    // Remove this command from pending list if it exists
                                    if let Some(idx) = pending.iter().position(|&id| id == cmd.id) {
                                        pending.remove(idx);
                                    }
                                }
                            }
                        }
                    }
                }
                Err(_) => {
                    // Failed to fetch commands, but we'll silently ignore for now
                }
            }
        }
    }
}

impl eframe::App for GuiClient {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Poll for command results more frequently
        let now = std::time::Instant::now();

        // Check if it's time to poll
        let should_poll = true; // We'll always poll on update now - the per-beacon rate limiting happens inside poll_command_results

        if should_poll {
            self.poll_command_results();

            // Request a repaint immediately when polling to ensure UI updates quickly
            ctx.request_repaint();
        }

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

        // Check if a beacon was selected for deletion from the context menu
        ctx.data_mut(|data| {
            if let Some(beacon_id) = data.get_temp::<String>(egui::Id::new("beacon_to_delete")) {
                // Clear the data as we're handling it now
                data.remove::<String>(egui::Id::new("beacon_to_delete"));

                // Set up the deletion modal
                self.delete_modal_open = true;
                self.beacon_to_delete = Some(beacon_id);
            }
        });

        // Add the left navigation panel
        egui::SidePanel::left("nav_panel")
            .max_width(50.0)
            .show(ctx, |ui| {
                ui.vertical_centered(|ui| {
                    ui.add_space(10.0);
                    self.render_nav_button(ui, regular::CHART_LINE, View::Dashboard, "Dashboard");
                    ui.add_space(8.0);
                    self.render_nav_button(ui, regular::DESKTOP_TOWER, View::Beacons, "Beacons");
                    ui.add_space(8.0);
                    self.render_nav_button(ui, regular::BROADCAST, View::Listeners, "Listeners");
                    ui.with_layout(egui::Layout::bottom_up(egui::Align::Center), |ui| {
                        ui.add_space(10.0); // Space below settings button
                        self.render_nav_button(ui, regular::GEAR_SIX, View::Settings, "Settings");
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

        // Render the delete confirmation modal if open
        if self.delete_modal_open {
            let mut should_close = false;
            let mut should_delete = false;
            let beacon_id_to_delete = self.beacon_to_delete.clone();

            egui::Modal::new(egui::Id::new("delete_beacon_modal")).show(ctx, |ui| {
                ui.set_width(300.0);
                ui.heading("Delete Beacon");

                if let Some(beacon_id) = &beacon_id_to_delete {
                    ui.label(format!(
                        "Are you sure you want to delete beacon '{}'?",
                        beacon_id
                    ));
                    ui.label("This action cannot be undone.");

                    ui.add_space(16.0);

                    ui.horizontal(|ui| {
                        if ui.button("Cancel").clicked() {
                            should_close = true;
                        }

                        let delete_btn = ui.add(
                            egui::Button::new("Delete").fill(egui::Color32::from_rgb(176, 0, 32)),
                        );
                        if delete_btn.clicked() {
                            should_delete = true;
                            should_close = true;
                        }
                    });
                } else {
                    ui.label("No beacon selected for deletion.");
                    if ui.button("Close").clicked() {
                        should_close = true;
                    }
                }
            });

            if should_delete {
                if let Some(beacon_id) = &beacon_id_to_delete {
                    if let Err(err) = self.delete_beacon(beacon_id) {
                        eprintln!("Failed to delete beacon: {}", err);
                    }
                }
            }

            if should_close {
                self.delete_modal_open = false;
                self.beacon_to_delete = None;
            }
        }
    }
}
