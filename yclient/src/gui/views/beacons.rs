use crate::gui::client::GuiClient;
use crate::models::{Tab, View};
use egui::{Color32, Ui};
use egui_dock::{DockArea, DockState, Style, TabViewer};
use egui_extras::{Column, TableBuilder};
use egui_phosphor::regular;

// Define SimpleTab struct locally to avoid borrowing issues
#[derive(Clone)]
struct SimpleTab {
    id: String,
}

impl GuiClient {
    /// Render the beacons view with table and dock area for tabs
    pub fn render_beacons_view(&mut self, ui: &mut Ui) {
        // Use a more straightforward approach with split views
        let available_height = ui.available_height();
        let mut top_panel_height = self.beacon_panel_height;

        // Create a frame for the top panel (beacon table)
        egui::Frame::none()
            .fill(ui.style().visuals.panel_fill)
            .outer_margin(1.0)
            .show(ui, |ui| {
                // Reserve space for the top panel
                let top_panel_rect = egui::Rect::from_min_size(
                    ui.min_rect().min,
                    egui::vec2(ui.available_width(), top_panel_height),
                );

                // Add a resize handle
                let resize_id = ui.id().with("resize_handle");
                let resize_rect = egui::Rect::from_min_max(
                    egui::pos2(top_panel_rect.min.x, top_panel_rect.max.y - 4.0),
                    egui::pos2(top_panel_rect.max.x, top_panel_rect.max.y + 4.0),
                );

                let resize_response = ui.interact(resize_rect, resize_id, egui::Sense::drag());

                if resize_response.dragged() {
                    top_panel_height += resize_response.drag_delta().y;
                    // Ensure reasonable bounds
                    top_panel_height = top_panel_height.clamp(100.0, available_height - 100.0);
                    // Save the height for next frame
                    self.beacon_panel_height = top_panel_height;
                }

                // Change cursor to indicate resizable
                if resize_response.hovered() {
                    ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeVertical);
                }

                // Draw the resize handle
                let visuals = ui.style().visuals.widgets.noninteractive;
                ui.painter().rect_filled(
                    resize_rect,
                    0.0,
                    if resize_response.hovered() || resize_response.dragged() {
                        visuals.bg_fill.linear_multiply(1.5)
                    } else {
                        visuals.bg_fill
                    },
                );

                // Beacons table
                let table_rect = top_panel_rect.shrink2(egui::vec2(0.0, 4.0));
                ui.allocate_ui_at_rect(table_rect, |ui| {
                    egui::ScrollArea::vertical()
                        .id_salt("beacons_scroll")
                        .show(ui, |ui| {
                            self.render_beacons_table(ui);
                        });
                });

                // Bottom panel - Interactive part
                let bottom_rect = egui::Rect::from_min_max(
                    egui::pos2(top_panel_rect.min.x, top_panel_rect.max.y + 4.0),
                    ui.max_rect().max,
                );

                ui.allocate_ui_at_rect(bottom_rect, |ui| {
                    if self.active_sessions.is_empty() {
                        ui.vertical_centered(|ui| {
                            ui.add_space(50.0);
                            ui.label("Click on a beacon to interact");
                        });
                    } else {
                        // Instead of using DockArea, we'll render the active session directly
                        // Get the active session ID
                        if !self.active_sessions.is_empty() {
                            // Find the active session index
                            let active_idx = self
                                .active_sessions
                                .iter()
                                .position(|s| s.is_selected)
                                .unwrap_or(0);

                            // Store the active beacon ID
                            let active_beacon_id =
                                self.active_sessions[active_idx].beacon_id.clone();

                            // Tab bar with tabs for all sessions
                            ui.horizontal(|ui| {
                                // We'll collect actions to perform after the loop to avoid borrow checker issues
                                let mut session_to_select = None;
                                let mut session_to_remove = None;

                                // Render all session tabs
                                for (idx, session) in self.active_sessions.iter().enumerate() {
                                    let selected = session.is_selected;
                                    let beacon_id = &session.beacon_id;

                                    let text = egui::RichText::new(beacon_id).color(if selected {
                                        ui.visuals().selection.stroke.color
                                    } else {
                                        ui.visuals().text_color()
                                    });

                                    // Tab button
                                    ui.horizontal(|ui| {
                                        if ui.selectable_label(selected, text).clicked() {
                                            session_to_select = Some(idx);
                                        }

                                        // Close button
                                        if ui.small_button("❌").clicked() {
                                            session_to_remove = Some(idx);
                                        }
                                    });
                                }

                                // Apply the actions after the loop
                                if let Some(idx) = session_to_select {
                                    // First deselect all
                                    for session in &mut self.active_sessions {
                                        session.is_selected = false;
                                    }
                                    // Then select the one that was clicked
                                    if idx < self.active_sessions.len() {
                                        self.active_sessions[idx].is_selected = true;
                                    }
                                }

                                if let Some(idx) = session_to_remove {
                                    if idx < self.active_sessions.len() {
                                        let beacon_id = self.active_sessions[idx].beacon_id.clone();

                                        // Remove the session
                                        self.active_sessions.remove(idx);

                                        // Also update the dock state
                                        self.dock_state.retain_tabs(|t| {
                                            if let Tab::Beacon(id) = t {
                                                id != &beacon_id
                                            } else {
                                                true
                                            }
                                        });

                                        // If we removed the active session, select another one
                                        if self.active_sessions.is_empty() {
                                            // No more sessions
                                        } else if self
                                            .active_sessions
                                            .iter()
                                            .all(|s| !s.is_selected)
                                        {
                                            // Select the first session if none are selected
                                            self.active_sessions[0].is_selected = true;
                                        }
                                    }
                                }
                            });

                            // After handling all the tab UI, render the active session
                            if let Some(active_idx) =
                                self.active_sessions.iter().position(|s| s.is_selected)
                            {
                                let beacon_id = self.active_sessions[active_idx].beacon_id.clone();
                                let session_idx = self.find_or_create_session(&beacon_id);
                                self.render_beacon_session(ui, session_idx);
                            } else if !self.active_sessions.is_empty() {
                                // Fallback - render the first session if none are selected
                                let beacon_id = self.active_sessions[0].beacon_id.clone();
                                let session_idx = self.find_or_create_session(&beacon_id);
                                self.render_beacon_session(ui, session_idx);
                            }
                        }
                    }
                });
            });
    }

    /// Render the table of beacons
    pub fn render_beacons_table(&mut self, ui: &mut Ui) {
        if let Ok(beacons) = self.beacons.lock() {
            if beacons.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(20.0);
                    ui.label(
                        egui::RichText::new(format!("{} No agents connected", regular::WARNING))
                            .color(Color32::YELLOW),
                    );
                    ui.add_space(10.0);
                });
                return;
            }

            // Clone beacon data to avoid borrow checker issues
            let beacon_data = beacons.clone();
            drop(beacons); // Release the lock

            let table = TableBuilder::new(ui)
                .striped(true)
                .resizable(true)
                .cell_layout(egui::Layout::left_to_right(egui::Align::Center))
                .column(Column::auto().at_least(30.0)) // OS icon column
                .column(Column::auto().at_least(100.0).resizable(true)) // ID
                .column(Column::auto().at_least(80.0).resizable(true)) // Status
                .column(Column::auto().at_least(120.0).resizable(true)) // Hostname
                .column(Column::auto().at_least(100.0).resizable(true)) // Username
                .column(Column::auto().at_least(120.0).resizable(true)) // OS Version
                .column(Column::remainder().at_least(150.0)); // Last Seen

            table
                .header(20.0, |mut header| {
                    header.col(|ui| {
                        ui.label(""); // Empty header for OS icon
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!(
                            "{} ID",
                            regular::IDENTIFICATION_BADGE
                        )));
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!("{} Status", regular::ACTIVITY)));
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!(
                            "{} Hostname",
                            regular::DESKTOP
                        )));
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!("{} User", regular::USER)));
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!("{} OS", regular::GEAR)));
                    });
                    header.col(|ui| {
                        ui.label(egui::RichText::new(format!("{} Last Seen", regular::CLOCK)));
                    });
                })
                .body(|mut body| {
                    let row_height = 30.0;

                    for beacon in &beacon_data {
                        let is_active = self
                            .active_sessions
                            .iter()
                            .any(|s| s.beacon_id == beacon.id);
                        let beacon_id = beacon.id.clone();

                        body.row(row_height, |mut row| {
                            // OS icon column
                            row.col(|ui| {
                                ui.label(egui::RichText::new(regular::APPLE_LOGO).size(16.0));
                            });

                            // ID column with selectable and context menu
                            row.col(|ui| {
                                let response = ui.selectable_label(
                                    is_active,
                                    egui::RichText::new(&beacon_id).color(if is_active {
                                        Color32::LIGHT_BLUE
                                    } else {
                                        ui.style().visuals.text_color()
                                    }),
                                );

                                if response.clicked() {
                                    ui.ctx().data_mut(|data| {
                                        data.insert_temp(
                                            egui::Id::new("selected_beacon"),
                                            beacon_id.clone(),
                                        )
                                    });
                                }

                                response.context_menu(|ui| {
                                    if ui
                                        .button(egui::RichText::new(format!(
                                            "{} Interact",
                                            regular::TERMINAL
                                        )))
                                        .clicked()
                                    {
                                        ui.ctx().data_mut(|data| {
                                            data.insert_temp(
                                                egui::Id::new("selected_beacon"),
                                                beacon_id.clone(),
                                            )
                                        });
                                        ui.close_menu();
                                    }

                                    ui.separator();

                                    if ui
                                        .button(
                                            egui::RichText::new(format!(
                                                "{} Delete",
                                                regular::TRASH
                                            ))
                                            .color(Color32::from_rgb(220, 50, 50)),
                                        )
                                        .clicked()
                                    {
                                        ui.ctx().data_mut(|data| {
                                            data.insert_temp(
                                                egui::Id::new("beacon_to_delete"),
                                                beacon_id.clone(),
                                            )
                                        });
                                        ui.close_menu();
                                    }
                                });
                            });

                            row.col(|ui| {
                                let status_icon = if beacon.status == "active" {
                                    regular::CHECK_CIRCLE
                                } else {
                                    regular::X_CIRCLE
                                };
                                ui.label(egui::RichText::new(format!(
                                    "{} {}",
                                    status_icon, beacon.status
                                )));
                            });

                            row.col(|ui| {
                                ui.label(egui::RichText::new(format!(
                                    "{}",
                                    beacon.hostname.as_deref().unwrap_or("N/A")
                                )));
                            });

                            row.col(|ui| {
                                ui.label(egui::RichText::new(format!(
                                    "{}",
                                    beacon.username.as_deref().unwrap_or("N/A")
                                )));
                            });

                            row.col(|ui| {
                                ui.label(egui::RichText::new(format!(
                                    "{}",
                                    beacon.os_version.as_deref().unwrap_or("N/A")
                                )));
                            });

                            row.col(|ui| {
                                ui.label(egui::RichText::new(format!("{}", beacon.last_seen)));
                            });
                        });
                    }
                });
        }
    }

    /// Open a beacon tab or focus the existing one
    pub fn open_beacon_tab(&mut self, beacon_id: &str) {
        // Create a new tab for this beacon if not already open
        let tab = Tab::Beacon(beacon_id.to_string());

        // Check if tab already exists
        let tab_exists = self.dock_state.iter_all_tabs().any(|(_, t)| {
            let Tab::Beacon(ref id) = t;
            let Tab::Beacon(ref tab_id) = tab;
            id == tab_id
        });

        if !tab_exists {
            // Find or create the session
            let session_idx = self.find_or_create_session(beacon_id);

            // Deselect all other sessions
            for session in &mut self.active_sessions {
                session.is_selected = false;
            }

            // Set the new session as selected
            if session_idx < self.active_sessions.len() {
                self.active_sessions[session_idx].is_selected = true;
            }

            // Add tab to the dock area
            self.dock_state.push_to_focused_leaf(tab);
        } else {
            // Session already exists, just update selection state
            for session in &mut self.active_sessions {
                // Update selection state
                session.is_selected = session.beacon_id == beacon_id;
            }
        }

        // Update the current view to beacons
        self.current_view = View::Beacons;
    }
}
