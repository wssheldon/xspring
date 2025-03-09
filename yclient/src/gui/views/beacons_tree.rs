use crate::gui::client::GuiClient;
use crate::models::{Beacon, Tab};
use egui::{Color32, RichText, Ui, Vec2};
use egui_dock::DockState;
use egui_phosphor::regular;
use std::sync::MutexGuard;

impl GuiClient {
    /// Render the beacons view with a tree layout on the left and terminal tabs on the right
    pub fn render_beacons_tree_view(&mut self, ui: &mut Ui) {
        let available_size = ui.available_size();

        // Create a frame that takes up the full available space
        egui::Frame::none()
            .fill(egui::Color32::from_rgb(20, 20, 20))
            .show(ui, |ui| {
                // Split the view into left (tree) and right (terminal) panels using Layout
                ui.horizontal(|ui| {
                    // Left panel - Tree view of beacons (fixed width)
                    egui::Frame::none().show(ui, |ui| {
                        ui.set_min_size(Vec2::new(250.0, available_size.y));
                        egui::ScrollArea::vertical()
                            .id_salt("beacons_tree")
                            .show(ui, |ui| {
                                self.render_beacons_tree(ui);
                            });
                    });

                    // Add a separator
                    ui.separator();

                    // Right panel - Terminal tabs and content (takes remaining space)
                    ui.with_layout(
                        egui::Layout::top_down(egui::Align::LEFT).with_cross_justify(true),
                        |ui| {
                            ui.set_min_size(Vec2::new(ui.available_width(), available_size.y));
                            if self.active_sessions.is_empty() {
                                ui.vertical_centered(|ui| {
                                    ui.add_space(50.0);
                                    ui.label("Select a beacon from the tree to interact");
                                });
                            } else {
                                self.render_terminal_tabs(ui);
                            }
                        },
                    );
                });
            });
    }

    fn render_beacons_tree(&mut self, ui: &mut Ui) {
        // First, collect and group all beacons
        let grouped_beacons = {
            if let Ok(beacons) = self.beacons.lock() {
                if beacons.is_empty() {
                    None
                } else {
                    let mut active = Vec::new();
                    let mut idle = Vec::new();
                    let mut offline = Vec::new();

                    // Clone the data we need
                    for beacon in beacons.iter() {
                        let beacon_data = (
                            beacon.id.clone(),
                            beacon
                                .hostname
                                .clone()
                                .unwrap_or_else(|| "Unknown".to_string()),
                            beacon.status.clone(),
                        );
                        match beacon.status.as_str() {
                            "active" => active.push(beacon_data),
                            "idle" => idle.push(beacon_data),
                            _ => offline.push(beacon_data),
                        }
                    }
                    Some((active, idle, offline))
                }
            } else {
                None
            }
        };

        // Now render the groups
        match grouped_beacons {
            None => {
                ui.vertical_centered(|ui| {
                    ui.add_space(20.0);
                    ui.label(
                        RichText::new(format!("{} No agents connected", regular::WARNING))
                            .color(Color32::YELLOW),
                    );
                    ui.add_space(10.0);
                });
            }
            Some((active, idle, offline)) => {
                // Render each group
                self.render_beacon_group_new(ui, "Active", &active, Color32::GREEN);
                self.render_beacon_group_new(ui, "Idle", &idle, Color32::YELLOW);
                self.render_beacon_group_new(ui, "Offline", &offline, Color32::RED);
            }
        }
    }

    fn render_beacon_group_new(
        &mut self,
        ui: &mut Ui,
        title: &str,
        beacons: &[(String, String, String)],
        color: Color32,
    ) {
        if beacons.is_empty() {
            return;
        }

        let header_text = format!("{} {} ({})", regular::FOLDER_SIMPLE, title, beacons.len());
        egui::CollapsingHeader::new(RichText::new(header_text).color(color))
            .default_open(true)
            .show(ui, |ui| {
                for (id, hostname, _) in beacons {
                    let is_selected = self
                        .active_sessions
                        .iter()
                        .any(|s| s.is_selected && s.beacon_id == *id);

                    // Get the last seen time for this beacon
                    let (last_seen_time, relative_time) = if let Ok(beacons) = self.beacons.lock() {
                        if let Some(beacon) = beacons.iter().find(|b| b.id == *id) {
                            // Parse the last_seen timestamp
                            if let Ok(timestamp) =
                                chrono::DateTime::parse_from_rfc3339(&beacon.last_seen)
                            {
                                let now = chrono::Local::now();
                                let duration = now.signed_duration_since(timestamp);

                                // Format relative time
                                let relative = if duration.num_seconds() < 60 {
                                    "just now".to_string()
                                } else if duration.num_minutes() < 60 {
                                    format!("{}m ago", duration.num_minutes())
                                } else if duration.num_hours() < 24 {
                                    format!("{}h ago", duration.num_hours())
                                } else {
                                    format!("{}d ago", duration.num_days())
                                };

                                // Format last seen time as HH:MM
                                let time_str = timestamp.format("%H:%M").to_string();
                                (time_str, relative)
                            } else {
                                ("??:??".to_string(), "unknown".to_string())
                            }
                        } else {
                            ("??:??".to_string(), "unknown".to_string())
                        }
                    } else {
                        ("??:??".to_string(), "unknown".to_string())
                    };

                    ui.horizontal(|ui| {
                        let beacon_text =
                            RichText::new(format!("{} {}", regular::DESKTOP, hostname)).color(
                                if is_selected {
                                    ui.style().visuals.selection.stroke.color
                                } else {
                                    ui.style().visuals.text_color()
                                },
                            );

                        let time_text =
                            RichText::new(format!(" ({} - {})", last_seen_time, relative_time))
                                .weak()
                                .color(if is_selected {
                                    ui.style()
                                        .visuals
                                        .selection
                                        .stroke
                                        .color
                                        .gamma_multiply(0.7)
                                } else {
                                    ui.style().visuals.text_color().gamma_multiply(0.7)
                                });

                        let response = ui.selectable_label(is_selected, beacon_text);
                        let was_clicked = response.clicked();
                        ui.label(time_text);

                        // Add hover tooltip with detailed information
                        if response.hovered() {
                            if let Ok(beacons) = self.beacons.lock() {
                                if let Some(beacon) = beacons.iter().find(|b| b.id == *id) {
                                    let os_info = beacon.os_version.as_deref().unwrap_or("Unknown");
                                    let username = beacon.username.as_deref().unwrap_or("Unknown");
                                    let last_seen = &beacon.last_seen;

                                    response.on_hover_ui(|ui| {
                                        ui.set_min_width(200.0);
                                        ui.vertical(|ui| {
                                            ui.label(RichText::new(format!(
                                                "{} ID: {}",
                                                regular::IDENTIFICATION_BADGE,
                                                id
                                            )));
                                            ui.label(RichText::new(format!(
                                                "{} OS: {}",
                                                regular::GEAR,
                                                os_info
                                            )));
                                            ui.label(RichText::new(format!(
                                                "{} User: {}",
                                                regular::USER,
                                                username
                                            )));
                                            ui.label(RichText::new(format!(
                                                "{} Last Seen: {}",
                                                regular::CLOCK,
                                                last_seen
                                            )));
                                        });
                                    });
                                }
                            }
                        }

                        if was_clicked {
                            self.handle_beacon_selection(id);
                        }
                    });
                }
            });
    }

