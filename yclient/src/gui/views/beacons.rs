use crate::gui::client::GuiClient;
use crate::models::Tab;
use egui::{Color32, Ui};
use egui_dock::{DockArea, DockState, Style, TabViewer};
use egui_extras::{Column, TableBuilder};

// Define SimpleTab struct locally to avoid borrowing issues
#[derive(Clone)]
struct SimpleTab {
    id: String,
}

impl GuiClient {
    /// Render the beacons view with table and dock area for tabs
    pub fn render_beacons_view(&mut self, ui: &mut Ui) {
        // Beacons table panel
        egui::TopBottomPanel::top("beacons")
            .resizable(true)
            .default_height(200.0)
            .min_height(100.0)
            .show_inside(ui, |ui| {
                egui::ScrollArea::vertical()
                    .id_salt("beacons_scroll")
                    .show(ui, |ui| {
                        self.render_beacons_table(ui);
                    });
            });

        // Use DockArea for tabs
        egui::CentralPanel::default().show_inside(ui, |ui| {
            if self.active_sessions.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(50.0);
                    ui.label("Click on a beacon to interact");
                });
            } else {
                // Create custom style with red accent color
                let mut style = Style::default();
                style.tab_bar.bg_fill = ui.visuals().widgets.inactive.bg_fill;
                style.tab_bar.hline_color = Color32::from_rgb(220, 80, 80);
                // Don't set corner radius directly as it expects a different type

                // Create a simple dock state with the same tabs
                let mut simple_dock_state = DockState::<SimpleTab>::new(vec![]);

                // Add all current tabs to the new dock state
                for (_, tab) in self.dock_state.iter_all_tabs() {
                    let Tab::Beacon(id) = tab;
                    let simple_tab = SimpleTab { id: id.clone() };
                    simple_dock_state.push_to_focused_leaf(simple_tab);
                }

                // Define a struct right here to avoid lifetime issues
                struct LocalTabViewer<'a> {
                    gui_client: &'a mut GuiClient,
                }

                impl<'a> TabViewer for LocalTabViewer<'a> {
                    type Tab = SimpleTab;

                    fn title(&mut self, tab: &mut Self::Tab) -> egui::WidgetText {
                        tab.id.clone().into()
                    }

                    fn ui(&mut self, ui: &mut egui::Ui, tab: &mut Self::Tab) {
                        let session_idx = self.gui_client.find_or_create_session(&tab.id);
                        self.gui_client.render_beacon_session(ui, session_idx);
                    }

                    fn on_close(&mut self, tab: &mut Self::Tab) -> bool {
                        // 1. Remove the session
                        if let Some(idx) = self
                            .gui_client
                            .active_sessions
                            .iter()
                            .position(|s| &s.beacon_id == &tab.id)
                        {
                            self.gui_client.active_sessions.remove(idx);
                        }

                        // 2. Remove the tab from the dock_state
                        let beacon_id = tab.id.clone();
                        let tab_to_find = Tab::Beacon(beacon_id.clone());

                        // Use the retain_tabs method to filter out this tab
                        // This avoids all the complex borrowing and iteration issues
                        self.gui_client.dock_state.retain_tabs(|t| {
                            if let Tab::Beacon(id) = t {
                                id != &beacon_id
                            } else {
                                true
                            }
                        });

                        // Return true to allow the tab to close
                        true
                    }
                }

                let mut tab_viewer = LocalTabViewer { gui_client: self };

                // Show the simple dock state
                DockArea::new(&mut simple_dock_state)
                    .style(style)
                    .show_inside(ui, &mut tab_viewer);
            }
        });
    }

    /// Render the table of beacons
    pub fn render_beacons_table(&mut self, ui: &mut Ui) {
        if let Ok(beacons) = self.beacons.lock() {
            if beacons.is_empty() {
                ui.vertical_centered(|ui| {
                    ui.add_space(20.0);
                    ui.label("⚠ No agents connected");
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
                .column(Column::auto().at_least(100.0).resizable(true)) // ID
                .column(Column::auto().at_least(80.0).resizable(true)) // Status
                .column(Column::auto().at_least(120.0).resizable(true)) // Hostname
                .column(Column::auto().at_least(100.0).resizable(true)) // Username
                .column(Column::auto().at_least(120.0).resizable(true)) // OS Version
                .column(Column::remainder().at_least(150.0)); // Last Seen

            table
                .header(20.0, |mut header| {
                    header.col(|ui| {
                        ui.strong("ID");
                    });
                    header.col(|ui| {
                        ui.strong("Status");
                    });
                    header.col(|ui| {
                        ui.strong("Hostname");
                    });
                    header.col(|ui| {
                        ui.strong("Username");
                    });
                    header.col(|ui| {
                        ui.strong("OS Version");
                    });
                    header.col(|ui| {
                        ui.strong("Last Seen");
                    });
                })
                .body(|mut body| {
                    let row_height = 30.0;

                    for beacon in &beacon_data {
                        let is_active = self
                            .active_sessions
                            .iter()
                            .any(|s| s.beacon_id == beacon.id);
                        let beacon_id = beacon.id.clone(); // Clone for the closure

                        body.row(row_height, |mut row| {
                            row.col(|ui| {
                                let response = ui.selectable_label(is_active, &beacon_id);
                                if response.clicked() {
                                    // Store the beacon ID to open a tab later
                                    ui.ctx().data_mut(|data| {
                                        data.insert_temp(
                                            egui::Id::new("selected_beacon"),
                                            beacon_id.clone(),
                                        )
                                    });
                                }
                                response.context_menu(|ui| {
                                    if ui.button("Interact").clicked() {
                                        ui.ctx().data_mut(|data| {
                                            data.insert_temp(
                                                egui::Id::new("selected_beacon"),
                                                beacon_id.clone(),
                                            )
                                        });
                                        ui.close_menu();
                                    }
                                });
                            });

                            row.col(|ui| {
                                ui.label(&beacon.status);
                            });
                            row.col(|ui| {
                                ui.label(beacon.hostname.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(beacon.username.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(beacon.os_version.as_deref().unwrap_or("N/A"));
                            });
                            row.col(|ui| {
                                ui.label(&beacon.last_seen);
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

        // Check if tab already exists - compare tab variant contents directly
        let tab_exists = self.dock_state.iter_all_tabs().any(|(_, t)| {
            let Tab::Beacon(ref id) = t;
            let Tab::Beacon(ref tab_id) = tab;
            id == tab_id
        });

        if !tab_exists {
            // Find or create the session
            self.find_or_create_session(beacon_id);

            // Add tab to the dock area
            self.dock_state.push_to_focused_leaf(tab);
        }
    }
}
