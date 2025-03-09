use eframe::egui;
use egui::{Color32, Pos2, Rect, Response, RichText, Sense, Stroke, Ui, Vec2};
use walkers::{sources::OpenStreetMap, HttpTiles, Map, MapMemory, Plugin, Position, Projector};

use crate::gui::client::GuiClient;
use crate::models::{Beacon, Tab, View};
use egui_phosphor::regular;

/// Plugin for displaying beacons on the map
struct BeaconMapPlugin<'a> {
    beacons: &'a [Beacon],
}

impl<'a> BeaconMapPlugin<'a> {
    fn new(beacons: &'a [Beacon]) -> Self {
        Self { beacons }
    }
}

// Helper struct to store marker data
struct MarkerData {
    pos: Pos2,
    rect: Rect,
    beacon: Beacon,
}

impl Plugin for BeaconMapPlugin<'_> {
    fn run(self: Box<Self>, ui: &mut Ui, response: &Response, projector: &Projector) {
        // First pass: Collect all marker data
        let markers: Vec<MarkerData> = self
            .beacons
            .iter()
            .map(|beacon| {
                let pos = Position::new(beacon.longitude, beacon.latitude);
                let screen_pos = projector.project(pos);
                let marker_pos = Pos2::new(screen_pos.x, screen_pos.y);
                let marker_rect = Rect::from_center_size(marker_pos, Vec2::splat(10.0));

                MarkerData {
                    pos: marker_pos,
                    rect: marker_rect,
                    beacon: beacon.clone(),
                }
            })
            .collect();

        // Second pass: Draw all markers
        let painter = ui.painter();
        for marker in &markers {
            painter.circle_filled(marker.pos, 5.0, Color32::RED);
        }

        // Third pass: Handle interactions
        let mut clicked_beacon = None;
        let mut right_clicked_beacon = None;
        let mut hovered_beacon = None;

        for marker in &markers {
            let marker_response = ui.allocate_rect(marker.rect, Sense::click());

            if marker_response.hovered() {
                hovered_beacon = Some(&marker.beacon);
            }
            if marker_response.clicked() {
                clicked_beacon = Some(marker.beacon.id.clone());
            }
            if marker_response.secondary_clicked() {
                right_clicked_beacon = Some(marker.beacon.id.clone());
            }
        }

        // Handle hover tooltip
        if let Some(beacon) = hovered_beacon {
            egui::show_tooltip(
                ui.ctx(),
                response.layer_id,
                response.id.with("beacon_tooltip"),
                |ui| {
                    ui.label(format!("ID: {}", beacon.id));
                    ui.label(format!("Status: {}", beacon.status));
                    ui.label(format!("Last Seen: {}", beacon.last_seen));
                    ui.label(format!(
                        "Hostname: {}",
                        beacon.hostname.as_deref().unwrap_or("Unknown")
                    ));
                    ui.label(format!(
                        "Username: {}",
                        beacon.username.as_deref().unwrap_or("Unknown")
                    ));
                    ui.label(format!(
                        "OS: {}",
                        beacon.os_version.as_deref().unwrap_or("Unknown")
                    ));
                },
            );
        }

        // Handle clicks
        if let Some(beacon_id) = clicked_beacon {
            ui.ctx().data_mut(|data| {
                data.insert_temp(egui::Id::new("selected_beacon"), beacon_id);
            });
        }

        if let Some(beacon_id) = right_clicked_beacon {
            ui.ctx().data_mut(|data| {
                data.insert_temp(egui::Id::new("beacon_context_menu"), beacon_id);
            });
        }

        // Handle context menu
        if let Some(beacon_id) = ui
            .ctx()
            .data_mut(|data| data.get_temp::<String>(egui::Id::new("beacon_context_menu")))
        {
            egui::Window::new("Beacon Actions")
                .fixed_size([150.0, 100.0])
                .anchor(egui::Align2::RIGHT_TOP, [10.0, 10.0])
                .show(ui.ctx(), |ui| {
                    if ui.button("Open Terminal").clicked() {
                        ui.ctx().data_mut(|data| {
                            data.insert_temp(egui::Id::new("selected_beacon"), beacon_id.clone());
                            data.remove::<String>(egui::Id::new("beacon_context_menu"));
                        });
                    }
                    if ui.button("Delete Beacon").clicked() {
                        ui.ctx().data_mut(|data| {
                            data.insert_temp(egui::Id::new("beacon_to_delete"), beacon_id.clone());
                            data.remove::<String>(egui::Id::new("beacon_context_menu"));
                        });
                    }
                });
        }
    }
}

impl GuiClient {
    pub fn render_dashboard_view(&mut self, ui: &mut Ui) {
        // Create a frame for the dashboard
        egui::Frame::new()
            .fill(egui::Color32::from_rgb(20, 20, 20))
            .show(ui, |ui| {
                // Add title
                ui.vertical(|ui| {
                    ui.add_space(10.0);
                    ui.heading(RichText::new(format!("{} Dashboard", regular::CHART_LINE)));
                    ui.add_space(10.0);
                    ui.separator();
                    ui.add_space(10.0);

                    // Create beacon data first so it lives longer than map
                    let beacons_data: Vec<Beacon> = if let Ok(beacons) = self.beacons.try_lock() {
                        beacons.clone()
                    } else {
                        Vec::new()
                    };

                    // Create the plugin first
                    let plugin = BeaconMapPlugin::new(&beacons_data);

                    // Initialize or get map state
                    if self.map_tiles.is_none() {
                        self.map_tiles = Some(HttpTiles::new(OpenStreetMap, ui.ctx().clone()));
                    }
                    if self.map_memory.is_none() {
                        self.map_memory = Some(MapMemory::default());
                    }

                    // Get mutable references to map state
                    let map_tiles = self.map_tiles.as_mut().unwrap();
                    let map_memory = self.map_memory.as_mut().unwrap();

                    // Add the map widget with plugin
                    ui.add(
                        Map::new(
                            Some(map_tiles),
                            map_memory,
                            Position::new(-122.4194, 37.7749), // San Francisco coordinates
                        )
                        .with_plugin(plugin),
                    );

                    // Check if we need to switch to beacons view
                    if ui.ctx().data_mut(|data| {
                        data.get_temp::<String>(egui::Id::new("selected_beacon"))
                            .is_some()
                    }) {
                        self.current_view = View::Beacons;
                    }
                });
            });
    }
}