    fn render_terminal_tabs(&mut self, ui: &mut Ui) {
        // Create a frame for the entire terminal area
        egui::Frame::none()
            .fill(ui.style().visuals.window_fill)
            .show(ui, |ui| {
                // Tab bar at the top
                ui.horizontal(|ui| {
                    let mut session_to_select = None;
                    let mut session_to_remove = None;

                    for (idx, session) in self.active_sessions.iter().enumerate() {
                        let selected = session.is_selected;
                        // Get the hostname for the beacon
                        let display_name = if let Ok(beacons) = self.beacons.lock() {
                            beacons
                                .iter()
                                .find(|b| b.id == session.beacon_id)
                                .and_then(|b| b.hostname.clone())
                                .unwrap_or_else(|| session.beacon_id.clone())
                        } else {
                            session.beacon_id.clone()
                        };

                        let text = RichText::new(display_name).color(if selected {
                            ui.visuals().selection.stroke.color
                        } else {
                            ui.visuals().text_color()
                        });

                        ui.horizontal(|ui| {
                            if ui.selectable_label(selected, text).clicked() {
                                session_to_select = Some(idx);
                            }

                            if ui.small_button("❌").clicked() {
                                session_to_remove = Some(idx);
                            }
                        });
                    }

                    // Handle tab selection
                    if let Some(idx) = session_to_select {
                        for session in &mut self.active_sessions {
                            session.is_selected = false;
                        }
                        if idx < self.active_sessions.len() {
                            self.active_sessions[idx].is_selected = true;
                        }
                    }

                    // Handle tab removal
                    if let Some(idx) = session_to_remove {
                        if idx < self.active_sessions.len() {
                            let beacon_id = self.active_sessions[idx].beacon_id.clone();
                            self.active_sessions.remove(idx);

                            // Update dock state
                            self.dock_state.retain_tabs(|t| {
                                if let Tab::Beacon(id) = t {
                                    id != &beacon_id
                                } else {
                                    true
                                }
                            });

                            // Select another session if needed
                            if !self.active_sessions.is_empty()
                                && self.active_sessions.iter().all(|s| !s.is_selected)
                            {
                                self.active_sessions[0].is_selected = true;
                            }
                        }
                    }
                });

                // Separator between tabs and content
                ui.separator();

                // Terminal content area
                if let Some(active_idx) = self.active_sessions.iter().position(|s| s.is_selected) {
                    let beacon_id = self.active_sessions[active_idx].beacon_id.clone();
                    let session_idx = self.find_or_create_session(&beacon_id);
                    self.render_beacon_session(ui, session_idx);
                } else if !self.active_sessions.is_empty() {
                    let beacon_id = self.active_sessions[0].beacon_id.clone();
                    let session_idx = self.find_or_create_session(&beacon_id);
                    self.render_beacon_session(ui, session_idx);
                }
            });
    }

    fn handle_beacon_selection(&mut self, beacon_id: &str) {
        // Check if this beacon is already in active sessions
        if let Some(idx) = self
            .active_sessions
            .iter()
            .position(|s| s.beacon_id == beacon_id)
        {
            // Just select it if it exists
            for session in &mut self.active_sessions {
                session.is_selected = session.beacon_id == beacon_id;
            }
        } else {
            // Add new session
            for session in &mut self.active_sessions {
                session.is_selected = false;
            }
            // Create a new session using the proper constructor
            let new_session = crate::models::BeaconSession::new(beacon_id.to_string());
            self.active_sessions.push(new_session);
        }
    }
}
